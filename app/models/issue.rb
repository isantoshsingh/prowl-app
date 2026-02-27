# frozen_string_literal: true

# Issue represents a detected problem on a product page.
# Issues are created by the detection engine after a scan.
#
# Issue types:
#   - missing_add_to_cart: ATC button not found, hidden, or permanently disabled
#   - atc_not_functional: ATC button clicks but cart doesn't update
#   - checkout_broken: Checkout page fails to load after adding to cart
#   - variant_selection_broken: Cannot select product variants
#   - variant_selector_error: Variant picker JS errors
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
  scope :alertable, -> { open.high_severity.where("occurrence_count >= ? OR ai_confirmed = ?", 2, true) }

# Issue type configuration
  ISSUE_TYPES = {
    "missing_add_to_cart" => {
      severity: "high",
      title: "Add to Cart button is not working",
      description: "The Add to Cart button is missing, hidden, or permanently disabled. Customers cannot purchase this product."
    },
    "atc_not_functional" => {
      severity: "high",
      title: "Add to Cart is not adding items",
      description: "The Add to Cart button exists and can be clicked, but items are not being added to the cart. Customers cannot complete purchases."
    },
    "checkout_broken" => {
      severity: "high",
      title: "Checkout page is not loading",
      description: "After adding a product to cart, the checkout page failed to load correctly. Customers cannot complete their purchase."
    },
    "variant_selection_broken" => {
      severity: "high",
      title: "Product variant selection is not working",
      description: "Customers cannot select product options (size, color, etc.). This may prevent them from adding the product to cart."
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

  SEVERITY_WEIGHTS = { "high" => 3, "medium" => 2, "low" => 1 }.freeze

  # Increments occurrence count and updates last detected time
  def record_occurrence!(scan)
    update!(
      occurrence_count: occurrence_count + 1,
      last_detected_at: Time.current,
      scan: scan
    )
  end

  # Smart merge that evaluates the severity trend to escalate, de-escalate, or persist context.
  def merge_new_detection!(scan:, new_severity:, new_title:, new_description:, new_evidence:)
    old_weight = SEVERITY_WEIGHTS[severity] || 0
    new_weight = SEVERITY_WEIGHTS[new_severity] || 0

    if new_weight > old_weight
      # Escalation: override everything and clear AI cache to force re-evaluation
      update!(
        severity: new_severity,
        title: new_title,
        description: new_description,
        evidence: new_evidence,
        occurrence_count: occurrence_count + 1,
        last_detected_at: Time.current,
        scan: scan,
        ai_confirmed: nil,
        ai_explanation: nil,
        ai_reasoning: nil,
        ai_suggested_fix: nil
      )
      self
    elsif new_weight < old_weight
      # De-escalation: resolve the higher severity issue and return nil to signal caller to create a new one
      resolve!
      nil
    else
      # Persistent Context Refresh (Same severity): always use latest data to avoid ghostly stale UI
      update!(
        title: new_title,
        description: new_description,
        evidence: new_evidence,
        occurrence_count: occurrence_count + 1,
        last_detected_at: Time.current,
        scan: scan
      )
      self
    end
  end

  # Checks if this issue should trigger an alert.
  # Two paths to alerting:
  #   1. AI-confirmed: alert immediately on first occurrence (high confidence)
  #   2. No AI confirmation: wait for 2 occurrences to avoid false positives
  def should_alert?
    return false unless open? && high_severity? && alerts.none?

    # If AI confirmed the issue, trust it on first scan
    return true if ai_confirmed?

    # Otherwise require 2 occurrences (rescan confirmation)
    occurrence_count >= 2
  end

  def ai_confirmed?
    ai_confirmed == true
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

  # Returns the best available explanation for the merchant.
  # Prefers AI-generated explanation, falls back to hardcoded description.
  def merchant_explanation
    ai_explanation.presence || Issue::ISSUE_TYPES.dig(issue_type, :description) || description
  end

  # Returns the AI-suggested fix if available.
  def merchant_suggested_fix
    ai_suggested_fix
  end
end
