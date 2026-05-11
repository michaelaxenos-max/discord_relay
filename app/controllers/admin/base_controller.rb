class Admin::BaseController < ActionController::Base
  before_action :authenticate_admin_user!
  layout "admin"
end
