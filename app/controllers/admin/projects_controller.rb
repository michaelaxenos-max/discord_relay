class Admin::ProjectsController < Admin::BaseController
  def index
    @projects = Project.includes(:project_tasks).order(created_at: :desc).limit(500)
  end

  def show
    @project = Project.includes(:project_tasks, :project_logs).find(params[:id])
    @tasks   = @project.project_tasks.order(:name)
    @logs    = @project.project_logs.order(created_at: :asc)
  end

  def destroy
    @project = Project.find(params[:id])
    @project.destroy!
    redirect_to admin_projects_path, notice: "\"#{@project.name}\" deleted."
  rescue => e
    redirect_to admin_project_path(params[:id]), alert: "Failed to delete: #{e.message}"
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

  def new_task
    @project = Project.find(params[:id])
    service  = RelayCore::HubstaffService.new

    members  = service.org_members_with_users.select { |m| m[:name].present? }
    teams    = service.org_teams

    # Build user_id -> [team_names] map
    team_by_user = {}
    teams.each do |team|
      service.team_member_ids(team["id"]).each do |uid|
        team_by_user[uid] ||= []
        team_by_user[uid] << team["name"]
      end
    end

    members_with_team = members.map { |m| m.merge(team: (team_by_user[m[:hubstaff_user_id]] || []).first || "No Team") }

    team_order = ["Funnel Builders", "Editor", "Facebook Launcher", "Customer Support"]

    @members_by_team = members_with_team
      .sort_by { |m| m[:name] }
      .group_by { |m| m[:team] }
      .sort_by  { |team, _| [team_order.index(team) || 99, team] }
      .to_h
  rescue => e
    redirect_to admin_project_path(@project), alert: "Failed to load members: #{e.message}"
  end

  def add_task
    @project     = Project.find(params[:id])
    task_name    = params[:task_name].to_s.strip
    assignee_ids = Array(params[:assignee_ids]).map(&:to_i).reject(&:zero?)

    if task_name.blank?
      redirect_to new_task_admin_project_path(@project), alert: "Task name can't be blank."
      return
    end

    service = RelayCore::HubstaffService.new
    task_id = service.add_task_to_project(
      @project.hubstaff_project_id,
      task_name,
      assignee_ids: assignee_ids.presence
    )

    dynamic_names = TaskTemplate.where(dynamic: true).pluck(:name).to_set
    @project.project_tasks.create!(
      hubstaff_task_id: task_id.to_s,
      name:             task_name,
      dynamic:          dynamic_names.include?(task_name)
    )

    redirect_to admin_project_path(@project), notice: "Task \"#{task_name}\" added."
  rescue => e
    redirect_to admin_project_path(@project), alert: "Failed to add task: #{e.message}"
  end

  def remove_task
    @project = Project.find(params[:id])
    task     = @project.project_tasks.find(params[:task_id])

    RelayCore::HubstaffService.new.archive_task(task.hubstaff_task_id) if task.hubstaff_task_id.present?
    task.destroy!

    redirect_to admin_project_path(@project), notice: "Task \"#{task.name}\" removed."
  rescue => e
    redirect_to admin_project_path(@project), alert: "Failed to remove task: #{e.message}"
  end
end
