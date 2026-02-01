class RemoveBillingFieldsFromShopSettings < ActiveRecord::Migration[8.1]
  def change
    remove_column :shop_settings, :billing_status, :string
    remove_column :shop_settings, :subscription_charge_id, :bigint
    remove_column :shop_settings, :trial_ends_at, :datetime
  end
end
