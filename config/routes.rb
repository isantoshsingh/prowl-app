# frozen_string_literal: true

Rails.application.routes.draw do
  # Webhook handlers (must be before ShopifyApp::Engine)
  post '/webhooks/app_uninstalled', to: 'webhooks/app_uninstalled#create'
  post '/webhooks/app_subscription_update', to: 'webhooks/app_subscription_update#create'
  post '/webhooks/shop_update', to: 'webhooks/shop_update#create'

  # Shopify App Engine (OAuth, etc.)
  mount ShopifyApp::Engine, at: "/"

  # Root - Dashboard (App Home Page)
  root to: "home#index"
  post "/dismiss_onboarding", to: "home#dismiss_onboarding", as: :dismiss_onboarding

  # Dashboard API
  get "/dashboard/stats", to: "dashboard#stats"

  # Product Pages (monitored PDPs)
  resources :product_pages, only: [:index, :show, :create, :destroy] do
    member do
      match :rescan, via: [:get, :post]
    end
  end

  # Issues
  resources :issues, only: [:index, :show] do
    member do
      match :acknowledge, via: [:get, :post]
    end
  end

  # Scans
  resources :scans, only: [:index, :show]

  # Settings
  resource :settings, only: [:show, :update]

  # Billing & Pricing
  get "/pricing", to: "billing#index", as: :pricing



  # Health check
  get "up" => "rails/health#show", as: :rails_health_check

  # Screenshots (for development - in production use S3/CDN)
  get "/screenshots/:filename", to: "screenshots#show", as: :screenshot
end
