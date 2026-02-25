# frozen_string_literal: true

Rails.application.routes.draw do
  # Webhook handlers (must be before ShopifyApp::Engine)
  post '/webhooks/app_uninstalled', to: 'webhooks/app_uninstalled#create'
  post '/webhooks/shop_update', to: 'webhooks/shop_update#create'
  post '/webhooks/customers_data_request', to: 'webhooks/compliance#customers_data_request'
  post '/webhooks/customers_redact', to: 'webhooks/compliance#customers_redact'
  post '/webhooks/shop_redact', to: 'webhooks/compliance#shop_redact'

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
      get  :status
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



  # Privacy Policy (public, no auth required)
  get "/privacy", to: "privacy#show", as: :privacy

  # Health check
  get "up" => "rails/health#show", as: :rails_health_check

  # Screenshots — proxied from R2 (production) or local tmp/ (development)
  # Path matches R2 key: /screenshots/shop-slug/product-handle/scan_123_xxx.png
  get "/screenshots/*path", to: "screenshots#show", as: :screenshot
end
