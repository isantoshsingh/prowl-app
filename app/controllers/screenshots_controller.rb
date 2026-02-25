# frozen_string_literal: true

# ScreenshotsController serves scan screenshots to the browser.
# Downloads from Cloudflare R2 in production, local tmp/ in development.
#
# Used by views to display screenshots inline:
#   <img src="<%= scan_screenshot_path(scan) %>" />
#
# The scan.screenshot_url stores either:
#   - An R2 object key: "test-store/blue-jacket/scan_123_xxx.png"
#   - A local path: "/screenshots/test-store/blue-jacket/scan_123_xxx.png"
#
class ScreenshotsController < AuthenticatedController
  def show
    key = params[:path]
    return head :not_found if key.blank?

    # Normalize: if key looks like a local path, convert for ScreenshotUploader
    download_key = if key.start_with?("screenshots/")
      "/#{key}"  # ScreenshotUploader expects local paths with leading /
    else
      key        # R2 keys are stored without prefix
    end

    data = ScreenshotUploader.new.download(download_key)
    send_data data,
      type: "image/png",
      disposition: "inline",
      cache_control: "private, max-age=86400"  # Cache for 24h (scans don't change)
  rescue ScreenshotUploader::UploadError => e
    Rails.logger.warn("[ScreenshotsController] Screenshot not found: #{e.message}")
    head :not_found
  end
end
