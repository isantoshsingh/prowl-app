# frozen_string_literal: true

class AddConfirmationUrlToSubscriptions < ActiveRecord::Migration[8.1]
  def change
    add_column :subscriptions, :confirmation_url, :text
  end
end
