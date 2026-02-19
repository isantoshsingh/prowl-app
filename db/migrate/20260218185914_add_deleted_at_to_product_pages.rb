class AddDeletedAtToProductPages < ActiveRecord::Migration[8.1]
  def change
    add_column :product_pages, :deleted_at, :datetime
    add_index  :product_pages, :deleted_at
  end
end

