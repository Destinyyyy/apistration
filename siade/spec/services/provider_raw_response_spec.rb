require 'rails_helper'

RSpec.describe ProviderRawResponse do
  subject(:raw_response) { described_class.new(response) }

  context 'with a Net::HTTP response' do
    let(:response) do
      Net::HTTPNotFound.new('1.1', '404', 'Not Found').tap do |net_response|
        net_response['Content-Type'] = 'application/json'
        net_response.instance_variable_set(:@body, '{"message":"nope"}')
        net_response.instance_variable_set(:@read, true)
      end
    end

    it 'extracts status, headers and raw body' do
      expect(raw_response.as_meta).to eq(
        'status' => 404,
        'headers' => { 'content-type' => 'application/json' },
        'body' => '{"message":"nope"}'
      )
    end
  end

  context 'with a response duck typing headers and status' do
    let(:response) do
      OpenStruct.new(
        headers: { 'Content-Type' => 'application/json' },
        body: '{"message":"tea"}',
        status: 418
      )
    end

    it 'extracts the debugging log payload' do
      expect(raw_response.as_debugging_log).to eq(
        header: { 'Content-Type' => 'application/json' },
        body: Base64.strict_encode64('{"message":"tea"}'),
        status: 418
      )
    end
  end

  context 'with a response without headers nor status' do
    let(:response) { OpenStruct.new(body: 'whatever') }

    it 'falls back on empty values' do
      expect(raw_response.as_meta).to eq(
        'status' => nil,
        'headers' => {},
        'body' => 'whatever'
      )
    end
  end

  context 'with a binary body' do
    let(:body) { "%PDF-1.7\r\n1 0 obj\x00\x01stream".dup.force_encoding(Encoding::ASCII_8BIT) }
    let(:response) { OpenStruct.new(body:) }

    it 'describes the body instead of exposing it' do
      expect(raw_response.as_meta['body']).to eq("[contenu binaire, #{body.bytesize} octets]")
    end
  end

  context 'with a binary body the provider encoded in base64' do
    let(:pdf) { "%PDF-1.7\r\n#{"1 0 obj\x00\x01stream" * 100}".force_encoding(Encoding::ASCII_8BIT) }
    let(:body) { Base64.strict_encode64(pdf) }
    let(:response) { OpenStruct.new(body:) }

    it 'describes the body instead of exposing it' do
      expect(raw_response.as_meta['body']).to eq("[contenu binaire, #{body.bytesize} octets]")
    end
  end

  context 'with a long textual body' do
    let(:body) { 'a' * (described_class::MIN_BASE64_BODY_SIZE * 2) }
    let(:response) { OpenStruct.new(body:) }

    it 'is not mistaken for base64 encoded binary' do
      expect(raw_response.as_meta['body']).to eq(body)
    end
  end

  context 'with a body larger than the exposed size' do
    let(:body) { "{\"documents\":\"#{'a' * (described_class::MAX_EXPOSED_BODY_SIZE * 2)}\"}" }
    let(:response) { OpenStruct.new(body:) }

    it 'truncates it and states the original size' do
      expect(raw_response.as_meta['body']).to start_with('{"documents":"aaa')
      expect(raw_response.as_meta['body']).to end_with("… [tronqué, #{body.bytesize} octets au total]")
      expect(raw_response.as_meta['body'].bytesize).to be < body.bytesize
    end
  end

  context 'with a body which is not valid UTF-8' do
    let(:body) { "%PDF-1.4\xC3\x28".dup.force_encoding(Encoding::ASCII_8BIT) }
    let(:response) { OpenStruct.new(body:) }

    it 'scrubs the body so it can be rendered as JSON' do
      expect { raw_response.as_meta.to_json }.not_to raise_error
      expect(raw_response.as_meta['body']).to start_with('%PDF-1.4')
    end

    it 'leaves the original body untouched' do
      raw_response.as_meta

      expect(body.encoding).to eq(Encoding::ASCII_8BIT)
    end
  end
end
