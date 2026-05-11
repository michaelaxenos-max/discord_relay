class Admin::TeamsController < Admin::BaseController
  before_action :set_team, only: [:show, :edit, :update, :destroy]

  def index
    @teams = Team.includes(:task_templates).order(:name)
    @new_team = Team.new
  end

  def show
    redirect_to admin_teams_path
  end

  def new
    @team = Team.new
  end

  def create
    @team = Team.new(team_params)
    if @team.save
      redirect_to admin_teams_path, notice: "Team \"#{@team.name}\" was created."
    else
      @teams = Team.includes(:task_templates).order(:name)
      @new_team = @team
      flash.now[:alert] = @team.errors.full_messages.to_sentence
      render :index, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @team.update(team_params)
      redirect_to admin_teams_path, notice: "Team \"#{@team.name}\" was updated."
    else
      flash.now[:alert] = @team.errors.full_messages.to_sentence
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @team.destroy
    redirect_to admin_teams_path, notice: "Team was deleted."
  end

  private

  def set_team
    @team = Team.find(params[:id])
  end

  def team_params
    params.require(:team).permit(:name)
  end
end
