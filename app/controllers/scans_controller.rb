# frozen_string_literal: true

# ScansController displays scan history and details.
#
class ScansController < AuthenticatedController
  include ShopifyApp::EmbeddedApp

  before_action :set_shop
  before_action :set_scan, only: [:show]

  def index
    @scans = Scan.joins(:product_page)
                 .where(product_pages: { shop_id: @shop.id })
                 .includes(:product_page)
                 .order(created_at: :desc)
                 .limit(50)
    
    @host = params[:host]
  end

  def show
    @product_page = @scan.product_page
    @issues = @scan.issues.order(severity: :asc)
    @host = params[:host]
  end

  private

  def set_shop
    @shop = Shop.find_by(shopify_domain: current_shopify_domain)
    unless @shop
      redirect_to ShopifyApp.configuration.login_url
    end
  end

  def set_scan
    @scan = Scan.joins(:product_page)
                .where(product_pages: { shop_id: @shop.id })
                .find(params[:id])
  rescue ActiveRecord::RecordNotFound
    flash[:error] = "Scan not found."
    redirect_to scans_path(host: params[:host])
  end
end
