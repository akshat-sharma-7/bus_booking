require "rails_helper"

RSpec.describe CancelHoldService do
  let(:trip) { create(:trip, seats_count: 10) }
  let(:user) { create(:user) }
  let(:seats) { trip.seats.order(:id).to_a }

  def hold_group_for(hold_user, seat_list)
    SeatHoldService.new(trip: trip, user: hold_user, seat_ids: seat_list.map(&:id)).call.hold_group_id
  end

  it "lets a user cancel their own active hold, releasing the seats immediately" do
    group = hold_group_for(user, seats[0..1])

    result = described_class.new(user: user, hold_group_id: group).call

    expect(result.success?).to be true
    expect(Hold.where(hold_group_id: group).pluck(:status).uniq).to eq(["released"])
    expect(seats[0].reload.status).to eq("available")
    expect(seats[1].reload.status).to eq("available")
  end

  it "lets another user hold the released seats immediately afterward" do
    group = hold_group_for(user, [seats[0]])
    described_class.new(user: user, hold_group_id: group).call

    other_user = create(:user)
    result = SeatHoldService.new(trip: trip, user: other_user, seat_ids: [seats[0].id]).call

    expect(result.success?).to be true
  end

  it "does not let a user cancel another user's hold" do
    group = hold_group_for(user, [seats[0]])
    other_user = create(:user)

    result = described_class.new(user: other_user, hold_group_id: group).call

    expect(result.success?).to be false
    expect(result.error).to match(/not found/i)
    expect(seats[0].reload.status).to eq("held") # unchanged
  end

  it "is idempotent — cancelling twice is safe and stays successful" do
    group = hold_group_for(user, [seats[0]])

    first = described_class.new(user: user, hold_group_id: group).call
    second = described_class.new(user: user, hold_group_id: group).call

    expect(first.success?).to be true
    expect(second.success?).to be true
    expect(Hold.where(hold_group_id: group).pluck(:status).uniq).to eq(["released"])
  end

  it "does not corrupt a hold that has already been confirmed into a booking" do
    group = hold_group_for(user, [seats[0]])
    BookingConfirmationService.new(user: user, hold_group_id: group).call

    result = described_class.new(user: user, hold_group_id: group).call

    expect(result.success?).to be true # no-op success, not an error
    expect(Hold.where(hold_group_id: group).pluck(:status).uniq).to eq(["confirmed"])
    expect(seats[0].reload.status).to eq("booked")
  end

  it "does not corrupt a hold that has already expired" do
    group = hold_group_for(user, [seats[0]])
    Hold.where(hold_group_id: group).update_all(expires_at: 1.minute.ago)
    HoldExpiryService.new(hold_group_id: group).call

    result = described_class.new(user: user, hold_group_id: group).call

    expect(result.success?).to be true
    expect(Hold.where(hold_group_id: group).pluck(:status).uniq).to eq(["expired"])
    expect(seats[0].reload.status).to eq("available")
  end
end
