# frozen_string_literal: true

# SettingsController allows merchants to configure:
#   - Alert preferences (email, admin notifications)
#   - Scan frequency
#   - Alert email address
#
class SettingsController < AuthenticatedController
  include ShopifyApp::EmbeddedApp

  before_action :set_shop

  def show
    @settings = @shop.shop_setting || @shop.create_shop_setting!
    @host = params[:host]

    respond_to do |format|
      format.html { render layout: "react_app" }
      format.json { render json: settings_json(@settings) }
    end
  end

  def update
    @settings = @shop.shop_setting

    if @settings.update(settings_params)
      respond_to do |format|
        format.html do
          flash[:success] = "Settings saved successfully."
          redirect_to settings_path(host: params[:host])
        end
        format.json { render json: { success: true, settings: settings_json(@settings) } }
      end
    else
      respond_to do |format|
        format.html do
          flash[:error] = @settings.errors.full_messages.join(", ")
          redirect_to settings_path(host: params[:host])
        end
        format.json do
          render json: { success: false, errors: @settings.errors.full_messages }, status: :unprocessable_entity
        end
      end
    end
  end

  private

  def set_shop
    @shop = Shop.find_by(shopify_domain: current_shopify_domain)
    unless @shop
      redirect_to ShopifyApp.configuration.login_url
    end
  end

  def settings_params
    params.require(:shop_setting).permit(
      :email_alerts_enabled,
      :admin_alerts_enabled,
      :alert_email,
      :scan_frequency
    )
  end

  def settings_json(settings)
    {
      email_alerts_enabled: settings.email_alerts_enabled,
      admin_alerts_enabled: settings.admin_alerts_enabled,
      alert_email: settings.alert_email,
      scan_frequency: settings.scan_frequency,
      max_monitored_pages: settings.max_monitored_pages,
      billing_status: settings.billing_status,
      trial_ends_at: settings.trial_ends_at&.iso8601,
      trial_days_remaining: settings.trial_days_remaining,
      subscription_charge_id: settings.subscription_charge_id
    }
  end
end
