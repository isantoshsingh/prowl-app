# frozen_string_literal: true

# AlertMailer sends email notifications to merchants about detected issues.
#
# Emails are designed to be:
#   - Calm and non-alarming (per UX principles)
#   - Clear and actionable
#   - Infrequent (only for confirmed high severity issues)
#   - Include screenshot evidence when available
#   - Include AI-generated plain-language explanations
#
class AlertMailer < ApplicationMailer
  # Sent when a high severity issue is detected twice
  def issue_detected(shop, issue)
    @shop = shop
    @issue = issue
    @product_page = issue.product_page
    @scan = issue.scan
    @app_url = "#{ENV.fetch('HOST', 'https://localhost:3000')}/issues/#{issue.id}"

    # Attach screenshot inline if available
    @has_screenshot = false
    if @scan&.screenshot_url.present?
      begin
        screenshot_data = ScreenshotUploader.new.download(@scan.screenshot_url)
        attachments.inline["screenshot.png"] = screenshot_data
        @has_screenshot = true
      rescue StandardError => e
        Rails.logger.warn("[AlertMailer] Failed to attach screenshot: #{e.message}")
      end
    end

    mail(
      to: shop.shop_setting&.effective_alert_email || shop.email,
      subject: "Prowl: Issue detected on #{@product_page.title}"
    )
  end

  # Sent when all issues for a page are resolved
  def issues_resolved(shop, product_page)
    @shop = shop
    @product_page = product_page
    @app_url = "#{ENV.fetch('HOST', 'https://localhost:3000')}/product_pages/#{product_page.id}"

    mail(
      to: shop.shop_setting&.effective_alert_email || shop.email,
      subject: "Prowl: #{@product_page.title} is now healthy"
    )
  end
end
