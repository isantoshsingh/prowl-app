# frozen_string_literal: true

ShopifyApp.configure do |config|
  config.application_name = "PDP Diagnostics"

  # Minimal scopes needed for Prowl
  # read_products: To fetch product list for monitoring selection
  config.scope = "read_products, read_themes"
  
  config.embedded_app = true
  config.new_embedded_auth_strategy = true

  config.after_authenticate_job = { job: "AfterAuthenticateJob", inline: true }
  config.api_version = "2025-10"
  config.shop_session_repository = "Shop"
  config.log_level = :info
  config.reauth_on_access_scope_changes = true
  
  # Webhooks are configured in shopify.app.toml and handled by controllers
  # config.webhooks = [
  #   { topic: "app/uninstalled", path: "webhooks/app_uninstalled" },
  #   { topic: "app_subscriptions/update", path: "webhooks/app_subscription_update" }
  # ]


  config.api_key = ENV.fetch("SHOPIFY_API_KEY", "").presence
  config.secret = ENV.fetch("SHOPIFY_API_SECRET", "").presence

  # Billing configuration for Prowl
  # $10/month with 14-day free trial
  config.billing = ShopifyApp::BillingConfiguration.new(
    charge_name: "Prowl Monthly",
    amount: 10,
    interval: ShopifyApp::BillingConfiguration::INTERVAL_EVERY_30_DAYS,
    currency_code: "USD",
    trial_days: 14,
    test: !ENV["SHOPIFY_TEST_CHARGES"].nil? ? ["true", "1"].include?(ENV["SHOPIFY_TEST_CHARGES"]) : !Rails.env.production?
  )

  if defined? Rails::Server
    raise("Missing SHOPIFY_API_KEY. See https://github.com/Shopify/shopify_app#requirements") unless config.api_key
    raise("Missing SHOPIFY_API_SECRET. See https://github.com/Shopify/shopify_app#requirements") unless config.secret
  end
end

Rails.application.config.after_initialize do
  # Skip Shopify API setup in test environment or if credentials missing
  next if Rails.env.test?
  next unless ShopifyApp.configuration.api_key.present? && ShopifyApp.configuration.secret.present?
  next unless ENV["HOST"].present?

  ShopifyAPI::Context.setup(
    api_key: ShopifyApp.configuration.api_key,
    api_secret_key: ShopifyApp.configuration.secret,
    api_version: ShopifyApp.configuration.api_version,
    host: ENV["HOST"],
    scope: ShopifyApp.configuration.scope,
    is_private: !ENV.fetch("SHOPIFY_APP_PRIVATE_SHOP", "").empty?,
    is_embedded: ShopifyApp.configuration.embedded_app,
    log_level: :info,
    logger: Rails.logger,
    private_shop: ENV.fetch("SHOPIFY_APP_PRIVATE_SHOP", nil),
    user_agent_prefix: "ShopifyApp/#{ShopifyApp::VERSION}"
  )

  ShopifyApp::WebhooksManager.add_registrations
end

