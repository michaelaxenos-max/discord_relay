class CreateHubstaffProjectJob < ApplicationJob
  queue_as :default

  retry_on HubstaffService::RateLimitError, wait: 1.minute, attempts: 10 do |job, error|
    row_number = job.arguments.first["row_number"]
    SheetsWriter.write_by_header(row_number, "Hubstaff Project ID", "Error: Rate limit exceeded after multiple retries")
  end

  retry_on ActiveRecord::StatementInvalid, wait: 5.seconds, attempts: 3

  def perform(project_name:, row_number:, dynamic_task: nil, hours: nil)
    project_id = HubstaffService.new.create_project_with_tasks(
      project_name: project_name,
      dynamic_task: dynamic_task,
      hours: hours
    )
    SheetsWriter.write_by_header(row_number, "Hubstaff Project ID", project_id)
  rescue HubstaffService::RateLimitError
    raise
  rescue ActiveRecord::StatementInvalid
    raise
  rescue => e
    SheetsWriter.write_by_header(row_number, "Hubstaff Project ID", "Error: #{e.message}")
  end
end
