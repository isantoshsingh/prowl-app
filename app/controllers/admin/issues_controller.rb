# frozen_string_literal: true

class Admin::IssuesController < Admin::BaseController
  def index
    issues = Issue.joins(product_page: :shop).order(last_detected_at: :desc)

    issues = issues.where(severity: params[:severity]) if params[:severity].present?
    issues = issues.where(issue_type: params[:issue_type]) if params[:issue_type].present?

    if params[:status_filter].present?
      case params[:status_filter]
      when "resolved"
        issues = issues.where(status: "resolved")
      when "unresolved"
        issues = issues.where.not(status: "resolved")
      end
    end

    @pagy, @issues = pagy(issues, limit: 25)
  end

  def show
    @issue = Issue.find(params[:id])
    @product_page = @issue.product_page
    @shop = @product_page.shop
    @scan = @issue.scan
  end
end
