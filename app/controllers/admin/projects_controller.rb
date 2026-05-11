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

  def bulk_resync
    ids = Array(params[:project_ids]).map(&:to_i).reject(&:zero?)
    if ids.empty?
      redirect_to admin_projects_path, alert: "No projects selected."
      return
    end

    projects = Project.where(id: ids, status: "active").where.not(hubstaff_project_id: [nil, ""])
    if projects.empty?
      redirect_to admin_projects_path, alert: "None of the selected projects have a Hubstaff ID."
      return
    end

    projects.each do |project|
      ResyncProjectJob.perform_later(
        hubstaff_project_id: project.hubstaff_project_id,
        project_record_id:   project.id
      )
    end

    redirect_to admin_projects_path, notice: "Resync queued for #{projects.size} project(s) — tasks and assignees will be updated shortly."
  end

  def resync_project
    @project = Project.find(params[:id])
    unless @project.hubstaff_project_id.present?
      redirect_to admin_project_path(@project), alert: "No Hubstaff project ID — sync from Hubstaff first."
      return
    end

    ResyncProjectJob.perform_later(
      hubstaff_project_id: @project.hubstaff_project_id,
      project_record_id:   @project.id
    )
    redirect_to admin_project_path(@project), notice: "Resync queued for \"#{@project.name}\" — tasks and assignees will be updated shortly."
  end
end
