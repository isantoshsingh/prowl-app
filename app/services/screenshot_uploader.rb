# frozen_string_literal: true

# ScreenshotUploader handles uploading scan screenshots to Cloudflare R2
# and downloading them for AI analysis and email attachments.
#
# Uses R2Client (lightweight HTTP + AWS SigV4) instead of aws-sdk-s3
# to save ~80MB of memory on Heroku.
#
# Screenshots are organized by shop slug and product handle:
#   prowl-screenshots/
#     test-store/
#       blue-denim-jacket/
#         scan_123_1709123456.png
#
# Storage approach:
#   - The R2 object KEY is stored in scans.screenshot_url (not a public URL)
#   - Downloads happen server-side via S3 API (no public access needed)
#
# Falls back to local tmp/ storage if R2 credentials are not configured.
#
# Usage:
#   uploader = ScreenshotUploader.new
#   key = uploader.upload(screenshot_bytes, scan_id, shop: shop, product_page: page)
#   bytes = uploader.download(key)
#
class ScreenshotUploader
  class UploadError < StandardError; end

  def initialize
    @client = R2Client.new
  end

  # Uploads screenshot PNG to R2 and returns the object key.
  # Falls back to local tmp/ storage if R2 is not configured.
  def upload(screenshot_data, scan_id, shop: nil, product_page: nil)
    return upload_local(screenshot_data, scan_id, shop: shop, product_page: product_page) unless @client.configured?

    key = object_key(scan_id, shop: shop, product_page: product_page)

    @client.put_object(
      bucket: bucket,
      key: key,
      body: screenshot_data,
      content_type: "image/png"
    )

    Rails.logger.info("[ScreenshotUploader] Uploaded to R2: #{key}")
    key
  rescue StandardError => e
    Rails.logger.error("[ScreenshotUploader] R2 upload failed: #{e.message}, falling back to local")
    upload_local(screenshot_data, scan_id, shop: shop, product_page: product_page)
  end

  # Downloads screenshot bytes from R2 or local tmp/.
  def download(key_or_path)
    if key_or_path.start_with?("/screenshots/")
      local_path = Rails.root.join("tmp", key_or_path.sub(%r{^/}, ""))
      return File.binread(local_path) if File.exist?(local_path)
      raise UploadError, "Local screenshot not found: #{key_or_path}"
    end

    if @client.configured?
      return @client.get_object(bucket: bucket, key: key_or_path)
    end

    raise UploadError, "Cannot download screenshot: R2 not configured and path is not local"
  rescue UploadError
    raise
  rescue StandardError => e
    Rails.logger.error("[ScreenshotUploader] R2 download failed: #{e.message}")
    raise UploadError, "Failed to download screenshot: #{e.message}"
  end

  private

  def bucket
    ENV.fetch("CLOUDFLARE_R2_BUCKET", "prowl-screenshots")
  end

  def object_key(scan_id, shop: nil, product_page: nil)
    shop_slug = extract_shop_slug(shop)
    product_handle = product_page&.handle.presence || "unknown-product"
    filename = "scan_#{scan_id}_#{Time.current.to_i}.png"

    "#{shop_slug}/#{product_handle}/#{filename}"
  end

  def extract_shop_slug(shop)
    return "unknown-shop" unless shop&.shopify_domain.present?
    shop.shopify_domain.sub(/\.myshopify\.com\z/i, "")
  end

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
