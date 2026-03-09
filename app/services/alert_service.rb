# frozen_string_literal: true

# AlertService handles sending notifications to merchants about detected issues.
#
# Alert types:
#   - Email alerts: Sent to shop owner email
#   - Admin notifications: Shopify admin notification
#
# Rules:
#   - Only alert for HIGH severity issues
#   - Only alert after issue persists across 2 scans OR is AI-confirmed
#   - Dedup within a single scan (one email per product page per scan)
#   - Allow re-alerting on subsequent scans for unacknowledged issues
#
class AlertService
  attr_reader :shop, :issues, :scan

  # Initialize with one or more issues from the same product page / same scan run.
  # scan: the Scan record that triggered these issues (used for per-scan dedup)
  def initialize(issues, scan:)
    @issues = Array(issues)
    @shop = @issues.first.shop
    @scan = scan
  end

  # Send batched email (and admin) alerts covering all new alertable issues.
  # Issues that already have an alert for THIS scan are skipped — avoids double-sending.
  def perform
    return unless shop.billing_active?

    alertable = issues.select { |i| i.should_alert? }
    return if alertable.empty?

    if shop.shop_setting&.email_alerts_enabled?
      send_batched_email_alert(alertable)
    end

    if shop.shop_setting&.admin_alerts_enabled?
      alertable.each { |issue| send_admin_notification(issue) }
    end
  end

  private

  # Send ONE email covering all alertable issues together.
  # Creates individual Alert records for each issue first (for per-scan dedup),
  # then sends a single batched email.
  def send_batched_email_alert(alertable_issues)
    # Create alert records for each issue (dedup guard — scoped to this scan)
    created_alerts = alertable_issues.filter_map do |issue|
      next if existing_alert?(issue, "email")
      create_alert(issue, "email")
    end

    return if created_alerts.empty? # All already alerted in this scan

    # Collect the issues that actually got new alerts
    alerted_issues = created_alerts.map { |a| a.issue }

    begin
      AlertMailer.issues_detected(shop, alerted_issues).deliver_later
      created_alerts.each(&:mark_sent!)
      Rails.logger.info(
        "[AlertService] Batched email alert sent for #{created_alerts.length} issue(s) on " \
        "product page #{alerted_issues.first.product_page_id} to shop #{shop.id} (scan #{scan.id})"
      )
    rescue StandardError => e
      created_alerts.each(&:mark_failed!)
      Rails.logger.error("[AlertService] Failed to send batched email alert: #{e.message}")
    end
  end

  def send_admin_notification(issue)
    return if existing_alert?(issue, "admin")

    alert = create_alert(issue, "admin")
    return unless alert

    begin
      Rails.logger.info("[AlertService] Admin notification for issue #{issue.id} would be sent to shop #{shop.id}")
      alert.mark_sent!
    rescue StandardError => e
      alert.mark_failed!
      Rails.logger.error("[AlertService] Failed to send admin notification: #{e.message}")
    end
  end

  # Check if an alert already exists for this issue in THIS scan
  def existing_alert?(issue, alert_type)
    Alert.exists?(shop: shop, issue: issue, alert_type: alert_type, scan: scan)
  end

  # Create an alert tied to this specific scan
  def create_alert(issue, alert_type)
    Alert.create!(
      shop: shop,
      issue: issue,
      scan: scan,
      alert_type: alert_type,
      delivery_status: "pending"
    )
  rescue ActiveRecord::RecordNotUnique
    Rails.logger.info("[AlertService] Alert already exists for issue #{issue.id} in scan #{scan.id} (#{alert_type}), skipping")
    nil
  end
end
