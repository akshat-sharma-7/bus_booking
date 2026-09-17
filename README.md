# Bus Booking

A simplified bus ticket booking system: search trips, select seats, hold them for 5 minutes, and confirm a booking — with the concurrency and idempotency guarantees a real booking flow needs (two people can never hold the same seat, and refreshing the confirmation page never creates a duplicate booking).

## 1. Project Overview

Riders sign up, search for a trip between two cities on a given date — via city dropdowns and Today/Tomorrow/pick-a-date shortcuts, filterable by operator rating, price, bus type, and amenities — select up to 6 seats on a live seat map, and get a **5-minute hold** on them while they complete payment. From the hold screen they can either continue to booking or cancel the hold outright (seats free up immediately either way). Confirming creates one booking covering all selected seats, complete with a PNR; letting the hold expire releases the seats automatically via a background job.

> **Running this locally, the Sidekiq worker is not optional.** Seat holds only ever become available again — after either the 5-minute timeout or nothing — if `bundle exec sidekiq -C config/sidekiq.yml` is actually running alongside `rails server`. This was the exact bug this app shipped with during development (see IMPLEMENTATION_NOTES.md "Hold expiry architecture" for the full root-cause writeup) — the job enqueues fine either way, so a missing worker fails silently rather than with an obvious error.

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

## 3. Architecture

```
Operator ──< Trip ──< Seat
                        ▲
User ──< Hold ──────────┤   (many Holds, one per seat, share hold_group_id)
  │                     │
  └──< Booking ──< BookingSeat ──┘
```

- **Data model.** `Trip` owns its `Seat`s directly (no separate `Bus` model — nothing in
  this app needs to track a physical vehicle across multiple trips). A seat-selection
  request creates one `Hold` row **per seat**, all sharing one `hold_group_id`; confirming
  that group creates exactly one `Booking` with one `BookingSeat` per seat. See
  `IMPLEMENTATION_NOTES.md` for the full reasoning behind each of these choices.

- **Concurrency.** Holding seats locks the requested `Seat` rows with `SELECT ... FOR
  UPDATE`, always acquired in ascending primary-key order regardless of the order the
  client requested them in — this is what prevents a deadlock when two users request an
  overlapping set of seats in different orders. Backing that up at the database level: a
  **partial unique index** (`holds.seat_id WHERE status = 'active'`) makes it physically
  impossible for two active holds to exist on the same seat, independent of whatever the
  application code does.

- **Idempotent booking confirmation.** A **unique index on `bookings.hold_group_id`**
  guarantees at most one booking per hold group. `BookingConfirmationService` checks for an
  existing booking first (the cheap path for a page refresh), and if a concurrent request
  wins the race instead, catches the resulting constraint violation and returns *that*
  booking rather than erroring — every caller sees success and the same booking, and the
  table never gets a second row for the same group.

- **Service objects** (`TripSearchService`, `SeatHoldService`, `BookingConfirmationService`)
  hold the multi-step domain logic (locking order, all-or-nothing rollback, idempotency
  recovery) out of controllers, each with its own service-level RSpec suite.

- **Caching.** Only trip *metadata* (route/schedule/price matching a search) is cached in
  Redis via `Rails.cache`, for 60 seconds. Seat availability counts are **never** cached —
  always computed live from `seats.status` — so a cache hit can never show a seat as
  available when it's actually held or booked. See `IMPLEMENTATION_NOTES.md` "Caching
  Strategy" for why this sidesteps needing explicit cache invalidation entirely.

- **Releasing a hold** (timeout or explicit cancel) always goes through the same
  `HoldRelease` helper from two different entry points: `HoldExpiryJob` →
  `HoldExpiryService` (time-based, scoped to holds actually past `expires_at`) and
  `HoldsController#destroy` → `CancelHoldService` (user-initiated "Cancel Hold", immediate,
  no timer check). Both lock their target Hold rows first, so they — and
  `BookingConfirmationService` — never corrupt each other's work no matter how they
  interleave; see `IMPLEMENTATION_NOTES.md` "Hold expiry architecture".

- **Time zone.** The app runs in `Asia/Kolkata` (`config.time_zone`) since every user,
  route, and price in it is India-based — without this, `Date.current` is UTC by default
  and disagrees with the browser's own "today" for part of each day. Stored timestamps are
  unaffected either way (ActiveRecord always persists UTC internally); this only affects
  which calendar day "today" resolves to for search/seeding.

## API Overview

| Method | Path | Auth required | Purpose |
|---|---|---|---|
| `GET` | `/trips` | no | Search trips (`TripsController#index`) |
| `GET` | `/trips/:id` | no | Trip details + live seat map (`#show`) |
| `POST` | `/trips/:id/holds` | yes | Select 1–6 seats → create a hold group (`HoldsController#create`) |
| `GET` | `/trips/:id/holds/:hold_group_id` | yes | Hold countdown / confirm screen (`#show`) |
| `DELETE` | `/trips/:id/holds/:hold_group_id` | yes | Cancel the hold, releasing its seats immediately (`#destroy`) |
| `POST` | `/bookings` | yes | Confirm a hold group → booking (`BookingsController#create`) |
| `GET` | `/bookings` | yes | My Bookings — the current user's own bookings (`#index`) |
| `GET` | `/bookings/:id` | yes | Ticket-style booking detail — confirmed/cancelled/rescheduled (`#show`) |
| `GET` | `/bookings/:id/reschedule` | yes | Target-trip picker for rescheduling (`#reschedule_form`) |
| `POST` | `/bookings/:id/reschedule` | yes | Reschedule to the chosen trip (`#reschedule`) |
| `POST` | `/bookings/:id/cancel` | yes | Cancel a confirmed booking (`#cancel`) |

