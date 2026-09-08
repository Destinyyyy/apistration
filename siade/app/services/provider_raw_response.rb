class ProviderRawResponse
  MAX_EXPOSED_BODY_SIZE = 64.kilobytes
  BINARY_DETECTION_WINDOW = 8.kilobytes
  MIN_BASE64_BODY_SIZE = 1.kilobyte
  BASE64_CONTENT = %r{\A[A-Za-z0-9+/\s]+={0,2}\z}

  def initialize(response)
    @response = response
  end

  def status
    raw_status&.to_i
  end

  def headers
    response.try(:headers) ||
      response.try(:each_header)&.to_h ||
      {}
  end

  def body
    response.try(:body).to_s
  end

  def body_base64
    Base64.strict_encode64(body)
  end

  def as_debugging_log
    {
      header: headers,
      body: body_base64,
      status:
    }
  end

  def as_meta
    {
      'status' => status,
      'headers' => headers,
      'body' => exposed_body
    }
  end

  private

  attr_reader :response

  def raw_status
    response.try(:status) || response.try(:code)
  end

  def exposed_body
    return "[contenu binaire, #{body.bytesize} octets]" if binary?

    truncate(utf8_body)
  end

  def binary?
    null_byte?(sample) || null_byte?(decoded_base64_sample)
  end

  def sample
    @sample ||= body.byteslice(0, BINARY_DETECTION_WINDOW).to_s.force_encoding(Encoding::ASCII_8BIT)
  end

  def decoded_base64_sample
    return '' unless sample.bytesize >= MIN_BASE64_BODY_SIZE && sample.match?(BASE64_CONTENT)

    Base64.decode64(sample)
  end

  def null_byte?(content)
    content.include?("\x00")
  end

  def utf8_body
    body.dup.force_encoding(Encoding::UTF_8).scrub
  end

  def truncate(content)
    return content if content.bytesize <= MAX_EXPOSED_BODY_SIZE

    "#{content.byteslice(0, MAX_EXPOSED_BODY_SIZE).scrub}… [tronqué, #{body.bytesize} octets au total]"
  end
end
