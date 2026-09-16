source "https://rubygems.org"

ruby "3.3.6"

gem "rails", "~> 8.0.5"

# Asset pipeline — required for stylesheet_link_tag / javascript_importmap_tags
# and to serve Tailwind's compiled CSS output (app/assets/builds).
gem "propshaft"

gem "pg", "~> 1.5"
gem "puma", ">= 5.0"
gem "importmap-rails"
gem "turbo-rails"
gem "stimulus-rails"
gem "tailwindcss-rails"

# Background jobs (hold expiry, notifications) and job-backed Redis client.
gem "sidekiq", "~> 7.0"
gem "redis", "~> 6.0"
# Pinned: sidekiq 7.3.x's scheduler thread calls its internal sleeper's
# `pop` with a positional timeout arg, but connection_pool 3.0+ made `pop`
# keyword-only (`pop(timeout: ...)`) — that mismatch crashes the scheduler
# thread on boot (silently, as a WARN in the log) with
# "ArgumentError: wrong number of arguments (given 1, expected 0)", which
# means delayed jobs (like HoldExpiryJob's 5-minute wait) are enqueued fine
# but NEVER get moved from the schedule into the ready queue. Root cause of
# the "seats never become available after 5 minutes" bug. Sidekiq's own
# Gemfile only requires connection_pool >= 2.3.0, so pinning to the last 2.x
# release resolves it without needing a Sidekiq upgrade.
gem "connection_pool", "~> 2.5"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

group :development, :test do
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"
  gem "rspec-rails", "~> 6.0"
  gem "factory_bot_rails"
  gem "shoulda-matchers"
  gem "faker"
end

group :development do
  gem "web-console"
end

group :test do
  gem "database_cleaner-active_record"
end

gem "bcrypt", "~> 3.1"
