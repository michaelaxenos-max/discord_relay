class CreateProjects < ActiveRecord::Migration[8.1]
  def change
    create_table :projects do |t|
      t.string  :name,                null: false
      t.string  :hubstaff_project_id
      t.integer :row_number
      t.string  :status,              null: false, default: "pending"
      t.timestamps
    end

    add_index :projects, :hubstaff_project_id
    add_index :projects, :row_number
    add_index :projects, :status
  end
end
