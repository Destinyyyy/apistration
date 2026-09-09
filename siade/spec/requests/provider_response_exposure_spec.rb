require 'rails_helper'

RSpec.describe 'Provider response exposure', api: :entreprise do
  subject(:payload) do
    get "/v3/insee/sirene/unites_legales/#{siren}",
      params: { context: 'Admin', recipient: '13002526500013', object: 'Debug requête' },
      headers: request_headers

    response_json
  end

  let(:siren) { sirens_insee_v3[:active_GE] }
  let(:request_headers) do
    {
      'Authorization' => "Bearer #{yes_jwt}",
      ProviderResponseDebuggingService::HEADER_NAME => 'true',
      'Cache-Control' => 'no-cache'
    }
  end

  before do
    Siade.credentials[ProviderResponseDebuggingService::CREDENTIALS_KEY] = [yes_jwt_user.token_id]
  end

  after do
    Siade.credentials.delete(ProviderResponseDebuggingService::CREDENTIALS_KEY)
  end

  it 'exposes the raw INSEE response next to the serialized payload', vcr: { cassette_name: 'insee/siren/active_GE_with_token' } do
    provider_response = payload.dig(:meta, :provider_response)

    expect(response).to have_http_status(:ok)
    expect(payload.dig(:data, :siren)).to eq(siren)
    expect(provider_response[:status]).to eq(200)
    expect(JSON.parse(provider_response[:body]).dig('uniteLegale', 'siren')).to eq(siren)
  end

  context 'without the header' do
    let(:request_headers) { { 'Authorization' => "Bearer #{yes_jwt}" } }

    it 'keeps the payload untouched', vcr: { cassette_name: 'insee/siren/active_GE_with_token' } do
      expect(payload[:meta]).not_to have_key(:provider_response)
    end
  end
end
