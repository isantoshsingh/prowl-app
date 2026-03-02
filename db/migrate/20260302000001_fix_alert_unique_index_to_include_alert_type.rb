class FixAlertUniqueIndexToIncludeAlertType < ActiveRecord::Migration[8.1]
  def change
    # The current unique index on (shop_id, issue_id) prevents creating both
    # email and admin alerts for the same issue. The model validates uniqueness
    # scoped to alert_type, so the DB constraint should match.
    remove_index :alerts, name: "index_alerts_on_shop_id_and_issue_id"
    add_index :alerts, [:shop_id, :issue_id, :alert_type],
      unique: true,
      name: "index_alerts_on_shop_issue_and_type"
  end
end
