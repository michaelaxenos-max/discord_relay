class CreateProjectTasks < ActiveRecord::Migration[8.1]
  def change
    create_table :project_tasks do |t|
      t.references :project, null: false, foreign_key: true
      t.string  :hubstaff_task_id, null: false
      t.string  :name,             null: false
      t.boolean :dynamic,          null: false, default: false
      t.timestamps
    end

    add_index :project_tasks, [:project_id, :hubstaff_task_id], unique: true
  end
end
