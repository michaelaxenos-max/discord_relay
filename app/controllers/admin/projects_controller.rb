class Admin::ProjectsController < Admin::BaseController
  def index
    @projects = Project.includes(:project_tasks).order(created_at: :desc).limit(500)
  end

  def show
    @project = Project.includes(:project_tasks, :project_logs).find(params[:id])
    @tasks   = @project.project_tasks.order(:name)
    @logs    = @project.project_logs.order(created_at: :asc)
  end

  def resync
    SyncProjectsFromHubstaffJob.perform_later
    redirect_to admin_projects_path, notice: "Project sync queued — the list will update shortly."
  end
end
