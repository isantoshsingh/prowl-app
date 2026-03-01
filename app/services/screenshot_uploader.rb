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
# Storage approach:
#   - The R2 object KEY is stored in scans.screenshot_url (not a public URL)
#   - Downloads happen server-side via S3 API (no public access needed)
#   - This is more secure — screenshots are never publicly accessible
#
# Falls back to local tmp/ storage if R2 credentials are not configured
# (development environment).
#
# Usage:
#   uploader = ScreenshotUploader.new
#   key = uploader.upload(screenshot_bytes, scan_id, shop: shop, product_page: page)
#   bytes = uploader.download(key)
#
class ScreenshotUploader
  class UploadError < StandardError; end

  def initialize
    @configured = r2_configured?
  end

  # Uploads screenshot PNG to R2 and returns the object key.
  # Falls back to local tmp/ storage if R2 is not configured.
  #
  # @param screenshot_data [String] binary PNG data
  # @param scan_id [Integer] scan record ID
  # @param shop [Shop] the shop record (for directory organization)
  # @param product_page [ProductPage] the product page record (for directory organization)
  # @return [String] the R2 object key or local path
  def upload(screenshot_data, scan_id, shop: nil, product_page: nil)
    return upload_local(screenshot_data, scan_id, shop: shop, product_page: product_page) unless @configured

    key = object_key(scan_id, shop: shop, product_page: product_page)

    client.put_object(
      bucket: bucket,
      key: key,
      body: screenshot_data,
      content_type: "image/png"
    )

    Rails.logger.info("[ScreenshotUploader] Uploaded to R2: #{key}")
    key
  rescue Aws::S3::Errors::ServiceError => e
    Rails.logger.error("[ScreenshotUploader] R2 upload failed: #{e.message}, falling back to local")
    upload_local(screenshot_data, scan_id, shop: shop, product_page: product_page)
  rescue StandardError => e
    Rails.logger.error("[ScreenshotUploader] Upload failed: #{e.message}")
    upload_local(screenshot_data, scan_id, shop: shop, product_page: product_page)
  end

  # Downloads screenshot bytes from R2 (via S3 API) or local tmp/.
  # Used by AiIssueAnalyzer and AlertMailer for server-side processing.
  #
  # @param key_or_path [String] the R2 object key or local path
  # @return [String] binary PNG data
  def download(key_or_path)
    # Handle local files stored in tmp/
    if key_or_path.start_with?("/screenshots/")
      local_path = Rails.root.join("tmp", key_or_path.sub(%r{^/}, ""))
      # Prevent path traversal — ensure resolved path stays within tmp/screenshots/
      safe_dir = Rails.root.join("tmp", "screenshots").to_s
      unless File.expand_path(local_path).start_with?(safe_dir)
        raise UploadError, "Invalid screenshot path: #{key_or_path}"
      end
      return File.binread(local_path) if File.exist?(local_path)
      raise UploadError, "Local screenshot not found: #{key_or_path}"
    end

    # Download from R2 via S3 API (private, no public access needed)
    if @configured
      response = client.get_object(bucket: bucket, key: key_or_path)
      return response.body.read
    end

    raise UploadError, "Cannot download screenshot: R2 not configured and path is not local"
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
