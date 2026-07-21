require "active_support/core_ext/integer/time"

Rails.application.configure do
  config.cache_classes = true
  config.eager_load = true
  config.consider_all_requests_local = false
  config.log_level = (ENV["LOG_LEVEL"] || "info").to_sym
  config.log_tags = [:request_id]
  config.active_support.deprecation = :silent
end
