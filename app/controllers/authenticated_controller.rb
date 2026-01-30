# frozen_string_literal: true

class AuthenticatedController < ApplicationController
  include ShopifyApp::EnsureHasSession

  before_action :set_host

  private

  # Set @host for use in views (needed for navigation links)
  def set_host
    @host = params[:host]
  end
end
