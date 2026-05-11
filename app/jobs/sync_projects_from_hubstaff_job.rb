class SyncProjectsFromHubstaffJob < ApplicationJob
  queue_as :default

  def perform
    service          = HubstaffService.new
    hubstaff_projects = service.org_projects(status: "active")
    sheet_rows        = SheetsReader.new.all_rows

    # Build lookup maps from the sheet
    rows_by_hubstaff_id  = {}
    rows_by_funnel_name  = {}

    sheet_rows.each do |row|
      hs_id       = row[:data]["Hubstaff Project ID"].to_s.strip
      funnel_name = row[:data]["Funnel Name"].to_s.strip

      rows_by_hubstaff_id[hs_id]       = row if hs_id.present? && !%w[pending].include?(hs_id) && !hs_id.start_with?("Error")
      rows_by_funnel_name[funnel_name]  = row if funnel_name.present?
    end

    hubstaff_projects.each do |project|
      project_id   = project["id"].to_s
      project_name = project["name"].to_s
      row_number   = nil

      if rows_by_hubstaff_id[project_id]
        row_number = rows_by_hubstaff_id[project_id][:row_number]
      elsif rows_by_funnel_name[project_name]
        sheet_row  = rows_by_funnel_name[project_name]
        row_number = sheet_row[:row_number]
        SheetsWriter.write_by_header(row_number, "Hubstaff Project ID", project_id)
      end

      record = Project.find_or_initialize_by(hubstaff_project_id: project_id)
      record.name       = project_name
      record.row_number = row_number if row_number
      record.status     = "active"
      record.save!
    rescue => e
      Rails.logger.error "SyncProjectsFromHubstaffJob: failed for project #{project_id} — #{e.message}"
    end
  end
end
