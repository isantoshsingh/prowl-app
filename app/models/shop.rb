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

  # Onboarding: checks if the setup guide should be shown
  def show_onboarding?
    onboarding_dismissed_at.nil? && !onboarding_completed?
  end

  # Onboarding: all steps completed
  def onboarding_completed?
    onboarding_steps.all? { |step| step[:completed] }
  end

  # Onboarding: computes step states dynamically from actual data
  def onboarding_steps
    has_pages = product_pages.monitoring_enabled.exists?
    has_scans = has_pages && Scan.joins(:product_page)
                                 .where(product_pages: { shop_id: id })
                                 .where(status: "completed")
                                 .exists?
    has_alerts_configured = shop_setting&.alert_email.present?

    [
      {
        key: :add_products,
        title: "Add product pages to monitor",
        description: "Select your most important product pages to start monitoring for issues that silently hurt sales.",
        completed: has_pages
      },
      {
        key: :first_scan,
        title: "Run your first scan",
        description: "Scan your product pages to detect JavaScript errors, broken UI elements, and performance issues.",
        completed: has_scans
      },
      {
        key: :configure_alerts,
        title: "Configure alert settings",
        description: "Set up your email address to receive notifications when critical issues are detected on your pages.",
        completed: has_alerts_configured
      }
    ]
  end

  # Onboarding: returns progress as completed/total
  def onboarding_progress
    steps = onboarding_steps
    completed = steps.count { |s| s[:completed] }
    { completed: completed, total: steps.size }
  end

  # Dismiss the onboarding setup guide
  def dismiss_onboarding!
    update!(onboarding_dismissed_at: Time.current)
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
