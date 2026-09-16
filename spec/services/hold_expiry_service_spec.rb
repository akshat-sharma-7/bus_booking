require "rails_helper"

RSpec.describe HoldExpiryService do
  let(:trip) { create(:trip, seats_count: 5) }
  let(:user) { create(:user) }
  let(:seat) { trip.seats.first }

  it "expires an active hold that is past its expires_at and frees the seat" do
    hold = create(:hold, user: user, trip: trip, seat: seat, status: :active, expires_at: 1.minute.ago)
    seat.update!(status: :held)

    described_class.new(hold_group_id: hold.hold_group_id).call

    expect(hold.reload.status).to eq("expired")
    expect(seat.reload.status).to eq("available")
  end

  it "leaves a hold alone if it has not reached expires_at yet" do
    hold = create(:hold, user: user, trip: trip, seat: seat, status: :active, expires_at: 4.minutes.from_now)
    seat.update!(status: :held)

    described_class.new(hold_group_id: hold.hold_group_id).call

    expect(hold.reload.status).to eq("active")
    expect(seat.reload.status).to eq("held")
  end

  it "is safe to run twice (idempotent, as Sidekiq's at-least-once delivery can redeliver)" do
    hold = create(:hold, user: user, trip: trip, seat: seat, status: :active, expires_at: 1.minute.ago)
    seat.update!(status: :held)

    described_class.new(hold_group_id: hold.hold_group_id).call
    expect { described_class.new(hold_group_id: hold.hold_group_id).call }.not_to raise_error

    expect(hold.reload.status).to eq("expired")
  end

  it "does not touch a hold that has already been confirmed into a booking" do
    hold = create(:hold, user: user, trip: trip, seat: seat, status: :confirmed, expires_at: 1.minute.ago)
    seat.update!(status: :booked)

    described_class.new(hold_group_id: hold.hold_group_id).call

    expect(hold.reload.status).to eq("confirmed")
    expect(seat.reload.status).to eq("booked")
  end

  it "does not touch a hold that was already cancelled" do
    hold = create(:hold, user: user, trip: trip, seat: seat, status: :released, expires_at: 1.minute.ago)
    seat.update!(status: :available)

    described_class.new(hold_group_id: hold.hold_group_id).call

    expect(hold.reload.status).to eq("released")
  end
end
