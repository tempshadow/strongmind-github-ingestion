require "spec_helper"
ENV["RAILS_ENV"] ||= "test"

require File.expand_path("../config/environment", __dir__)

require "rspec/rails"
require "webmock/rspec"
require "simplecov"

WebMock.disable_net_connect!(allow_localhost: true)

SimpleCov.start do
  add_filter "/spec/"
  add_filter "/config/"
  add_filter "/db/"
  add_group "Services", "app/services"
  minimum_coverage line: 85
end

# SimpleCov has no built-in per-group floor, so enforce the 95% app/services
# requirement here before the overall check runs.
SimpleCov.at_exit do
  SimpleCov.result.format!
  services = SimpleCov.result.groups["Services"]
  if services && services.covered_percent < 95
    warn "app/services line coverage #{services.covered_percent.round(2)}% is below the required 95%"
    Kernel.exit(1)
  end
end

RSpec.configure do |config|
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!
end
