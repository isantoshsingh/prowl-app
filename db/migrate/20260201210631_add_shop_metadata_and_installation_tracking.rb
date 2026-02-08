# frozen_string_literal: true

class AddShopMetadataAndInstallationTracking < ActiveRecord::Migration[8.1]
  def change
    # Shop identifiers
    add_column :shops, :shopify_shop_id, :bigint
    add_column :shops, :shop_created_at, :datetime
    
    # Shop metadata
    add_column :shops, :shop_owner, :string
    add_column :shops, :email, :string
    add_column :shops, :country_code, :string, limit: 2
    add_column :shops, :country_name, :string
    add_column :shops, :currency, :string, limit: 3
    add_column :shops, :timezone, :string
    add_column :shops, :iana_timezone, :string
    add_column :shops, :plan_name, :string
    add_column :shops, :plan_display_name, :string
    add_column :shops, :primary_locale, :string, limit: 5
    
    # Shop flags
    add_column :shops, :password_enabled, :boolean
    add_column :shops, :pre_launch_enabled, :boolean
    
    # Installation tracking
    add_column :shops, :installed, :boolean, default: true, null: false
    add_column :shops, :installed_at, :datetime
    add_column :shops, :uninstalled_at, :datetime
    
    # Raw webhook data (complete shop payload)
    add_column :shops, :shop_json, :jsonb, default: {}
    
    # Indexes for common queries
    add_index :shops, :shopify_shop_id, unique: true
    add_index :shops, :installed
    add_index :shops, :country_code
    add_index :shops, :plan_name
    add_index :shops, :shop_json, using: :gin
  end
end
