class MemberSyncJob < ApplicationJob
  queue_as :default

  def perform(member_id:, project_ids:)
    member  = HubstaffMember.find(member_id)
    return unless member.team_name.present?

    service = HubstaffService.new
    project_ids.each do |pid|
      service.create_user_tasks_for_project(pid, member.hubstaff_user_id, member.team_name)
    rescue => e
      Rails.logger.error "MemberSyncJob failed for #{member.name} / project #{pid}: #{e.message}"
    end
  end
end
