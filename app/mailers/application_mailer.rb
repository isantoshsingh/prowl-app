# frozen_string_literal: true

class ApplicationMailer < ActionMailer::Base
  default from: "Silent Profit <alerts@silentprofit.app>"
  layout "mailer"
end
