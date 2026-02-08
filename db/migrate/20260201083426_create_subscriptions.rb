class CreateSubscriptions < ActiveRecord::Migration[8.1]
  def change
    create_table :subscriptions do |t|
      t.references :shop, null: false, foreign_key: true, index: true
      t.string :subscription_charge_id, index: { unique: true }
      t.string :status, null: false, default: 'pending'
      t.string :charge_name
      t.decimal :price, precision: 10, scale: 2
      t.string :currency_code
      t.integer :trial_days
      t.datetime :trial_ends_at
      t.datetime :activated_at
      t.datetime :cancelled_at

      t.timestamps
    end
    
    # Additional indexes for querying
    add_index :subscriptions, [:shop_id, :status]
    add_index :subscriptions, [:shop_id, :created_at]
  end
end
