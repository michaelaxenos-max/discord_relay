class Admin::MemberSyncController < Admin::BaseController
  def index
    @members_by_team = HubstaffMember.by_team.group_by(&:team_name)
    @team_order      = ["Funnel Builders", "Editor", "Facebook Launcher", "Customer Support"]
  end

  def resync_members
    HubstaffService.new.sync_members_to_db
    redirect_to admin_member_sync_index_path, notice: "Members synced from Hubstaff (#{HubstaffMember.count} total)."
  rescue => e
    redirect_to admin_member_sync_index_path, alert: "Sync failed: #{e.message}"
  end

  def sync
    member_ids  = Array(params[:member_ids]).map(&:to_i).reject(&:zero?)
    project_ids = params[:project_ids].to_s.split(/[\s,\n]+/).map(&:strip).reject(&:blank?)

    if member_ids.empty?
      redirect_to admin_member_sync_index_path, alert: "Select at least one member."
      return
    end
    if project_ids.empty?
      redirect_to admin_member_sync_index_path, alert: "Enter at least one project ID."
      return
    end

    members = HubstaffMember.where(id: member_ids).select { |m| m.team_name.present? }

    members.each do |member|
      MemberSyncJob.perform_later(member_id: member.id, project_ids: project_ids)
    end

    redirect_to admin_member_sync_index_path,
      notice: "Queued #{members.size} member(s) across #{project_ids.size} project(s) — they will be added to existing tasks. Check Job Queues for progress."
  end
end
