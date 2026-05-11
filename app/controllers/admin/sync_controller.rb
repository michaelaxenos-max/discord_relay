class Admin::SyncController < Admin::BaseController
  def new
    @user_id = params.require(:user_id)
    service  = HubstaffService.new
    members  = service.org_members_with_users
    @user    = members.find { |m| m[:hubstaff_user_id].to_s == @user_id.to_s }
    render :new
  rescue ActionController::ParameterMissing
    redirect_to admin_root_path, alert: "user_id is required."
  rescue => e
    Rails.logger.error "Sync#new error: #{e.message}"
    redirect_to admin_root_path, alert: "Could not load user: #{e.message}"
  end

  def create
    user_id     = params.require(:user_id)
    raw_ids     = params[:project_ids].to_s
    project_ids = raw_ids.split("\n").map(&:strip).reject(&:blank?)

    if project_ids.empty?
      redirect_to new_admin_sync_path(user_id: user_id), alert: "Please enter at least one project ID."
      return
    end

    SyncUserToProjectsJob.perform_later(user_id: user_id, project_ids: project_ids)
    redirect_to admin_root_path, notice: "Sync job queued for #{project_ids.size} project(s)."
  rescue ActionController::ParameterMissing => e
    redirect_to admin_root_path, alert: e.message
  end
end
