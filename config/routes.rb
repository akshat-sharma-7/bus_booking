require "sidekiq/web"

Rails.application.routes.draw do
  resource :session
  resources :passwords, param: :token
  resource :registration, only: %i[ new create ]

  # Placeholder until Step 2/3 create TripsController — visiting "/" will
  # 404 until then; /session/new and /registration/new work today.
  # root "trips#index"

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  mount Sidekiq::Web => "/sidekiq"
end
