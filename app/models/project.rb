class Project < ApplicationRecord
  STATUSES = %w[pending active archived failed].freeze

  has_many :project_logs,  dependent: :destroy
  has_many :project_tasks, dependent: :destroy

  validates :name, presence: true
  validates :status, inclusion: { in: STATUSES }

  def log(event, message)
    project_logs.create!(event: event, message: message)
  rescue => e
    Rails.logger.warn "ProjectLog write failed: #{e.message}"
  end
end
