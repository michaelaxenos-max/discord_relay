class Admin::DashboardController < Admin::BaseController
  def index
    service = HubstaffService.new
    members = service.org_members_with_users
    teams   = service.org_teams

    @users = members.map do |m|
      team = teams.find { |t| t["name"].present? } # will be enriched below
      { hubstaff_user_id: m[:hubstaff_user_id],
        name:             m[:name],
        email:            m[:email],
        team_name:        nil,
        membership_role:  m[:membership_role] }
    end
  rescue => e
    Rails.logger.error "Dashboard fetch error: #{e.message}"
    @users = []
    flash.now[:alert] = "Could not load users from Hubstaff: #{e.message}"
  end
end
