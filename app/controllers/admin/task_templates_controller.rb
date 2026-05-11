class Admin::TaskTemplatesController < Admin::BaseController
  before_action :set_task_template, only: [:edit, :update, :destroy]
  before_action :set_team, only: [:new, :create]

  def new
    @task_template = @team.task_templates.build
  end

  def create
    @task_template = @team.task_templates.build(task_template_params)
    if @task_template.save
      redirect_to admin_teams_path, notice: "Task \"#{@task_template.name}\" was added."
    else
      flash.now[:alert] = @task_template.errors.full_messages.to_sentence
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @task_template.update(task_template_params)
      redirect_to admin_teams_path, notice: "Task \"#{@task_template.name}\" was updated."
    else
      flash.now[:alert] = @task_template.errors.full_messages.to_sentence
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @task_template.destroy
    redirect_to admin_teams_path, notice: "Task was deleted."
  end

  private

  def set_task_template
    @task_template = TaskTemplate.find(params[:id])
  end

  def set_team
    @team = Team.find(params[:team_id])
  end

  def task_template_params
    params.require(:task_template).permit(:name, :dynamic)
  end
end
