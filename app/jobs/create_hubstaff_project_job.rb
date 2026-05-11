class CreateHubstaffProjectJob < ApplicationJob
  queue_as :default

  retry_on HubstaffService::RateLimitError, wait: 1.minute, attempts: 10 do |job, error|
    args = job.arguments.first
    SheetsWriter.write_by_header(args["row_number"], "Hubstaff Project ID", "Error: Rate limit exceeded after multiple retries")
    with_record(args["project_record_id"]) { |r| r.log("error", "Rate limit exceeded after 10 retries"); r.update!(status: "failed") }
  end

  retry_on ActiveRecord::StatementInvalid, wait: 5.seconds, attempts: 3 do |job, error|
    args = job.arguments.first
    SheetsWriter.write_by_header(args["row_number"], "Hubstaff Project ID", "Error: Database connection failed, please retry")
    with_record(args["project_record_id"]) { |r| r.log("error", "DB connection failed after retries"); r.update!(status: "failed") }
  end

  retry_on ActiveRecord::ConnectionNotEstablished, wait: 5.seconds, attempts: 3 do |job, error|
    args = job.arguments.first
    SheetsWriter.write_by_header(args["row_number"], "Hubstaff Project ID", "Error: Database connection failed, please retry")
    with_record(args["project_record_id"]) { |r| r.log("error", "DB connection not established after retries"); r.update!(status: "failed") }
  end

  def perform(project_name:, row_number:, dynamic_task: nil, hours: nil, project_record_id: nil)
    record  = Project.find_by(id: project_record_id)
    service = HubstaffService.new

    # Check our DB first
    existing_record = Project.where.not(hubstaff_project_id: [nil, ""])
                             .find_by("LOWER(name) = ?", project_name.to_s.strip.downcase)

    project_id = if existing_record&.hubstaff_project_id.present?
      record&.log("created", "Reused existing Hubstaff project (DB match) with ID #{existing_record.hubstaff_project_id}")
      existing_record.hubstaff_project_id
    elsif (hubstaff_match = service.find_project_by_name(project_name))
      record&.log("created", "Reused existing Hubstaff project (API match) with ID #{hubstaff_match["id"]}")
      hubstaff_match["id"].to_s
    else
      id = service.create_project_with_tasks(
        project_name: project_name,
        dynamic_task: dynamic_task,
        hours:        hours
      )
      record&.log("created", "Hubstaff project created with ID #{id}")
      id
    end

    record&.update!(hubstaff_project_id: project_id.to_s, status: "active")
    SheetsWriter.write_by_header(row_number, "Hubstaff Project ID", project_id)
    record&.log("sheet_written", "Project ID #{project_id} written to sheet row #{row_number}")
  rescue HubstaffService::RateLimitError
    record&.log("error", "Rate limit hit — retrying in 1 minute") rescue nil
    raise
  rescue ActiveRecord::StatementInvalid
    record&.log("error", "DB StatementInvalid — retrying") rescue nil
    raise
  rescue ActiveRecord::ConnectionNotEstablished
    record&.log("error", "DB connection lost — retrying") rescue nil
    raise
  rescue => e
    record&.update!(status: "failed") rescue nil
    record&.log("error", e.message) rescue nil
    SheetsWriter.write_by_header(row_number, "Hubstaff Project ID", "Error: #{e.message}")
  end

  private

  def self.with_record(id, &block)
    record = Project.find_by(id: id)
    block.call(record) if record
  rescue => e
    Rails.logger.warn "with_record failed: #{e.message}"
  end
end
