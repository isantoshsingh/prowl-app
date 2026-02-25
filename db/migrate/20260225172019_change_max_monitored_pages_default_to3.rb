# frozen_string_literal: true

class ChangeMaxMonitoredPagesDefaultTo3 < ActiveRecord::Migration[8.1]
  def change
    change_column_default :shop_settings, :max_monitored_pages, from: 5, to: 3

    # Update existing shops that still have the old default
    reversible do |dir|
      dir.up do
        execute "UPDATE shop_settings SET max_monitored_pages = 3 WHERE max_monitored_pages = 5"
      end
      dir.down do
        execute "UPDATE shop_settings SET max_monitored_pages = 5 WHERE max_monitored_pages = 3"
      end
    end
  end
end
