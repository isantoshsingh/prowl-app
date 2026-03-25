# frozen_string_literal: true

# Log failed admin authentication attempts
Warden::Manager.before_failure do |env, opts|
  if opts[:scope] == :admin
    email = env["action_dispatch.request.request_parameters"]&.dig("admin", "email") || "unknown"
    ip = env["action_dispatch.remote_ip"]&.to_s || env["REMOTE_ADDR"] || "unknown"
    Rails.logger.warn("[ADMIN_AUTH] Failed login attempt for email: #{email} from IP: #{ip}")
  end
end
