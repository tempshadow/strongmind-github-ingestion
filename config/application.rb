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

    # Logs go to stdout unbuffered so `docker compose logs -f` is the operator's single pane.
    unless Rails.env.test?
      $stdout.sync = true
      logger = ActiveSupport::Logger.new($stdout)
      logger.formatter = proc { |severity, time, _progname, message|
        "#{time.utc.iso8601} #{severity} #{message}\n"
      }
      config.logger = ActiveSupport::TaggedLogging.new(logger)
    end
    config.generators.system_tests = nil
  end
end
