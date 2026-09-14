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
gem "redis", "~> 5.0"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Use the database-backed adapters for Rails.cache and Active Job
gem "solid_cache"
gem "solid_queue"

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
