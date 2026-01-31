# frozen_string_literal: true

class CreateProductPages < ActiveRecord::Migration[8.1]
  def change
    create_table :product_pages do |t|
      t.references :shop, null: false, foreign_key: true
      t.bigint :shopify_product_id, null: false
      t.string :handle, null: false
      t.string :title, null: false
      t.string :url, null: false
      t.boolean :monitoring_enabled, default: true, null: false
      t.datetime :last_scanned_at
      t.string :status, default: "pending", null: false

      t.timestamps
    end

    add_index :product_pages, [:shop_id, :shopify_product_id], unique: true
    add_index :product_pages, [:shop_id, :monitoring_enabled]
    add_index :product_pages, :status
  end
end
