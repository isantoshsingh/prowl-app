# frozen_string_literal: true

# ShopSetting stores configuration for each shop.
# Created automatically when a shop installs the app.
#
# Billing statuses:
#   - trial: In 14-day free trial
#   - active: Paid subscription active
#   - cancelled: Subscription cancelled
#   - expired: Trial expired without payment
#
class ShopSetting < ApplicationRecord
  # Associations
  belongs_to :shop

  # Validations
  validates :scan_frequency, inclusion: { in: %w[daily weekly] }
  validates :billing_status, inclusion: { in: %w[trial active cancelled expired] }
  validates :max_monitored_pages, numericality: { greater_than: 0, less_than_or_equal_to: 5 }
  validates :shop_id, uniqueness: true

  # Default values set in migration, but ensure they're set
  after_initialize :set_defaults, if: :new_record?

  # Checks if trial is still active
  def trial_active?
    billing_status == "trial" && trial_ends_at.present? && trial_ends_at > Time.current
  end

  # Checks if paid subscription is active
  def subscription_active?
    billing_status == "active" && subscription_charge_id.present?
  end

  # Checks if billing is active (trial or paid)
  def billing_active?
    trial_active? || subscription_active?
  end

  # Returns days remaining in trial
  def trial_days_remaining
    return 0 unless trial_active?
    ((trial_ends_at - Time.current) / 1.day).ceil
  end

  # Activates the subscription after payment
  def activate_subscription!(charge_id)
    update!(
      billing_status: "active",
      subscription_charge_id: charge_id
    )
  end

  # Cancels the subscription
  def cancel_subscription!
    update!(billing_status: "cancelled")
  end

  # Marks trial as expired
  def expire_trial!
    update!(billing_status: "expired")
  end

  # Returns the alert email, falling back to shop email
  def effective_alert_email
    alert_email.presence || shop.shopify_domain
  end

  private

  def set_defaults
    self.email_alerts_enabled = true if email_alerts_enabled.nil?
    self.admin_alerts_enabled = true if admin_alerts_enabled.nil?
    self.scan_frequency ||= "daily"
    self.max_monitored_pages ||= 5
    self.billing_status ||= "trial"
    self.trial_ends_at ||= 14.days.from_now
  end
end
