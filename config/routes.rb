Rails.application.routes.draw do
  get "/health", to: "health#check"
end
