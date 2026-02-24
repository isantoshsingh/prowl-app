# frozen_string_literal: true

class Admin::BaseController < ApplicationController
  include Pagy::Backend

  before_action :authenticate_admin!

  layout "admin"

  protect_from_forgery with: :exception
end
