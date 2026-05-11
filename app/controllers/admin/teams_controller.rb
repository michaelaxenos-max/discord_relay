class Admin::TeamsController < Admin::BaseController
  def index
    @teams = Team.includes(:task_templates).order(:name)
  end

  def resync
    hubstaff_teams = HubstaffService.new.org_teams
    synced = 0
    hubstaff_teams.each do |t|
      Team.find_or_create_by!(name: t["name"])
      synced += 1
    end
    redirect_to admin_teams_path, notice: "Synced #{synced} team(s) from Hubstaff."
  rescue => e
    redirect_to admin_teams_path, alert: "Resync failed: #{e.message}"
  end

end
