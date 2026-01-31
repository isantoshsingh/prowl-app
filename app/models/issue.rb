# frozen_string_literal: true

# Issue represents a detected problem on a product page.
# Issues are created by the detection engine after a scan.
#
# Issue types:
#   - missing_add_to_cart: ATC button not found or not clickable
#   - variant_selector_error: Variant picker not working
#   - js_error: JavaScript error on page load
#   - liquid_error: Liquid template error
#   - missing_images: Product images not loading
#   - missing_price: Price not visible
#   - slow_page_load: Page load time exceeds threshold
#
# Severity levels:
#   - high: Revenue-impacting, immediate attention needed
#   - medium: Potentially problematic, should investigate
#   - low: Minor issue, informational
#
# Status values:
#   - open: Issue is active and unresolved
#   - acknowledged: Merchant aware of issue
#   - resolved: Issue no longer detected
#
class Issue < ApplicationRecord
  # Associations
  belongs_to :product_page
  belongs_to :scan
  has_many :alerts, dependent: :destroy
  has_one :shop, through: :product_page

  # Validations
  validates :issue_type, presence: true
  validates :severity, inclusion: { in: %w[high medium low] }
  validates :title, presence: true
  validates :status, inclusion: { in: %w[open acknowledged resolved] }
  validates :occurrence_count, numericality: { greater_than: 0 }
  validates :first_detected_at, presence: true
  validates :last_detected_at, presence: true

  # JSON serialization for evidence
  serialize :evidence, coder: JSON

  # Scopes
  scope :open, -> { where(status: "open") }
  scope :acknowledged, -> { where(status: "acknowledged") }
  scope :resolved, -> { where(status: "resolved") }
  scope :high_severity, -> { where(severity: "high") }
  scope :medium_severity, -> { where(severity: "medium") }
  scope :low_severity, -> { where(severity: "low") }
  scope :recent, -> { order(last_detected_at: :desc) }
  scope :by_type, ->(type) { where(issue_type: type) }
  scope :alertable, -> { open.high_severity.where("occurrence_count >= ?", 2) }

  # Issue type configuration
  ISSUE_TYPES = {
    "missing_add_to_cart" => {
      severity: "high",
      title: "Add to Cart button may not be working",
      description: "We couldn't find a working Add to Cart button on this page. Customers may not be able to purchase this product."
    },
    "variant_selector_error" => {
      severity: "high",
      title: "Variant selector may have issues",
      description: "The product variant selector might not be working correctly. Customers may have trouble selecting options."
    },
    "js_error" => {
      severity: "high",
      title: "JavaScript errors detected",
      description: "We detected JavaScript errors on this page. This may affect functionality and customer experience."
    },
    "liquid_error" => {
      severity: "medium",
      title: "Liquid template errors detected",
      description: "There may be template errors on this page. Some content might not display correctly."
    },
    "missing_images" => {
      severity: "medium",
      title: "Product images may not be loading",
      description: "We couldn't verify that product images are loading correctly. Customers may not see product photos."
    },
    "missing_price" => {
      severity: "high",
      title: "Price may not be visible",
      description: "We couldn't find a visible price on this page. Customers may be confused about the cost."
    },
    "slow_page_load" => {
      severity: "low",
      title: "Page is loading slowly",
      description: "This page took longer than expected to load. This may affect customer experience."
    }
  }.freeze

  # Acknowledges the issue
  def acknowledge!(by: nil)
    update!(
      status: "acknowledged",
      acknowledged_at: Time.current,
      acknowledged_by: by
    )
  end

  # Resolves the issue
  def resolve!
    update!(status: "resolved")
  end

  # Reopens a resolved issue
  def reopen!
    update!(status: "open")
  end

  # Increments occurrence count and updates last detected time
  def record_occurrence!(scan)
    update!(
      occurrence_count: occurrence_count + 1,
      last_detected_at: Time.current,
      scan: scan
    )
  end

  # Checks if this issue should trigger an alert
  # Only alerts after 2 occurrences to avoid false positives
  def should_alert?
    open? && high_severity? && occurrence_count >= 2 && alerts.none?
  end

  def open?
    status == "open"
  end

  def high_severity?
    severity == "high"
  end

  # Returns a human-readable severity label
  def severity_label
    case severity
    when "high" then "High Priority"
    when "medium" then "Medium Priority"
    when "low" then "Low Priority"
    else severity.humanize
    end
  end
end
