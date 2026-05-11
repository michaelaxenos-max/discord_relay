class SyncUserToProjectsJob < ApplicationJob
  queue_as :default

  def perform(user_id:, project_ids:)
    service    = HubstaffService.new
    user_teams = service.user_team_names(user_id)

    project_ids.each do |project_id|
      # Add user to project
      service.add_member_to_project(project_id, user_id)

      # Get tasks in this project
      project_tasks = service.get_project_tasks(project_id)

      # Get task names for this user's teams from DB
      team_task_names = TaskTemplate.joins(:team)
                                    .where(teams: { name: user_teams })
                                    .pluck(:name)

      # Match and assign
      project_tasks.each do |task|
        next unless team_task_names.include?(task["summary"])
        service.add_assignee_to_task(task["id"], user_id)
      end
    end
  end
end
