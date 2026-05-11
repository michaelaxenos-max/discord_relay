class Admin::AdminUsersController < Admin::BaseController
  def index
    @admin_users = AdminUser.order(:email)
  end

  def new
    @admin_user = AdminUser.new
  end

  def create
    @admin_user = AdminUser.new(admin_user_params)
    if @admin_user.save
      redirect_to admin_admin_users_path, notice: "User #{@admin_user.email} created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    user = AdminUser.find(params[:id])
    if user == current_admin_user
      redirect_to admin_admin_users_path, alert: "You can't delete your own account."
      return
    end
    user.destroy!
    redirect_to admin_admin_users_path, notice: "User removed."
  end

  private

  def admin_user_params
    params.require(:admin_user).permit(:email, :password, :password_confirmation)
  end
end
