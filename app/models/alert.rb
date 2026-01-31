# frozen_string_literal: true

# Alert represents a notification sent to a merchant about an issue.
# Alerts are only sent for high severity issues that persist across 2+ scans.
#
# Alert types:
#   - email: Email sent to shop owner
#   - admin: Shopify admin notification
#
# Delivery status:
#   - pending: Not yet sent
#   - sent: Successfully delivered
#   - failed: Delivery failed
#
class Alert < ApplicationRecord
  # Associations
  belongs_to :shop
  belongs_to :issue

  # Validations
  validates :alert_type, inclusion: { in: %w[email admin] }
  validates :delivery_status, inclusion: { in: %w[pending sent failed] }
  validates :issue_id, uniqueness: { scope: [:shop_id, :alert_type], message: "already alerted for this issue" }

  # Scopes
  scope :email_alerts, -> { where(alert_type: "email") }
  scope :admin_alerts, -> { where(alert_type: "admin") }
  scope :pending, -> { where(delivery_status: "pending") }
  scope :sent, -> { where(delivery_status: "sent") }
  scope :failed, -> { where(delivery_status: "failed") }
  scope :recent, -> { order(created_at: :desc) }
  scope :today, -> { where("created_at >= ?", Time.current.beginning_of_day) }

  # Marks alert as sent
  def mark_sent!
    update!(delivery_status: "sent", sent_at: Time.current)
  end

  # Marks alert as failed
  def mark_failed!
    update!(delivery_status: "failed")
  end

  # Checks if alert is pending
  def pending?
    delivery_status == "pending"
  end

  # Checks if alert was sent
  def sent?
    delivery_status == "sent"
  end
end
