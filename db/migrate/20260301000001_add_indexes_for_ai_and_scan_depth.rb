class AddIndexesForAiAndScanDepth < ActiveRecord::Migration[8.1]
  def change
    # Used by Issue.alertable scope: open + high_severity + ai_confirmed
    add_index :issues, :ai_confirmed, where: "ai_confirmed = true", name: "index_issues_on_ai_confirmed_true"

    # Used by ScanPdpJob to filter scans by depth
    add_index :scans, :scan_depth
  end
end
