# frozen_string_literal: true

# Lightweight S3-compatible client for Cloudflare R2.
# Replaces the full aws-sdk-s3 gem (~80MB memory) with direct HTTP calls
# using AWS Signature V4 signing (~0MB additional memory).
#
# Only implements the two operations we need: PUT and GET object.
#
class R2Client
  ALGORITHM = "AWS4-HMAC-SHA256"
  SERVICE = "s3"
  REGION = "auto"

  def initialize
    @access_key_id = ENV["CLOUDFLARE_R2_ACCESS_KEY_ID"]
    @secret_access_key = ENV["CLOUDFLARE_R2_SECRET_ACCESS_KEY"]
    @endpoint = ENV["CLOUDFLARE_R2_ENDPOINT"] # https://ACCOUNT_ID.r2.cloudflarestorage.com
  end

  def configured?
    @access_key_id.present? && @secret_access_key.present? && @endpoint.present?
  end

  # PUT object to R2
  # @return [Boolean] true if upload succeeded
  def put_object(bucket:, key:, body:, content_type: "application/octet-stream")
    uri = build_uri(bucket, key)
    request = Net::HTTP::Put.new(uri)
    request.body = body
    request["Content-Type"] = content_type

    sign_request!(request, uri, body)
    response = execute(uri, request)

    unless response.is_a?(Net::HTTPSuccess)
      raise "R2 PUT failed: #{response.code} #{response.body&.truncate(200)}"
    end

    true
  end

  # GET object from R2
  # @return [String] binary file data
  def get_object(bucket:, key:)
    uri = build_uri(bucket, key)
    request = Net::HTTP::Get.new(uri)

    sign_request!(request, uri, "")
    response = execute(uri, request)

    unless response.is_a?(Net::HTTPSuccess)
      raise "R2 GET failed: #{response.code} #{response.body&.truncate(200)}"
    end

    response.body
  end

  private

  def build_uri(bucket, key)
    URI.parse("#{@endpoint}/#{bucket}/#{key}")
  end

  def execute(uri, request)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 10
    http.read_timeout = 30
    http.request(request)
  end

  # AWS Signature V4 signing
  # Reference: https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_sigv.html
  def sign_request!(request, uri, body)
    now = Time.now.utc
    datestamp = now.strftime("%Y%m%d")
    amz_date = now.strftime("%Y%m%dT%H%M%SZ")

    request["x-amz-date"] = amz_date
    request["x-amz-content-sha256"] = sha256_hex(body)
    request["Host"] = uri.host

    # Step 1: Canonical request
    canonical_headers = "host:#{uri.host}\nx-amz-content-sha256:#{sha256_hex(body)}\nx-amz-date:#{amz_date}\n"
    signed_headers = "host;x-amz-content-sha256;x-amz-date"

    canonical_request = [
      request.method,
      uri.path,
      uri.query || "",
      canonical_headers,
      signed_headers,
      sha256_hex(body)
    ].join("\n")

    # Step 2: String to sign
    credential_scope = "#{datestamp}/#{REGION}/#{SERVICE}/aws4_request"
    string_to_sign = [
      ALGORITHM,
      amz_date,
      credential_scope,
      sha256_hex(canonical_request)
    ].join("\n")

    # Step 3: Signing key
    signing_key = derive_signing_key(datestamp)

    # Step 4: Signature
    signature = hmac_hex(signing_key, string_to_sign)

    # Step 5: Authorization header
    request["Authorization"] = "#{ALGORITHM} Credential=#{@access_key_id}/#{credential_scope}, SignedHeaders=#{signed_headers}, Signature=#{signature}"
  end

  def derive_signing_key(datestamp)
    k_date = hmac("AWS4#{@secret_access_key}", datestamp)
    k_region = hmac(k_date, REGION)
    k_service = hmac(k_region, SERVICE)
    hmac(k_service, "aws4_request")
  end

  def hmac(key, data)
    OpenSSL::HMAC.digest("SHA256", key, data)
  end

  def hmac_hex(key, data)
    OpenSSL::HMAC.hexdigest("SHA256", key, data)
  end

  def sha256_hex(data)
    Digest::SHA256.hexdigest(data.to_s)
  end
end
