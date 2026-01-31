# frozen_string_literal: true

# ScreenshotsController serves scan screenshots from local storage.
# In production, screenshots would be served from S3/CDN with signed URLs.
#
class ScreenshotsController < ApplicationController
  def show
    filename = params[:filename]
    filepath = Rails.root.join("tmp", "screenshots", filename)

    if File.exist?(filepath)
      send_file filepath, type: "image/png", disposition: "inline"
    else
      head :not_found
    end
  end
end
