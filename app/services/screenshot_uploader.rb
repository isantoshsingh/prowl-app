# frozen_string_literal: true

# ScreenshotUploader handles uploading scan screenshots to Cloudflare R2
# and downloading them for AI analysis and email attachments.
#
# R2 is S3-compatible, so we use the aws-sdk-s3 gem with R2's endpoint.
# Zero egress fees — downloads for AI and email are free.
#
# Screenshots are organized by shop slug and product handle:
#   prowl-screenshots/
#     test-store/
#       blue-denim-jacket/
#         scan_123_1709123456.png
#     another-store/
#       classic-tee/
#         scan_456_1709123457.png
#
# Falls back to local tmp/ storage if R2 credentials are not configured
# (development environment).
#
# Usage:
#   uploader = ScreenshotUploader.new
#   url = uploader.upload(screenshot_bytes, scan_id, shop: shop, product_page: page)
#   bytes = uploader.download(url)
#
class ScreenshotUploader
  class UploadError < StandardError; end

  def initialize
    @configured = r2_configured?
  end

  # Uploads screenshot PNG to R2 and returns the public URL.
  # Falls back to local tmp/ storage if R2 is not configured.
  #
  # @param screenshot_data [String] binary PNG data
  # @param scan_id [Integer] scan record ID
  # @param shop [Shop] the shop record (for directory organization)
  # @param product_page [ProductPage] the product page record (for directory organization)
  # @return [String] the public URL or local path
  def upload(screenshot_data, scan_id, shop: nil, product_page: nil)
    return upload_local(screenshot_data, scan_id, shop: shop, product_page: product_page) unless @configured

    key = object_key(scan_id, shop: shop, product_page: product_page)

    client.put_object(
      bucket: bucket,
      key: key,
      body: screenshot_data,
      content_type: "image/png"
    )

    public_url(key)
  rescue Aws::S3::Errors::ServiceError => e
    Rails.logger.error("[ScreenshotUploader] R2 upload failed: #{e.message}, falling back to local")
    upload_local(screenshot_data, scan_id, shop: shop, product_page: product_page)
  rescue StandardError => e
    Rails.logger.error("[ScreenshotUploader] Upload failed: #{e.message}")
    upload_local(screenshot_data, scan_id, shop: shop, product_page: product_page)
  end

  # Downloads screenshot bytes from R2 for AI analysis or email attachment.
  #
  # @param url [String] the public URL or local path
  # @return [String] binary PNG data
  def download(url)
    # Handle local files stored in tmp/
    if url.start_with?("/screenshots/")
      local_path = Rails.root.join("tmp", url.sub(%r{^/}, ""))
      return File.binread(local_path) if File.exist?(local_path)
      raise UploadError, "Local screenshot not found: #{url}"
    end

    # Handle R2 URLs — extract key from public URL
    return download_from_r2(url) if @configured

    raise UploadError, "Cannot download screenshot: R2 not configured and URL is not local"
  rescue Aws::S3::Errors::ServiceError => e
    Rails.logger.error("[ScreenshotUploader] R2 download failed: #{e.message}")
    raise UploadError, "Failed to download screenshot: #{e.message}"
  end

  private

  def r2_configured?
    ENV["CLOUDFLARE_R2_ACCESS_KEY_ID"].present? &&
      ENV["CLOUDFLARE_R2_SECRET_ACCESS_KEY"].present? &&
      ENV["CLOUDFLARE_R2_ENDPOINT"].present?
  end

  def client
    @client ||= begin
      require "aws-sdk-s3"
      Aws::S3::Client.new(
        access_key_id: ENV["CLOUDFLARE_R2_ACCESS_KEY_ID"],
        secret_access_key: ENV["CLOUDFLARE_R2_SECRET_ACCESS_KEY"],
        endpoint: ENV["CLOUDFLARE_R2_ENDPOINT"],
        region: "auto",
        force_path_style: true
      )
    end
  end

  def bucket
    ENV.fetch("CLOUDFLARE_R2_BUCKET", "prowl-screenshots")
  end

  # Builds the R2 object key organized by shop slug and product handle.
  #
  # Examples:
  #   test-store/blue-denim-jacket/scan_123_1709123456.png
  #   test-store/red-sneakers/scan_456_1709123457.png
  #   unknown-shop/unknown-product/scan_789_1709123458.png (fallback)
  def object_key(scan_id, shop: nil, product_page: nil)
    shop_slug = extract_shop_slug(shop)
    product_handle = product_page&.handle.presence || "unknown-product"
    filename = "scan_#{scan_id}_#{Time.current.to_i}.png"

    "#{shop_slug}/#{product_handle}/#{filename}"
  end

  # Extracts the shop slug from the Shopify domain.
  # "test-store.myshopify.com" → "test-store"
  def extract_shop_slug(shop)
    return "unknown-shop" unless shop&.shopify_domain.present?

    shop.shopify_domain.sub(/\.myshopify\.com\z/i, "")
  end

  def public_url(key)
    base_url = ENV.fetch("CLOUDFLARE_R2_PUBLIC_URL", "")
    "#{base_url}/#{key}"
  end

  def download_from_r2(url)
    base_url = ENV.fetch("CLOUDFLARE_R2_PUBLIC_URL", "")
    key = url.sub("#{base_url}/", "")

    response = client.get_object(bucket: bucket, key: key)
    response.body.read
  end

  # Fallback: store screenshot locally in tmp/screenshots/
  # Mirrors the R2 directory structure for consistency.
  def upload_local(screenshot_data, scan_id, shop: nil, product_page: nil)
    shop_slug = extract_shop_slug(shop)
    product_handle = product_page&.handle.presence || "unknown-product"
    filename = "scan_#{scan_id}_#{Time.current.to_i}.png"

    relative_path = File.join("screenshots", shop_slug, product_handle, filename)
    filepath = Rails.root.join("tmp", relative_path)

    FileUtils.mkdir_p(File.dirname(filepath))
    File.binwrite(filepath, screenshot_data)

    Rails.logger.info("[ScreenshotUploader] Stored screenshot locally: #{filepath}")
    "/#{relative_path}"
  end
end
