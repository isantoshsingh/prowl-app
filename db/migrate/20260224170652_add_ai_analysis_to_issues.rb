class AddAiAnalysisToIssues < ActiveRecord::Migration[8.1]
  def change
    add_column :issues, :ai_confirmed, :boolean
    add_column :issues, :ai_confidence, :float
    add_column :issues, :ai_reasoning, :text
    add_column :issues, :ai_explanation, :text
    add_column :issues, :ai_suggested_fix, :text
    add_column :issues, :ai_verified_at, :datetime
  end
end
