# frozen_string_literal: true

# AlertService handles sending notifications to merchants about detected issues.
# 
# Alert types:
#   - Email alerts: Sent to shop owner email
#   - Admin notifications: Shopify admin notification
#
# Rules (per agent.md):
#   - Only alert for HIGH severity issues
#   - Only alert after issue persists across 2 scans (avoid noise)
#   - Never send duplicate alerts for same issue
#
class AlertService
  attr_reader :shop, :issue

  def initialize(issue)
    @issue = issue
    @shop = issue.shop
  end

  # Checks if issue should be alerted and sends appropriate alerts
  def perform
    return unless issue.should_alert?
    return unless shop.billing_active?

    alerts_sent = []

    # Send email alert if enabled
    if shop.shop_setting&.email_alerts_enabled?
      alert = send_email_alert
      alerts_sent << alert if alert
    end

    # Send admin notification if enabled
    if shop.shop_setting&.admin_alerts_enabled?
      alert = send_admin_notification
      alerts_sent << alert if alert
    end

    alerts_sent
  end

  private

  def send_email_alert
    # Check if email alert already exists for this issue
    return if existing_alert?("email")

    alert = create_alert("email")

    begin
      AlertMailer.issue_detected(shop, issue).deliver_later
      alert.mark_sent!
      Rails.logger.info("[AlertService] Email alert sent for issue #{issue.id} to shop #{shop.id}")
    rescue StandardError => e
      alert.mark_failed!
      Rails.logger.error("[AlertService] Failed to send email alert: #{e.message}")
    end

    alert
  end

  def send_admin_notification
    # Check if admin alert already exists for this issue
    return if existing_alert?("admin")

    alert = create_alert("admin")

    begin
      # Use Shopify Admin API to send notification
      # In Phase 1, we'll log it - full implementation requires App Bridge
      Rails.logger.info("[AlertService] Admin notification for issue #{issue.id} would be sent to shop #{shop.id}")
      
      # Mark as sent - in production, this would happen after API confirmation
      alert.mark_sent!
    rescue StandardError => e
      alert.mark_failed!
      Rails.logger.error("[AlertService] Failed to send admin notification: #{e.message}")
    end

    alert
  end

  def existing_alert?(alert_type)
    Alert.exists?(shop: shop, issue: issue, alert_type: alert_type)
  end

  def create_alert(alert_type)
    Alert.create!(
      shop: shop,
      issue: issue,
      alert_type: alert_type,
      delivery_status: "pending"
    )
  end
end
