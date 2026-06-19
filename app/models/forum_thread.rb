class ForumThread < ApplicationRecord
  validates :channel_id, :title, :thread_id, presence: true
  validates :title, uniqueness: { scope: :channel_id }
end
