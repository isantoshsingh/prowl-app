# frozen_string_literal: true

# AfterAuthenticateJob runs after a shop successfully authenticates.
# The shopify_app gem will automatically handle billing before this job runs (if not exempt).
# This job initializes the ShopSetting and Subscription for the newly installed shop.
#
class AfterAuthenticateJob < ApplicationJob
  queue_as :default

  def perform(shop_domain:)
    shop = Shop.find_by(shopify_domain: shop_domain)

    unless shop
      Rails.logger.error("[AfterAuthenticateJob] Shop not found: #{shop_domain}")
      return
    end

    # Create shop settings if they don't exist
    shop.shop_setting || shop.create_shop_setting!

    # Update shop metadata and handle reinstall
    update_shop_metadata(shop)
    reinstall_if_needed(shop)

    Rails.logger.info("[AfterAuthenticateJob] Shop setup complete for #{shop_domain}")
  end

  private

  # Update shop metadata from Shopify API
  def update_shop_metadata(shop)
    session = ShopifyAPI::Auth::Session.new(
      shop: shop.shopify_domain,
      access_token: shop.shopify_token
    )

    client = ShopifyAPI::Clients::Graphql::Admin.new(session: session)

    query = <<~GRAPHQL
      {
        shop {
          id
          name
          email
          contactEmail
          currencyCode
          timezoneAbbreviation
          ianaTimezone
          primaryDomain {
            host
          }
          plan {
            displayName
            partnerDevelopment
          }
          billingAddress {
            countryCodeV2
            country
          }
        }
      }
    GRAPHQL

    response = client.query(query: query)
    shop_data = response.body.dig("data", "shop")

    return unless shop_data

    # Extract shop ID from GraphQL global ID
    shopify_id = shop_data["id"]&.split("/")&.last&.to_i

    shop.update!(
      shopify_shop_id: shopify_id,
      shop_owner: shop_data["name"],
      email: shop_data["email"] || shop_data["contactEmail"],
      country_code: shop_data.dig("billingAddress", "countryCodeV2"),
      country_name: shop_data.dig("billingAddress", "country"),
      currency: shop_data["currencyCode"],
      timezone: shop_data["timezoneAbbreviation"],
      iana_timezone: shop_data["ianaTimezone"],
      plan_display_name: shop_data.dig("plan", "displayName"),
      installed_at: shop.installed_at || Time.current,
      shop_json: shop_data.to_h.merge(fetched_at: Time.current.iso8601)
    )

    Rails.logger.info("[AfterAuthenticateJob] Updated shop metadata for #{shop.shopify_domain}")
  rescue StandardError => e
    Rails.logger.error("[AfterAuthenticateJob] Error fetching shop metadata: #{e.message}")
    # Don't fail job if metadata fetch fails
  end

  # Mark shop as installed if it was previously uninstalled
  def reinstall_if_needed(shop)
    return if shop.installed?

    shop.reinstall!
    Rails.logger.info("[AfterAuthenticateJob] Shop #{shop.shopify_domain} reinstalled")
  end
end
