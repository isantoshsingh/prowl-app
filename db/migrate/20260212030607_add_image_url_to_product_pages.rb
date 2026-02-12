class AddImageUrlToProductPages < ActiveRecord::Migration[8.1]
  def change
    add_column :product_pages, :image_url, :string
  end
end
