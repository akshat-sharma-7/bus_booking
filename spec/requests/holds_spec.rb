require "rails_helper"

RSpec.describe "Holds", type: :request do
  let(:trip) { create(:trip, seats_count: 5) }
  let(:user) { create(:user) }

  def login(as_user)
    post session_path, params: { email_address: as_user.email_address, password: "Password123!" }
  end

  it 'labels the hold confirmation submit button "Confirm Booking", distinct from the seat-selection step' do
    login(user)
    seat = trip.seats.first
    hold = SeatHoldService.new(trip: trip, user: user, seat_ids: [seat.id]).call

    get trip_hold_path(trip, hold.hold_group_id)

    expect(response.body).to include('value="Confirm Booking"')
  end
end
