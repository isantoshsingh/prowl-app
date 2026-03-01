# frozen_string_literal: true

# ScreenshotsController serves scan screenshots.
# Downloads from R2 (production) or local tmp/ (development) and streams to browser.
# Screenshots are private — served through this controller, never publicly accessible.
# Authorization: only serves screenshots belonging to the current shop's scans.
#
class ScreenshotsController < AuthenticatedController
  def show
    # Scope scan lookup to current shop to prevent unauthorized access (IDOR)
    scan = Scan.joins(product_page: :shop)
      .where(shops: { id: @shop&.id })
      .find_by(id: params[:scan_id])

    unless scan&.screenshot_url.present?
      head :not_found
      return
    end

    begin
      screenshot_data = ScreenshotUploader.new.download(scan.screenshot_url)
      send_data screenshot_data,
        type: "image/png",
        disposition: "inline",
        filename: "scan_#{scan.id}.png"
    rescue ScreenshotUploader::UploadError => e
      Rails.logger.warn("[ScreenshotsController] Screenshot not found: #{e.message}")
      head :not_found
    rescue StandardError => e
      Rails.logger.error("[ScreenshotsController] Error serving screenshot: #{e.message}")
      head :internal_server_error
    end
  end
end
