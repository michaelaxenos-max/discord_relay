class Team < ApplicationRecord
  has_many :task_templates, dependent: :destroy

  validates :name, presence: true, uniqueness: true
end
