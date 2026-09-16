require "rails_helper"

RSpec.describe SeatHoldService do
  let(:trip) { create(:trip, seats_count: 10) }
  let(:user) { create(:user) }
  let(:seats) { trip.seats.order(:id).to_a }

  it "holds a single seat" do
    result = described_class.new(trip: trip, user: user, seat_ids: [seats[0].id]).call

    expect(result.success?).to be true
    expect(result.holds.size).to eq(1)
    expect(seats[0].reload.status).to eq("held")
  end

  it "holds multiple seats under one shared hold_group_id" do
    result = described_class.new(trip: trip, user: user, seat_ids: seats[0..2].map(&:id)).call

    expect(result.success?).to be true
    expect(result.holds.size).to eq(3)
    expect(result.holds.map(&:hold_group_id).uniq).to eq([result.hold_group_id])
  end

  it "allows exactly the maximum of 6 seats" do
    result = described_class.new(trip: trip, user: user, seat_ids: seats[0..5].map(&:id)).call

    expect(result.success?).to be true
    expect(result.holds.size).to eq(6)
  end

  it "rejects 7 seats" do
    result = described_class.new(trip: trip, user: user, seat_ids: seats[0..6].map(&:id)).call

    expect(result.success?).to be false
    expect(result.error).to match(/at most 6/)
    expect(Hold.count).to eq(0)
  end

  it "rejects the whole request (all-or-nothing) when one requested seat is already unavailable" do
    seats[1].update!(status: :booked)

    result = described_class.new(trip: trip, user: user, seat_ids: [seats[0].id, seats[1].id, seats[2].id]).call

    expect(result.success?).to be false
    expect(result.error).to match(/no longer available/)
    expect(seats[0].reload.status).to eq("available")
    expect(seats[2].reload.status).to eq("available")
    expect(Hold.count).to eq(0)
  end

  it "rejects seats that belong to a different trip" do
    other_trip_seat = create(:trip, seats_count: 1).seats.first

    result = described_class.new(trip: trip, user: user, seat_ids: [seats[0].id, other_trip_seat.id]).call

    expect(result.success?).to be false
    expect(result.error).to match(/could not be found for this trip/)
    expect(Hold.count).to eq(0)
  end

  it "enqueues a HoldExpiryJob for the hold group after committing" do
    result = nil
    expect {
      result = described_class.new(trip: trip, user: user, seat_ids: [seats[0].id]).call
    }.to have_enqueued_job(HoldExpiryJob)

    expect(result.success?).to be true
  end

  it "two users racing for the same seat: exactly one succeeds", truncation: true do
    seat = seats[0]
    user_a = create(:user)
    user_b = create(:user)
    results = Array.new(2)
    ready = 0
    mutex = Mutex.new
    cv = ConditionVariable.new
    start_latch = Queue.new

    threads = [user_a, user_b].each_with_index.map do |racing_user, i|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          mutex.synchronize { ready += 1; cv.signal }
          start_latch.pop
          results[i] = described_class.new(trip: trip, user: racing_user, seat_ids: [seat.id]).call
        end
      end
    end

    mutex.synchronize { cv.wait(mutex) until ready == 2 }
    2.times { start_latch << :go }
    threads.each { |t| t.join(10) }

    expect(results.count { |r| r.success? }).to eq(1)
    expect(Hold.where(seat_id: seat.id, status: :active).count).to eq(1)
  end

  it "requesting the same 3 seats in reverse order concurrently does not deadlock", truncation: true do
    three_seats = seats[0..2]
    user_a = create(:user)
    user_b = create(:user)
    results = Array.new(2)
    ready = 0
    mutex = Mutex.new
    cv = ConditionVariable.new
    start_latch = Queue.new

    # User A requests [seat1, seat2, seat3]; User B requests the SAME seats
    # in reverse — the exact pattern that deadlocks without deterministic
    # (id-ascending) lock ordering.
    threads = [
      [user_a, three_seats.map(&:id)],
      [user_b, three_seats.map(&:id).reverse]
    ].each_with_index.map do |(racing_user, ids), i|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          mutex.synchronize { ready += 1; cv.signal }
          start_latch.pop
          results[i] = described_class.new(trip: trip, user: racing_user, seat_ids: ids).call
        end
      end
    end

    mutex.synchronize { cv.wait(mutex) until ready == 2 }
    2.times { start_latch << :go }
    completed = threads.map { |t| t.join(10) }.all? { |t| !t.nil? }

    expect(completed).to be true # false would mean a thread hung — i.e. a deadlock
    expect(results.count { |r| r.success? }).to eq(1)
  end
end
