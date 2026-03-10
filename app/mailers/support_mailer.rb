# frozen_string_literal: true

class SupportMailer < ApplicationMailer
  def contact_request(name:, email:, store_url:, subject:, message:)
    @name = name
    @email = email
    @store_url = store_url
    @subject = subject
    @message = message

    mail(
      to: "prowl@lucyapps.com",
      reply_to: email,
      subject: "[Prowl Support] #{subject}"
    )
  end
end
