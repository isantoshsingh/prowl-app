# frozen_string_literal: true

class SupportController < ApplicationController
  layout "support"

  ARTICLES = {
    "getting-started" => {
      title: "Getting started with Prowl",
      category: "Setup"
    },
    "adding-product-pages" => {
      title: "Adding product pages to monitor",
      category: "Setup"
    },
    "understanding-scan-results" => {
      title: "Understanding scan results",
      category: "Monitoring"
    },
    "alerts-and-notifications" => {
      title: "Alerts and notifications",
      category: "Monitoring"
    },
    "issue-types" => {
      title: "Issue types Prowl detects",
      category: "Monitoring"
    },
    "managing-your-subscription" => {
      title: "Billing and subscription",
      category: "Account"
    }
  }.freeze

  def index
  end

  def faq
  end

  def contact
  end

  def submit_contact
    name = params[:name].to_s.strip
    email = params[:email].to_s.strip
    store_url = params[:store_url].to_s.strip
    subject = params[:subject].to_s.strip
    message = params[:message].to_s.strip

    if name.blank? || email.blank? || subject.blank? || message.blank?
      flash[:alert] = "Please fill in all required fields."
      render :contact, status: :unprocessable_entity
      return
    end

    SupportMailer.contact_request(
      name: name,
      email: email,
      store_url: store_url,
      subject: subject,
      message: message
    ).deliver_later

    redirect_to support_contact_path, notice: "Your message has been sent. We'll get back to you within 24 hours."
  end

  def show
    @slug = params[:article]
    @article = ARTICLES[@slug]

    unless @article && lookup_context.exists?("support/articles/#{@slug}", [], true)
      raise ActionController::RoutingError, "Not Found"
    end
  end
end
