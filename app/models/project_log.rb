class ProjectLog < ApplicationRecord
  belongs_to :project

  EVENTS = %w[created task_created member_added sheet_written error].freeze
end
