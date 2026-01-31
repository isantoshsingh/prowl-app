# frozen_string_literal: true

class CreateAlerts < ActiveRecord::Migration[8.1]
  def change
    create_table :alerts do |t|
      t.references :shop, null: false, foreign_key: true
      t.references :issue, null: false, foreign_key: true
      t.string :alert_type, null: false
      t.datetime :sent_at
      t.string :delivery_status, default: "pending", null: false

      t.timestamps
    end

    add_index :alerts, [:shop_id, :issue_id], unique: true
    add_index :alerts, :alert_type
    add_index :alerts, :delivery_status
  end
end