A nonexistent or deleted record on any `:id`/`:hold_group_id` route (a deleted Trip, a
booking that isn't yours, ...) redirects to the search page with a flash message instead
of Rails' raw exception page (`ApplicationController` `rescue_from ActiveRecord::RecordNotFound`).

## UI Flow

Login/Signup → Search Trips (From/To city dropdowns, Today/Tomorrow/Select Date, rating,
price, bus type, amenities) → Trip Details (live seat map: available seats are
selectable; a seat someone else is holding shows "Currently Unavailable"; a sold seat
shows "Booked" — select up to 6) → Hold Seats (5-minute countdown, backend-authoritative —
the JS timer is cosmetic only and reloads the page from the server when it hits zero) →
either **Continue to Booking** or **Cancel Hold** (releases the seats immediately, no
waiting for the timer) → Booking Confirmation (PNR, route, timing, seats, total).

From there: **My Bookings** lists every booking the signed-in user has made, each showing
View always, and Reschedule/Cancel only while the booking is still `confirmed`.
**Reschedule** picks a same-route/same-operator trip on a different date; the seat count
carries over, the original booking becomes `rescheduled` and links to its replacement.
**Cancel** is allowed up to exactly 1 hour before departure and shows the ₹50 flat
cancellation fee and calculated refund on the booking page (no payment gateway is
integrated, so nothing is actually charged or paid out — see IMPLEMENTATION_NOTES.md).

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

## 5. Running Tests

```bash
bundle exec rspec
```

79 examples covering trip search (every filter, including Today/Tomorrow/arbitrary-date and recurring-schedule lookups), seat holding (single/multiple/max-6/reject-7/reject-unavailable/reject-cross-trip, all-or-nothing rollback verified), hold expiry (`HoldExpiryService`, idempotent, leaves confirmed/cancelled holds alone), Cancel Hold (ownership, idempotency, doesn't corrupt a confirmed or already-expired hold), booking confirmation (idempotent repeat, wrong-user rejection, expired/cancelled-hold rejection), rescheduling (route/operator/seat-count validation, idempotent, concurrency-safe, full-rollback-on-failure), cancellation (the 1-hour rule at its exact boundary, the ₹50-once-per-booking fee, idempotency, concurrency-safety, rollback), My Bookings/Booking Detail authorization, and missing-record handling. Uses the `test` database configured the same way as `development` (see the env-var note above); `RAILS_ENV=test` forces the `:test` ActiveJob adapter so background jobs run inline instead of touching real Sidekiq/Redis.

Most examples run inside a DatabaseCleaner-managed transaction (fast, isolated). The concurrency specs (two users racing for the same seat, two users confirming the same hold group simultaneously, deadlock-avoidance under reverse-order locking, expiry-vs-confirmation, cancel-vs-expiry) genuinely spawn threads with independent DB connections — those are tagged `truncation: true` and use real commits instead, since a spawned thread's connection can't see another connection's uncommitted transaction. These are not mocked: they exercise the actual `SELECT ... FOR UPDATE` locking and unique-index behavior against Postgres.

## 6. Key Features

- **Auth** — email + password signup/login via Rails 8's built-in `has_secure_password` + database-backed sessions (no Devise).
- **Trip search & filters** — From/To city dropdowns, Today/Tomorrow/Select Date quick-pick, operator rating, price range, bus type, amenities; results show live available-seat counts.
- **Trip details & seat map** — visual seat map (always live DB state), select up to 6 seats client-side (JS-enforced for UX, server-enforced for correctness). A seat someone else is currently holding reads "Currently Unavailable" — the underlying `held` state is never exposed as a word to the rider; a sold seat still reads "Booked".
- **Seat holding with a 5-minute hold** — pessimistic row locking (deterministic lock order) plus a partial unique DB index prevent two riders from ever holding the same seat; a Sidekiq job releases the hold automatically if it isn't confirmed in time.
- **Cancel Hold** — releases a hold (and its seats) immediately, without waiting for the 5-minute timer; safe to click more than once, and safe even if the hold already expired or was already confirmed elsewhere.
- **Idempotent booking confirmation** — refreshing, double-submitting, or two concurrent confirm requests for the same hold group all converge on exactly one booking.
- **Booking confirmation page** — PNR, operator, route, timing, seats, and total, styled as an actual ticket rather than raw JSON.
- **My Bookings** — every booking the signed-in user has made, with the status-appropriate actions (View always; Reschedule/Cancel only while `confirmed`).
- **Reschedule** — move a confirmed booking to a different date/time on the same route and operator, keeping the same seat count; the original booking becomes `rescheduled` and links to its replacement. Concurrency-safe and rollback-safe the same way booking confirmation is.
- **Cancellation** — allowed up to exactly 1 hour before departure; shows the flat ₹50 cancellation fee and the calculated refund (`total_price - ₹50`) on the booking page. No payment gateway is integrated, so this is a calculated figure only — nothing is actually charged or refunded anywhere.
- **Friendly missing-record handling** — a deleted Trip, or a Booking that isn't yours, redirects to the search page with a message instead of showing Rails' raw exception page.
