Rails.application.configure do
  config.cache_classes = true
  config.eager_load = false
  config.active_support.deprecation = :stderr
  config.log_level = (ENV["LOG_LEVEL"] || "debug").to_sym
end
