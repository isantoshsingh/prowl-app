# frozen_string_literal: true

class ApplicationMailer < ActionMailer::Base
  default from: "Prowl <alerts@prowlapp.com>"
  layout "mailer"
end
