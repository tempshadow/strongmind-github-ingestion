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
  minimum_coverage 85
end

RSpec.configure do |config|
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!
end
