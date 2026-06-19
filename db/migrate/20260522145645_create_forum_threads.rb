class CreateForumThreads < ActiveRecord::Migration[8.1]
  def change
    create_table :forum_threads do |t|
      t.string :channel_id, null: false
      t.string :title, null: false
      t.string :thread_id, null: false

      t.timestamps
    end

    add_index :forum_threads, [:channel_id, :title], unique: true
  end
end
