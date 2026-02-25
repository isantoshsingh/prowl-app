# frozen_string_literal: true

# Scan represents a single PDP scan run.
# Each scan captures the state of a product page at a point in time.
#
# Status values:
#   - pending: Scan queued but not started
#   - running: Scan in progress
#   - completed: Scan finished successfully
#   - failed: Scan failed (error_message contains details)
#
class Scan < ApplicationRecord
  # Associations
  belongs_to :product_page
  has_many :issues, dependent: :destroy
  has_one :shop, through: :product_page

  # Validations
  validates :status, inclusion: { in: %w[pending running completed failed] }

  # Scopes
  scope :completed, -> { where(status: "completed") }
  scope :failed, -> { where(status: "failed") }
  scope :pending, -> { where(status: "pending") }
  scope :running, -> { where(status: "running") }
  scope :recent, -> { order(created_at: :desc) }
  scope :today, -> { where("created_at >= ?", Time.current.beginning_of_day) }
  scope :last_7_days, -> { where("created_at >= ?", 7.days.ago) }

  # JSON serialization for error arrays
  serialize :js_errors, coder: JSON
  serialize :network_errors, coder: JSON
  serialize :console_logs, coder: JSON
  serialize :dom_checks_data, coder: JSON

  # Marks the scan as started
  def start!
    update!(status: "running", started_at: Time.current)
  end

  # Marks the scan as completed
  def complete!(attributes = {})
    update!(
      status: "completed",
      completed_at: Time.current,
      **attributes
    )
    product_page.update!(last_scanned_at: Time.current)
  end

  # Marks the scan as failed
  def fail!(message)
    update!(
      status: "failed",
      completed_at: Time.current,
      error_message: message
    )
    product_page.update!(status: "error", last_scanned_at: Time.current)
  end

  # Returns the duration of the scan in seconds
  def duration_seconds
    return nil unless started_at && completed_at
    (completed_at - started_at).round(2)
  end

  # Checks if scan has JS errors
  def has_js_errors?
    js_errors.present? && js_errors.any?
  end

  # Checks if scan has network errors
  def has_network_errors?
    network_errors.present? && network_errors.any?
  end

  # Returns parsed JS errors
  def parsed_js_errors
    return [] if js_errors.blank?
    js_errors.is_a?(Array) ? js_errors : []
  end

  IRRELEVANT_NETWORK_PATTERNS = %w[
    google-analytics.com googletagmanager.com facebook.net hotjar.com
    doubleclick.net connect.facebook.net analytics monorail-edge.shopifysvc.com
    shopifysvc.com /api/collect favicon.ico
  ].freeze

  RELEVANT_RESOURCE_TYPES = %w[document stylesheet script xhr fetch image].freeze

  # Returns parsed network errors, filtered to exclude irrelevant noise
  def parsed_network_errors
    return [] if network_errors.blank?
    errors = network_errors.is_a?(Array) ? network_errors : []
    errors.select do |error|
      url = error["url"].to_s.downcase
      resource_type = error["resource_type"].to_s.downcase
      RELEVANT_RESOURCE_TYPES.include?(resource_type) &&
        IRRELEVANT_NETWORK_PATTERNS.none? { |pattern| url.include?(pattern) }
    end
  end

  # Returns parsed detection results from the detection engine
  def parsed_dom_checks_data
    return [] if dom_checks_data.blank?

    # Handle both Array (properly deserialized) and String (JSON string) formats
    if dom_checks_data.is_a?(Array)
      dom_checks_data
    elsif dom_checks_data.is_a?(String)
      JSON.parse(dom_checks_data) rescue []
    else
      []
    end
  end

  # Whether a screenshot is available for display
  def has_screenshot?
    screenshot_url.present?
  end

  # Returns the key/path suitable for use with screenshot_path() route helper.
  # Strips leading "/" from local paths since the route adds /screenshots/ prefix.
  def screenshot_display_key
    return nil unless screenshot_url.present?
    screenshot_url.sub(%r{^/screenshots/}, "")
  end
end
