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

    # Pagination
    page = (params[:page] || 1).to_i
    per_page = 20
    total_count = @issues.count
    @issues = @issues.offset((page - 1) * per_page).limit(per_page)

    @host = params[:host]

    respond_to do |format|
      format.html { render layout: "react_app" }
      format.json do
        render json: {
          issues: @issues.map { |i| issue_json(i) },
          page: page,
          per_page: per_page,
          total_count: total_count,
          has_more: (page * per_page) < total_count
        }
      end
    end
  end

  def show
    @product_page = @issue.product_page
    @scan = @issue.scan
    @host = params[:host]

    respond_to do |format|
      format.html { render layout: "react_app" }
      format.json { render json: issue_json(@issue, include_details: true) }
    end
  end

  def acknowledge
    @issue.acknowledge!(by: current_shopify_domain)

    respond_to do |format|
      format.html do
        flash[:success] = "Issue acknowledged. We'll continue monitoring."
        redirect_to issue_path(@issue, host: params[:host])
      end
      format.json { render json: { success: true, issue: issue_json(@issue) } }
    end
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
    respond_to do |format|
      format.html do
        flash[:error] = "Issue not found."
        redirect_to issues_path(host: params[:host])
      end
      format.json { render json: { error: "Issue not found" }, status: :not_found }
    end
  end

  def issue_json(issue, include_details: false)
    data = {
      id: issue.id,
      title: issue.title,
      description: issue.description,
      issue_type: issue.issue_type,
      severity: issue.severity,
      status: issue.status,
      occurrence_count: issue.occurrence_count,
      first_detected_at: issue.first_detected_at&.iso8601,
      last_detected_at: issue.last_detected_at&.iso8601,
      acknowledged_at: issue.acknowledged_at&.iso8601,
      acknowledged_by: issue.acknowledged_by,
      product_page: issue.product_page ? {
        id: issue.product_page.id,
        title: issue.product_page.title,
        handle: issue.product_page.handle
      } : nil
    }

    if include_details
      data[:evidence] = issue.evidence
      data[:scan] = issue.scan ? {
        id: issue.scan.id,
        status: issue.scan.status,
        completed_at: issue.scan.completed_at&.iso8601
      } : nil
    end

    data
  end
end
