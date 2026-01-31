# frozen_string_literal: true

class CreateIssues < ActiveRecord::Migration[8.1]
  def change
    create_table :issues do |t|
      t.references :product_page, null: false, foreign_key: true
      t.references :scan, null: false, foreign_key: true
      t.string :issue_type, null: false
      t.string :severity, null: false
      t.string :title, null: false
      t.text :description
      t.text :evidence
      t.integer :occurrence_count, default: 1, null: false
      t.datetime :first_detected_at, null: false
      t.datetime :last_detected_at, null: false
      t.string :status, default: "open", null: false
      t.datetime :acknowledged_at
      t.string :acknowledged_by

      t.timestamps
    end

    add_index :issues, [:product_page_id, :status]
    add_index :issues, [:product_page_id, :issue_type, :status]
    add_index :issues, :severity
    add_index :issues, :status
  end
end
