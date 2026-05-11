class CreateProjectLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :project_logs do |t|
      t.references :project, null: false, foreign_key: true
      t.string :event,   null: false
      t.text   :message
      t.timestamps
    end

    add_index :project_logs, [:project_id, :created_at]
  end
end
