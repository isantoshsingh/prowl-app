# frozen_string_literal: true

# ProductPage represents a Shopify product page (PDP) being monitored.
# Each shop can have up to 5 monitored pages in Phase 1.
#
# Status values:
#   - pending: Never scanned yet
#   - healthy: Last scan found no issues
#   - warning: Last scan found medium/low severity issues
#   - critical: Last scan found high severity issues
#   - error: Last scan failed to complete
#
class ProductPage < ApplicationRecord
  # Associations
  belongs_to :shop
  has_many :scans, dependent: :destroy
  has_many :issues, dependent: :destroy

  # Validations
  validates :shopify_product_id, presence: true, uniqueness: { scope: :shop_id }
  validates :handle, presence: true
  validates :title, presence: true
  validates :url, presence: true
  validates :status, inclusion: { in: %w[pending healthy warning critical error] }

  # Scopes
  scope :monitoring_enabled, -> { where(monitoring_enabled: true) }
  scope :monitoring_disabled, -> { where(monitoring_enabled: false) }
  scope :needs_scan, -> { monitoring_enabled.where("last_scanned_at IS NULL OR last_scanned_at < ?", 24.hours.ago) }
  scope :by_status, ->(status) { where(status: status) }
  scope :healthy, -> { by_status("healthy") }
  scope :warning, -> { by_status("warning") }
  scope :critical, -> { by_status("critical") }

  # Returns the most recent scan
  def latest_scan
    scans.order(created_at: :desc).first
  end

  # Returns all open issues for this page
  def open_issues
    issues.where(status: "open")
  end

  # Returns count of high severity open issues
  def high_severity_issues_count
    open_issues.where(severity: "high").count
  end

  # Checks if this page needs to be scanned
  def needs_scan?
    return true if last_scanned_at.nil?
    last_scanned_at < 24.hours.ago
  end

  # Updates status based on open issues
  def update_status_from_issues!
    if open_issues.where(severity: "high").any?
      update!(status: "critical")
    elsif open_issues.where(severity: "medium").any?
      update!(status: "warning")
    elsif open_issues.empty?
      update!(status: "healthy")
    else
      update!(status: "warning")
    end
  end

  # Returns the full URL for scanning
  def scannable_url
    url.start_with?("http") ? url : "https://#{shop.shopify_domain}#{url}"
  end
end
