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
  has_many :subscriptions, dependent: :destroy
  has_one :active_subscription, -> { where(status: 'active') }, class_name: 'Subscription'
  has_one :latest_subscription, -> { order(created_at: :desc) }, class_name: 'Subscription'

  # Callbacks
  after_create :create_default_settings

  # Scopes
  scope :installed, -> { where(installed: true) }
  scope :uninstalled, -> { where(installed: false) }
  scope :by_country, ->(country_code) { where(country_code: country_code) }
  scope :by_plan, ->(plan_name) { where(plan_name: plan_name) }

  def api_version
    ShopifyApp.configuration.api_version
  end

  # Returns the storefront URL for this shop
  def storefront_url
    "https://#{shopify_domain}"
  end

  # Checks if the shop has active billing (subscription or exemption)
  def billing_active?
    billing_exempt? || subscription_active?
  end

  # Helper to check if subscription is valid/active based on local cache
  def subscription_active?
    subscription_status == 'active'
  end

  # Returns current subscription status for display
  # Now uses the cached column on the Shop model
  def subscription_status
    self[:subscription_status] || 'none'
  end

  # Returns the number of product pages currently being monitored
  def monitored_pages_count
    product_pages.monitoring_enabled.count
  end

  # Checks if the shop can add more monitored pages
  def can_add_monitored_page?
    monitored_pages_count < (shop_setting&.max_monitored_pages || 5)
  end

  # Returns a friendly display name for the shop
  def display_name
    shop_owner.presence || shopify_domain
  end

  # Marks shop as reinstalled
  def reinstall!
    update!(
      installed: true,
      installed_at: installed_at || Time.current,
      uninstalled_at: nil
    )
  end

  # Updates shop metadata from webhook params
  def update_from_webhook!(params)
    update!(
      shopify_shop_id: params[:id],
      shop_owner: params[:shop_owner],
      email: params[:email] || params[:customer_email],
      country_code: params[:country_code],
      country_name: params[:country_name],
      currency: params[:currency],
      timezone: params[:timezone],
      iana_timezone: params[:iana_timezone],
      plan_name: params[:plan_name],
      plan_display_name: params[:plan_display_name],
      primary_locale: params[:primary_locale],
      shop_created_at: params[:created_at],
      password_enabled: params[:password_enabled],
      pre_launch_enabled: params[:pre_launch_enabled],
      shop_json: params.except(:controller, :action, :format, :webhook).to_h
    )
  end

  private

  def create_default_settings
    create_shop_setting!(
      email_alerts_enabled: true,
      admin_alerts_enabled: true,
      scan_frequency: "daily",
      max_monitored_pages: 5
    )
  end
end
