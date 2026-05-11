namespace :hubstaff do
  desc "Archive duplicate Hubstaff projects, keeping the oldest one per name"
  task dedup_projects: :environment do
    service  = HubstaffService.new
    projects = service.org_projects(status: "active")

    grouped = projects.group_by { |p| p["name"].to_s.strip.downcase }
    dupes   = grouped.select { |_name, group| group.size > 1 }

    if dupes.empty?
      puts "No duplicate projects found."
      next
    end

    puts "Found #{dupes.size} project name(s) with duplicates:\n\n"

    dupes.each do |name, group|
      # Keep the one with the lowest (oldest) ID
      sorted  = group.sort_by { |p| p["id"].to_i }
      keep    = sorted.first
      archive = sorted[1..]

      puts "  \"#{group.first["name"]}\""
      puts "    Keep:    ID #{keep["id"]}"
      archive.each do |p|
        puts "    Archive: ID #{p["id"]}"
        begin
          service.delete_project(p["id"])
          Project.find_by(hubstaff_project_id: p["id"].to_s)&.update!(status: "archived")
          puts "             -> archived"
        rescue => e
          puts "             -> FAILED: #{e.message}"
        end
      end
      puts
    end

    puts "Done."
  end

  desc "Sync archived/deleted Hubstaff project statuses to our DB"
  task sync_archived: :environment do
    service        = HubstaffService.new
    active_ids     = service.org_projects(status: "active").map { |p| p["id"].to_s }.to_set

    candidates = Project.where(status: "active").where.not(hubstaff_project_id: [nil, ""])
    archived_count = 0

    candidates.each do |project|
      next if active_ids.include?(project.hubstaff_project_id.to_s)
      project.update!(status: "archived")
      puts "Archived in DB: #{project.name} (Hubstaff ID #{project.hubstaff_project_id})"
      archived_count += 1
    end

    puts archived_count > 0 ? "\nMarked #{archived_count} project(s) as archived." : "All active DB projects are active in Hubstaff."
  end
end
