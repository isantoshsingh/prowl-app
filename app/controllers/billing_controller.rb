# frozen_string_literal: true

# BillingController handles the Shopify Billing API flow.
#
# Flow:
#   1. Merchant installs app
#   2. App redirects to create subscription
#   3. Shopify shows billing approval page
#   4. Merchant approves/declines
#   5. Shopify redirects back to callback
#   6. App activates or handles decline
#
class BillingController < AuthenticatedController
  include ShopifyApp::EmbeddedApp

  before_action :set_shop

  # Initiates the billing flow
  def create
    billing_service = BillingService.new(@shop)

    begin
      confirmation_url = billing_service.create_subscription

      respond_to do |format|
        format.html { redirect_to confirmation_url, allow_other_host: true }
        format.json { render json: { confirmation_url: confirmation_url } }
      end
    rescue BillingService::BillingError => e
      respond_to do |format|
        format.html do
          flash[:error] = "Could not start subscription: #{e.message}"
          redirect_to root_path(host: params[:host])
        end
        format.json { render json: { error: e.message }, status: :unprocessable_entity }
      end
    end
  end

  # Handles callback from Shopify after billing approval/decline
  def callback
    charge_id = params[:charge_id]

    if charge_id.blank?
      # Billing was declined or cancelled
      @shop.shop_setting&.cancel_subscription!
      flash[:notice] = "Subscription was not activated. You can try again anytime."
      redirect_to root_path(host: params[:host])
      return
    end

    billing_service = BillingService.new(@shop)

    if billing_service.handle_callback(charge_id)
      flash[:success] = "Subscription activated! Silent Profit is now monitoring your store."
    else
      flash[:notice] = "Subscription could not be verified. Please contact support."
    end

    redirect_to root_path(host: params[:host])
  end

  private

  def set_shop
    @shop = Shop.find_by(shopify_domain: current_shopify_domain)
    unless @shop
      redirect_to ShopifyApp.configuration.login_url
    end
  end
end
