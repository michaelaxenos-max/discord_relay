class ResyncProjectTasksJob < ApplicationJob
  queue_as :default

  def perform(project_ids:)
    service = HubstaffService.new
    project_ids.each do |project_id|
      service.sync_tasks_to_project(project_id)
      service.sync_task_assignees(project_id)
    rescue => e
      Rails.logger.error "ResyncProjectTasksJob failed for project #{project_id}: #{e.message}"
    end
  end
end
