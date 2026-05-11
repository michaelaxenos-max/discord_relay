class CreateHubstaffMembers < ActiveRecord::Migration[8.1]
  def change
    create_table :hubstaff_members do |t|
      t.integer :hubstaff_user_id, null: false
      t.string  :name
      t.string  :email
      t.string  :team_name
      t.string  :membership_role

      t.timestamps
    end

    add_index :hubstaff_members, :hubstaff_user_id, unique: true
  end
end
