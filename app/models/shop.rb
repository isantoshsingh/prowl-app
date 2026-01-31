# frozen_string_literal: true

# Shop model represents a Shopify store that has installed Silent Profit.
# This is the central model that connects to all other domain models.
#
# Associations:
#   - has_many :product_pages - The PDP pages being monitored
#   - has_one :shop_setting - Configuration for this shop
#   - has_many :alerts - Notifications sent to this shop
#
class Shop < ActiveRecord::Base
  include ShopifyApp::ShopSessionStorage

  # Associations
  has_many :product_pages, dependent: :destroy
  has_one :shop_setting, dependent: :destroy
  has_many :alerts, dependent: :destroy

  # Callbacks
  after_create :create_default_settings

  def api_version
    ShopifyApp.configuration.api_version
  end

  # Returns the storefront URL for this shop
  def storefront_url
    "https://#{shopify_domain}"
  end

  # Checks if the shop has an active subscription or is in trial
  def billing_active?
    return true if shop_setting&.trial_active?
    shop_setting&.subscription_active?
  end

  # Returns the number of product pages currently being monitored
  def monitored_pages_count
    product_pages.monitoring_enabled.count
  end

  # Checks if the shop can add more monitored pages
  def can_add_monitored_page?
    monitored_pages_count < (shop_setting&.max_monitored_pages || 5)
  end

  private

  def create_default_settings
    create_shop_setting!(
      email_alerts_enabled: true,
      admin_alerts_enabled: true,
      scan_frequency: "daily",
      max_monitored_pages: 5,
      billing_status: "trial",
      trial_ends_at: 14.days.from_now
    )
  end
end
