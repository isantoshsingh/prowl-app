class AddBillingExemptToShops < ActiveRecord::Migration[8.1]
  def change
    add_column :shops, :billing_exempt, :boolean, default: false, null: false
    add_column :shops, :exemption_reason, :string
    
    add_index :shops, :billing_exempt
  end
end
