require "active_support/core_ext/integer/time"

Rails.application.configure do
  config.enable_reloading = true
  config.eager_load = false
  config.consider_all_requests_local = true
  config.server_timing = true
  config.log_level = (ENV["LOG_LEVEL"] || "info").to_sym
  config.log_tags = [:request_id]
end
