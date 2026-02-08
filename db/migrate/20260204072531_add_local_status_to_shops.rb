class AddLocalStatusToShops < ActiveRecord::Migration[8.1]
  def change
    add_column :shops, :subscription_status, :string
    add_column :shops, :subscription_plan, :string
  end
end
