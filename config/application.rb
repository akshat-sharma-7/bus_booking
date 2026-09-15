require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
# require "active_storage/engine"
require "action_controller/railtie"
# require "action_mailer/railtie"
# require "action_mailbox/engine"
# require "action_text/engine"
require "action_view/railtie"
# require "action_cable/engine"
require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module BusBooking
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.0

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Sidekiq/Redis-backed by default in every environment except test,
    # which overrides to :test in config/environments/test.rb so specs
    # run jobs inline instead of touching Redis.
    config.active_job.queue_adapter = :sidekiq

    # RSpec (not Minitest) is this app's test framework; skip fixtures
    # in favor of FactoryBot factories under spec/factories.
    config.generators do |g|
      g.test_framework :rspec, fixtures: false
      g.fixture_replacement :factory_bot, dir: "spec/factories"
    end

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # All routes/prices/operators in this app are India-based (₹, Indian
    # cities). Without this, Rails defaults Time.zone to UTC while real users
    # and the browser's own "today" are IST (UTC+5:30) — for roughly 5.5
    # hours every day (whenever IST has already crossed midnight but UTC
    # hasn't), the server's Date.current is a day behind the browser's, so
    # the "Today"/"Tomorrow" quick-pick buttons on the search page disagree
    # with what the server actually searches for. Stored timestamps are
    # unaffected (ActiveRecord always persists UTC internally regardless of
    # this setting) — this only fixes which calendar day "today" resolves to.
    config.time_zone = "Asia/Kolkata"
    # config.eager_load_paths << Rails.root.join("extras")
  end
end
