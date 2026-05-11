class Admin::ProjectResyncController < Admin::BaseController
  def new
  end

  def create
    raw_ids     = params[:project_ids].to_s
    project_ids = raw_ids.split("\n").map(&:strip).reject(&:blank?)

    if project_ids.empty?
      redirect_to new_admin_project_resync_path, alert: "Please enter at least one project ID."
      return
    end

    ResyncProjectTasksJob.perform_later(project_ids: project_ids)
    redirect_to admin_root_path, notice: "Task resync queued for #{project_ids.size} project(s)."
  end
end
