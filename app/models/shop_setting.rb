# frozen_string_literal: true

# ShopSetting stores configuration for each shop.
# Created automatically when a shop installs the app (via AfterAuthenticateJob).
#
# This model handles:
#   - Alert preferences (email, admin notifications)
#   - Scan frequency settings
#   - Maximum monitored pages limit
#
# Billing is now tracked in the Subscription model.
#
class ShopSetting < ApplicationRecord
  # Associations
  belongs_to :shop

  # Validations
  validates :scan_frequency, inclusion: { in: %w[daily weekly] }
  validates :max_monitored_pages, numericality: { greater_than: 0, less_than_or_equal_to: Shop::MAX_MONITORED_PAGES }
  validates :shop_id, uniqueness: true

  # Default values set in migration, but ensure they're set
  after_initialize :set_defaults, if: :new_record?

  # Returns the alert email, falling back to shop's actual email address.
  # shop.email is populated from Shopify webhook data (shop owner's email).
  def effective_alert_email
    alert_email.presence || shop.email.presence
  end

  private

  def set_defaults
    self.email_alerts_enabled = true if email_alerts_enabled.nil?
    self.admin_alerts_enabled = true if admin_alerts_enabled.nil?
    self.scan_frequency ||= "daily"
    self.max_monitored_pages ||= Shop::MAX_MONITORED_PAGES
  end
end
