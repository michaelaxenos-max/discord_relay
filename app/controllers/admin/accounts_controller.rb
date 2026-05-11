class Admin::AccountsController < Admin::BaseController
  def edit
  end

  def update
    if current_admin_user.update_with_password(account_params)
      bypass_sign_in(current_admin_user)
      redirect_to edit_admin_account_path, notice: "Password updated successfully."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def account_params
    params.require(:admin_user).permit(:current_password, :password, :password_confirmation)
  end
end
