class HubstaffMember < ApplicationRecord
  validates :hubstaff_user_id, presence: true, uniqueness: true

  scope :by_team, -> { order(:team_name, :name) }
end
