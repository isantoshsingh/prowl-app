# frozen_string_literal: true

# Puppeteer configuration for headless browser scanning.
#
# On Heroku, Chrome is installed via heroku-buildpack-chrome-for-testing which
# places `chrome` on PATH (no GOOGLE_CHROME_BIN env var).
#
# Resolution order:
#   1. PUPPETEER_EXECUTABLE_PATH env var (explicit override)
#   2. GOOGLE_CHROME_BIN env var (legacy buildpack compatibility)
#   3. `chrome` found on PATH (heroku-buildpack-chrome-for-testing)
#   4. nil — puppeteer-ruby falls back to its bundled Chromium

Rails.application.config.puppeteer = ActiveSupport::OrderedOptions.new
Rails.application.config.puppeteer.executable_path =
  ENV["PUPPETEER_EXECUTABLE_PATH"].presence ||
  ENV["GOOGLE_CHROME_BIN"].presence ||
  `which chrome 2>/dev/null`.strip.presence
