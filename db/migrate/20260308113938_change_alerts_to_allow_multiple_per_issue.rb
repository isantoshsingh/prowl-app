# frozen_string_literal: true

# Replaces the old index on [shop_id, issue_id, alert_type] (no uniqueness)
# with a new unique index on [shop_id, issue_id, alert_type, scan_id].
#
# This allows multiple alerts for the same issue across different scans,
# while preventing duplicates within a single scan.
class ChangeAlertsToAllowMultiplePerIssue < ActiveRecord::Migration[8.1]
  def change
    remove_index :alerts, name: "index_alerts_on_shop_issue_type", if_exists: true
    add_index :alerts, [:shop_id, :issue_id, :alert_type, :scan_id],
      unique: true,
      name: "index_alerts_on_shop_issue_type_scan"
  end
end
