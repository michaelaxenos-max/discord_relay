class CreateTaskTemplates < ActiveRecord::Migration[8.1]
  def change
    create_table :task_templates do |t|
      t.string :name, null: false
      t.integer :team_id, null: false
      t.boolean :dynamic, null: false, default: false

      t.timestamps
    end

    add_index :task_templates, :team_id
  end
end
