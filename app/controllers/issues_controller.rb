# frozen_string_literal: true

# IssuesController displays detected issues.
# Merchants can:
#   - View all issues
#   - View issue details
#   - Acknowledge issues
#
class IssuesController < AuthenticatedController
  include ShopifyApp::EmbeddedApp

  before_action :set_shop
  before_action :set_issue, only: [:show, :acknowledge]

  def index
    @issues = Issue.joins(:product_page)
                   .where(product_pages: { shop_id: @shop.id })
                   .includes(:product_page, :scan)
                   .order(status: :asc, severity: :asc, last_detected_at: :desc)

    # Filter by status if provided
    @issues = @issues.where(status: params[:status]) if params[:status].present?
    
    # Filter by severity if provided
    @issues = @issues.where(severity: params[:severity]) if params[:severity].present?

    @issues = @issues.page(params[:page]).per(20) if @issues.respond_to?(:page)
    
    @host = params[:host]
  end

  def show
    @product_page = @issue.product_page
    @scan = @issue.scan
    @host = params[:host]
  end

  def acknowledge
    @issue.acknowledge!(by: current_shopify_domain)
    flash[:success] = "Issue acknowledged. We'll continue monitoring."
    redirect_to issue_path(@issue, host: params[:host])
  end

  private

  def set_shop
    @shop = Shop.find_by(shopify_domain: current_shopify_domain)
    unless @shop
      redirect_to ShopifyApp.configuration.login_url
    end
  end

  def set_issue
    @issue = Issue.joins(:product_page)
                  .where(product_pages: { shop_id: @shop.id })
                  .find(params[:id])
  rescue ActiveRecord::RecordNotFound
    flash[:error] = "Issue not found."
    redirect_to issues_path(host: params[:host])
  end
end
