# frozen_string_literal: true

Rails.application.routes.draw do
  # Shopify App Engine (OAuth, webhooks, etc.)
  mount ShopifyApp::Engine, at: "/"

  # Root - Dashboard (App Home Page)
  root to: "home#index"

  # Dashboard API
  get "/dashboard/stats", to: "dashboard#stats"

  # Product Pages (monitored PDPs)
  resources :product_pages, only: [:index, :show, :new, :create, :destroy] do
    member do
      post :rescan
    end
  end

  # Issues
  resources :issues, only: [:index, :show] do
    member do
      post :acknowledge
    end
  end

  # Scans
  resources :scans, only: [:index, :show]

  # Settings
  resource :settings, only: [:show, :update]

  # Billing
  get "/billing/create", to: "billing#create", as: :create_billing
  get "/billing/callback", to: "billing#callback", as: :billing_callback

  # Health check
  get "up" => "rails/health#show", as: :rails_health_check

  # Screenshots (for development - in production use S3/CDN)
  get "/screenshots/:filename", to: "screenshots#show", as: :screenshot
end
