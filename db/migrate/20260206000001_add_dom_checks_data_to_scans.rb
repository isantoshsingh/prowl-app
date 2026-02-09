# frozen_string_literal: true

class AddDomChecksDataToScans < ActiveRecord::Migration[8.1]
  def change
    add_column :scans, :dom_checks_data, :text
  end
end
