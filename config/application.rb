require_relative "boot"

require "rails/all"

# Only load ActiveRecord, ActionController and middleware we need
%w[
  active_record
  action_controller/railtie
  rails/test_unit/railtie
].each do |railtie|
  require railtie
end

Bundler.require(*Rails.groups)

module StrongmindGithubIngestion
  class Application < Rails::Application
    config.load_defaults 7.1
    config.api_only = true
    config.generators.system_tests = nil
  end
end
