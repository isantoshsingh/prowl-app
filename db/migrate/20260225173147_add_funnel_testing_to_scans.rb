# frozen_string_literal: true

class AddFunnelTestingToScans < ActiveRecord::Migration[8.1]
  def change
    add_column :scans, :scan_depth, :string, default: "quick"
    add_column :scans, :funnel_results, :jsonb, default: {}
  end
end
