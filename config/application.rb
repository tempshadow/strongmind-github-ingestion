require_relative "boot"

require "rails"

# API-only: load just the railties this service needs.
require "active_record/railtie"
require "action_controller/railtie"

Bundler.require(*Rails.groups)

module StrongmindGithubIngestion
  class Application < Rails::Application
    config.load_defaults 7.1
    config.api_only = true
    config.generators.system_tests = nil
  end
end
