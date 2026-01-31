# frozen_string_literal: true

class CreateShopSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :shop_settings do |t|
      t.references :shop, null: false, foreign_key: true, index: { unique: true }
      t.string :alert_email
      t.boolean :email_alerts_enabled, default: true, null: false
      t.boolean :admin_alerts_enabled, default: true, null: false
      t.string :scan_frequency, default: "daily", null: false
      t.integer :max_monitored_pages, default: 5, null: false
      t.datetime :trial_ends_at
      t.string :billing_status, default: "trial", null: false
      t.bigint :subscription_charge_id

      t.timestamps
    end

    add_index :shop_settings, :billing_status
  end
end
