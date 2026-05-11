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
          # Update our DB record if it exists
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
end
