module Api
  class ProjectsController < ApplicationController
    def create
      project_name = params.require(:project_name)
      row_number   = params.require(:row_number).to_i
      dynamic_task = params[:dynamic_task]
      hours        = params[:hours]

      CreateHubstaffProjectJob.perform_later(
        project_name: project_name,
        row_number:   row_number,
        dynamic_task: dynamic_task,
        hours:        hours
      )

      render json: { success: true, message: "Project creation queued" }, status: :accepted
    rescue ActionController::ParameterMissing => e
      render json: { success: false, error: e.message }, status: :bad_request
    rescue ArgumentError => e
      render json: { success: false, error: e.message }, status: :unprocessable_entity
    end

    def destroy
      project_id = params.require(:id)

      HubstaffService.new.delete_project(project_id)
      render json: { success: true }, status: :ok
    rescue ActionController::ParameterMissing => e
      render json: { success: false, error: e.message }, status: :bad_request
    rescue => e
      render json: { success: false, error: e.message }, status: :internal_server_error
    end
  end
end
