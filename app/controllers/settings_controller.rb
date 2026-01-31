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
  end

  def update
    @settings = @shop.shop_setting

    if @settings.update(settings_params)
      flash[:success] = "Settings saved successfully."
    else
      flash[:error] = @settings.errors.full_messages.join(", ")
    end

    redirect_to settings_path(host: params[:host])
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
end
