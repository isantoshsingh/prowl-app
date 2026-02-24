# frozen_string_literal: true

class Admin::DashboardController < Admin::BaseController
  def index
    @total_shops = Shop.count
    @active_shops = Shop.where("installed_at >= ? OR created_at >= ?", 30.days.ago, 30.days.ago)
                       .where(installed: true).count
    @total_scans = Scan.count
    @scans_last_7_days = Scan.where("created_at >= ?", 7.days.ago).count
    @total_issues = Issue.count
    @issues_by_severity = {
      high: Issue.where(severity: "high").count,
      medium: Issue.where(severity: "medium").count,
      low: Issue.where(severity: "low").count
    }
    @recent_installs = Shop.where(installed: true)
                           .order(installed_at: :desc, created_at: :desc)
                           .limit(10)
  end
end
