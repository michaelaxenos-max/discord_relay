class ResyncProjectJob < ApplicationJob
  queue_as :default

  def perform(hubstaff_project_id:, project_record_id: nil)
    record  = Project.find_by(id: project_record_id)
    service = HubstaffService.new

    service.sync_tasks_to_project(hubstaff_project_id)
    service.sync_task_assignees(hubstaff_project_id)
    sync_tasks_to_db(record, hubstaff_project_id) if record

    record&.log("created", "Tasks and assignees resynced")
  rescue => e
    Rails.logger.error "ResyncProjectJob failed for #{hubstaff_project_id}: #{e.message}"
    Project.find_by(id: project_record_id)&.log("error", "Resync failed: #{e.message}") rescue nil
  end

  private

  def sync_tasks_to_db(project_record, hubstaff_project_id)
    tasks         = HubstaffService.new.get_project_tasks(hubstaff_project_id)
    dynamic_names = TaskTemplate.where(dynamic: true).pluck(:name).to_set

    tasks.each do |task|
      ProjectTask.find_or_create_by!(
        project:          project_record,
        hubstaff_task_id: task["id"].to_s
      ) do |t|
        t.name    = task["summary"].to_s
        t.dynamic = dynamic_names.include?(task["summary"].to_s)
      end
    end
  rescue => e
    Rails.logger.warn "ResyncProjectJob: DB task sync failed — #{e.message}"
  end
end
