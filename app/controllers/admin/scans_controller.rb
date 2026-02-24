# frozen_string_literal: true

class Admin::ScansController < Admin::BaseController
  def index
    scans = Scan.joins(product_page: :shop).order(created_at: :desc)

    if params[:shop_domain].present?
      scans = scans.where("shops.shopify_domain ILIKE ?", "%#{params[:shop_domain]}%")
    end
    if params[:date_from].present?
      scans = scans.where("scans.created_at >= ?", Date.parse(params[:date_from]).beginning_of_day)
    end
    if params[:date_to].present?
      scans = scans.where("scans.created_at <= ?", Date.parse(params[:date_to]).end_of_day)
    end

    @pagy, @scans = pagy(scans, limit: 50)
  end

  def show
    @scan = Scan.find(params[:id])
    @issues = @scan.issues.order(severity: :asc, created_at: :desc)
  end
end
