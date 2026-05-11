Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  post   "discord/forum/post",   to: "discord#create_forum_post"
  post   "discord/forum/update", to: "discord#update_forum_post"
  delete "discord/forum/delete", to: "discord#delete_forum_post"

  namespace :api do
    resources :projects, only: [:create, :destroy]
  end

  devise_for :admin_users,
    path: "admin",
    path_names: { sign_in: "login", sign_out: "logout" },
    controllers: { sessions: "admin/sessions" }

  namespace :admin do
    root to: "dashboard#index"
    resources :teams do
      resources :task_templates, shallow: true
    end
    resources :sync, only: [:new, :create]
  end
end
