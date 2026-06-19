Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  post   "discord/forum/post",   to: "discord#create_forum_post"
  post   "discord/forum/update", to: "discord#update_forum_post"
  delete "discord/forum/delete", to: "discord#delete_forum_post"

  namespace :api do
    resources :projects, only: [:create, :destroy]
    resources :task_templates, only: [:index]
  end

  devise_for :admin_users,
    path: "admin",
    path_names: { sign_in: "login", sign_out: "logout" },
    controllers: { sessions: "admin/sessions" }

  mount MissionControl::Jobs::Engine, at: "/admin/jobs"

  namespace :admin do
    resources :admin_users, only: [:index, :new, :create, :destroy]
    resource :account, only: [:edit, :update]
    root to: "dashboard#index"
    resources :teams, only: [:index] do
      collection { post :resync }
      resources :task_templates, shallow: true
    end
    resources :member_sync, only: [:index] do
      collection do
        post :resync_members
        post :sync
      end
    end
    resources :sync, only: [:new, :create]
    resources :project_resync, only: [:new, :create]
    resources :projects, only: [:index, :show, :destroy] do
      collection do
        post :resync
        post :bulk_resync
      end
      member do
        post :resync_project
        get  :new_task
        post :add_task
        delete :remove_task
      end
    end
  end
end
