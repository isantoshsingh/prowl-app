# frozen_string_literal: true

# Subscription model tracks billing subscription history for shops.
# A shop can have multiple subscriptions across install/reinstall cycles.
#
# Statuses:
#   - pending: Subscription created, awaiting merchant approval
#   - active: Subscription approved and active
#   - cancelled: Subscription cancelled (on uninstall or manually)
#   - expired: Trial expired without activation
#   - declined: Merchant declined billing during installation
#
class Subscription < ApplicationRecord
  # Associations
  belongs_to :shop

  # Validations
  validates :status, presence: true, inclusion: { in: %w[pending active cancelled expired declined] }
  validates :subscription_charge_id, uniqueness: true, allow_nil: true

  # Scopes
  scope :active, -> { where(status: 'active') }
  scope :pending, -> { where(status: 'pending') }
  scope :cancelled, -> { where(status: 'cancelled') }
  scope :expired, -> { where(status: 'expired') }
  scope :declined, -> { where(status: 'declined') }
  scope :for_shop, ->(shop) { where(shop: shop).order(created_at: :desc) }

  # Instance methods

  # Activates the subscription after merchant approval
  def activate!(charge_id)
    update!(
      status: 'active',
      subscription_charge_id: charge_id,
      activated_at: Time.current
    )
  end

  # Cancels the subscription (on uninstall or manual cancellation)
  def cancel!
    update!(
      status: 'cancelled',
      cancelled_at: Time.current
    )
  end

  # Marks trial as expired
  def expire!
    update!(status: 'expired')
  end

  # Marks as declined
  def decline!
    update!(status: 'declined')
  end

  # Checks if subscription is currently active
  def active?
    status == 'active'
  end

  # Checks if in trial period
  def in_trial?
    return false unless activated_at && trial_days.to_i > 0
    Time.current < (activated_at + trial_days.days)
  end

  # Returns days remaining in trial
  def trial_days_remaining
    return 0 unless in_trial?
    ((trial_ends_at - Time.current) / 1.day).ceil
  end

  # Calculates trial end date from activated_at + trial_days
  def trial_ends_at
    return nil unless activated_at && trial_days.to_i > 0
    activated_at + trial_days.days
  end
end
