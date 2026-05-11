Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  post   "discord/forum/post",   to: "discord#create_forum_post"
  post   "discord/forum/update", to: "discord#update_forum_post"
  delete "discord/forum/delete", to: "discord#delete_forum_post"

  namespace :api do
    resources :projects, only: [:create, :destroy]
  end
end
