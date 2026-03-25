# frozen_string_literal: true

class Admin::ShopsController < Admin::BaseController
  def index
    shops = Shop.order(created_at: :desc)
    shops = shops.where("shopify_domain ILIKE ?", "%#{params[:search]}%") if params[:search].present?
    @pagy, @shops = pagy(shops, limit: 25)
  end

  def show
    @shop = Shop.find(params[:id])
    @product_pages = @shop.product_pages.order(created_at: :desc)
    @recent_scans = Scan.joins(:product_page)
                        .where(product_pages: { shop_id: @shop.id })
                        .order(created_at: :desc)
                        .limit(20)
    @open_issues = Issue.joins(:product_page)
                       .where(product_pages: { shop_id: @shop.id })
                       .where.not(status: "resolved")
                       .order(last_detected_at: :desc)
  end
end
