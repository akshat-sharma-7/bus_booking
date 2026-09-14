# Bus Booking

A simplified bus ticket booking system: search trips, hold a seat, confirm a booking, and cancel or reschedule it — with the concurrency and idempotency guarantees a real booking flow needs (no two people can hold the same seat, and refreshing the confirmation page never creates a duplicate booking).

## 1. Project Overview

Riders sign up, search for a trip between two cities on a given date (filterable by operator rating, price, bus type, and amenities), pick a seat, and get a **5-minute hold** on it while they complete payment. Confirming the hold creates a booking; letting the hold expire releases the seat automatically via a background job. Bookings can be cancelled or rescheduled up to 1 hour before departure, with a flat ₹50 cancellation fee deducted from the refund.

## 2. Tech Stack

| Layer | Choice |
|---|---|
| Language | Ruby 3.3.6 |
| Framework | Rails 8.0.5 |
| Database | PostgreSQL 16 |
| Cache / job queue backend | Redis 7 |
| Background jobs | Sidekiq |
| Auth | Rails 8 built-in `has_secure_password` generator |
| Frontend | Turbo + Stimulus + Tailwind CSS (no SPA framework) |
| Tests | RSpec, FactoryBot, Shoulda Matchers, DatabaseCleaner, Faker |

## 3. Architecture Decisions

*(Placeholders below — filled in with real detail as each feature is built in later steps.)*

- **Pessimistic locking** (`Seat.lock.find(id)`) at the application level prevents two concurrent requests from both reading a seat as "available" and both proceeding to hold it — the second request blocks until the first transaction commits or rolls back, then re-reads the now-updated state.
- **Idempotent booking confirmation** via `find_or_create_by!(hold_id: hold.id)` plus a unique index on `bookings.hold_id`: a page refresh or double-click on "Confirm" re-runs the same request, finds the booking that already exists for that hold, and returns it instead of inserting a second row.
- **Service objects** for multi-step domain operations (creating a hold, confirming a booking, cancelling with a fee) keep that logic out of controllers and models, and give each operation one obvious place to unit test.
- **Cache invalidation** is explicit and event-driven (seat held, booking confirmed, booking cancelled, hold expired all bust the relevant trip-search cache key) rather than time-based-only, so search results never show a seat as available when it's actually held.

## 4. Local Setup

### macOS

```bash
brew install rbenv ruby-build postgresql@16 redis
rbenv install 3.3.6
rbenv global 3.3.6
brew services start postgresql@16
brew services start redis

git clone <repo-url> && cd bus_booking
gem install bundler
bundle install

bin/rails db:create db:migrate db:seed
bin/rails tailwindcss:build   # first-time only; bin/dev keeps it live afterward

bundle exec sidekiq -C config/sidekiq.yml   # separate terminal
bin/rails server                             # or: bin/dev (runs web+worker+css together)
```

### Linux

```bash
curl -fsSL https://github.com/rbenv/rbenv-installer/raw/HEAD/bin/rbenv-installer | bash
rbenv install 3.3.6
rbenv global 3.3.6

sudo apt-get install postgresql redis-server libpq-dev
sudo systemctl start postgresql redis-server

git clone <repo-url> && cd bus_booking
gem install bundler
bundle install

bin/rails db:create db:migrate db:seed
bin/rails tailwindcss:build

bundle exec sidekiq -C config/sidekiq.yml   # separate terminal
bin/rails server                             # or: bin/dev
```

> **Note on `config/database.yml`:** it connects via environment variables (`DB_HOST`, `DB_PORT`, `DB_USERNAME`, `DB_PASSWORD`). Leave them **unset** for local development — the `pg` gem then connects over the Postgres unix socket using your OS user's role, which needs no password on a typical local install. If your local Postgres requires a specific role/password, export those four variables before running any `rails db:*` / `rails server` command.

App runs at **http://localhost:3000**. Redis is expected at `redis://localhost:6379` (DB 0 for Sidekiq, DB 1 for the cache — see `REDIS_URL` / `REDIS_CACHE_URL` if you need to point elsewhere).

## 5. Docker Setup (for evaluators)

`docker-compose.yml` starts **Postgres and Redis only** (on offset ports `5433`/`6380` so they don't collide with anything already running locally) — the Rails app itself still runs on your host machine, connecting into those containers.

**Prerequisites:** Docker Desktop (or Docker Engine + Compose) installed. Ruby 3.3.6 and Bundler still need to be installed locally, same as the Local Setup section above — Docker here replaces only the database and cache services.

```bash
docker compose up -d          # starts postgres:5433, redis:6380

bundle install

export DB_HOST=localhost DB_PORT=5433 DB_USERNAME=bus_booking DB_PASSWORD=password
export REDIS_URL=redis://localhost:6380/0
export REDIS_CACHE_URL=redis://localhost:6380/1

bin/rails db:create db:migrate db:seed

bundle exec sidekiq -C config/sidekiq.yml   # separate terminal, same exports in scope
bin/rails server                             # or: bin/dev
```

Those `export` lines only need to be set in whichever shell(s) you run `rails`/`sidekiq` commands from — `config/database.yml` and the Sidekiq/cache initializers pick them up automatically; no file needs editing.

```bash
docker compose down           # stop the containers
docker compose down -v        # stop and also wipe the postgres volume
```

## 6. Running Tests

```bash
bundle exec rspec
```

Uses the `test` database configured the same way as `development` (see the env-var note above); RSpec runs each example in a DatabaseCleaner-managed transaction, and `RAILS_ENV=test` forces the `:test` ActiveJob adapter so background jobs run inline instead of touching real Sidekiq/Redis.

## 7. Key Features

- **Auth** — email + password signup/login via Rails 8's built-in `has_secure_password` + database-backed sessions (no Devise).
- **Trip search & filters** — city pair, date, operator rating, price range, bus type, amenities.
- **Seat selection with a 5-minute hold** — pessimistic row locking prevents two riders from holding the same seat; a Sidekiq job releases the hold automatically if it isn't confirmed in time.
- **Idempotent booking confirmation** — refreshing or double-submitting the confirmation page is a no-op past the first successful booking.
- **Reschedule & cancellation** — allowed up to 1 hour before departure; cancellation refunds the fare minus a flat ₹50 fee.
