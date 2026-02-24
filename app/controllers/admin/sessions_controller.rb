# frozen_string_literal: true

class Admin::SessionsController < Devise::SessionsController
  layout "admin_login"

  def create
    self.resource = warden.authenticate!(auth_options)
    Rails.logger.info("[ADMIN_AUTH] Successful login for admin: #{resource.email} from IP: #{request.remote_ip}")
    set_flash_message!(:notice, :signed_in)
    sign_in(resource_name, resource)
    yield resource if block_given?
    respond_with resource, location: after_sign_in_path_for(resource)
  end

  protected

  def after_sign_in_path_for(_resource)
    admin_root_path
  end

  def after_sign_out_path_for(_resource)
    new_admin_session_path
  end

  def auth_options
    { scope: resource_name, recall: "#{controller_path}#new" }
  end
end
