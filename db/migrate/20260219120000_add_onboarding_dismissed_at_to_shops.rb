# frozen_string_literal: true

class AddOnboardingDismissedAtToShops < ActiveRecord::Migration[8.1]
  def change
    add_column :shops, :onboarding_dismissed_at, :datetime
  end
end
