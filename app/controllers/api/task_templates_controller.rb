module Api
  class TaskTemplatesController < ApplicationController
    before_action :authenticate!

    def index
      templates = TaskTemplate.includes(:team).order(:name)

      render json: {
        task_templates: templates.map { |t|
          {
            id: t.id,
            name: t.name,
            dynamic: t.dynamic,
            team: t.team.name
          }
        }
      }
    end

    private

    def authenticate!
      expected = ENV["KPI_DASHBOARD_API_KEY"].presence
      return if expected.nil? # no key configured = open (dev convenience)

      provided = request.headers["X-Api-Key"] || params[:api_key]
      render json: { error: "Unauthorized" }, status: :unauthorized unless provided == expected
    end
  end
end
