# frozen_string_literal: true

class CreateScans < ActiveRecord::Migration[8.1]
  def change
    create_table :scans do |t|
      t.references :product_page, null: false, foreign_key: true
      t.string :status, default: "pending", null: false
      t.datetime :started_at
      t.datetime :completed_at
      t.string :screenshot_url
      t.text :html_snapshot
      t.text :js_errors
      t.text :network_errors
      t.text :console_logs
      t.integer :page_load_time_ms
      t.text :error_message

      t.timestamps
    end

    add_index :scans, [:product_page_id, :created_at]
    add_index :scans, :status
    add_index :scans, :started_at
  end
end
