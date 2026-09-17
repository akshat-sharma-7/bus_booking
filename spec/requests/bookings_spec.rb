require "rails_helper"

RSpec.describe "Bookings", type: :request do
  let(:operator) { create(:operator, rating: 4.0) }
  let(:user) { create(:user) }

  def login(as_user)
    post session_path, params: { email_address: as_user.email_address, password: "Password123!" }
  end

  def confirm_booking(booking_user, trip, seat_count)
    seats = trip.seats.order(:id).limit(seat_count)
    hold = SeatHoldService.new(trip: trip, user: booking_user, seat_ids: seats.map(&:id)).call
    raise "hold setup failed: #{hold.error}" unless hold.success?

    result = BookingConfirmationService.new(user: booking_user, hold_group_id: hold.hold_group_id).call
    raise "confirm setup failed: #{result.error}" unless result.success?

    result.booking
  end

  describe "GET /bookings (My Bookings)" do
    it "shows the authenticated user's own bookings" do
      trip = create(:trip, operator: operator, seats_count: 5)
      booking = confirm_booking(user, trip, 1)
      login(user)

      get bookings_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(booking.pnr)
    end

    it "never shows another user's bookings" do
      trip = create(:trip, operator: operator, seats_count: 5)
      other_user = create(:user)
      other_booking = confirm_booking(other_user, trip, 1)
      login(user)

      get bookings_path

      expect(response.body).not_to include(other_booking.pnr)
    end

    it "redirects an unauthenticated visitor to sign in" do
      get bookings_path

      expect(response).to redirect_to(new_session_path)
    end
  end

  describe "GET /bookings/:id (Booking Detail)" do
    it "lets the owner view their booking" do
      trip = create(:trip, operator: operator, seats_count: 5)
      booking = confirm_booking(user, trip, 1)
      login(user)

      get booking_path(booking)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(booking.pnr)
    end

    it "does not let another user access it (handled gracefully, not a raw exception)" do
      trip = create(:trip, operator: operator, seats_count: 5)
      booking = confirm_booking(user, trip, 1)
      other_user = create(:user)
      login(other_user)

      get booking_path(booking)

      expect(response).to redirect_to(root_path)
      follow_redirect!
      expect(response.body).to include("no longer available")
    end
  end

  describe "reschedule UI/request integration" do
    it "shows a picker of valid same-route/same-operator target trips" do
      trip = create(:trip, operator: operator, from_city: "Pune", to_city: "Mumbai", seats_count: 5)
      target = create(:trip, operator: operator, from_city: "Pune", to_city: "Mumbai",
                              travel_date: 3.days.from_now.to_date, departure_time: 3.days.from_now.change(hour: 9),
                              arrival_time: 3.days.from_now.change(hour: 13), seats_count: 5)
      booking = confirm_booking(user, trip, 1)
      login(user)

      get reschedule_booking_path(booking)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(target.travel_date.strftime("%d %b %Y"))
    end

    it "successfully reschedules and shows the replacement booking" do
      trip = create(:trip, operator: operator, from_city: "Pune", to_city: "Mumbai", seats_count: 5)
      target = create(:trip, operator: operator, from_city: "Pune", to_city: "Mumbai",
                              travel_date: 3.days.from_now.to_date, departure_time: 3.days.from_now.change(hour: 9),
                              arrival_time: 3.days.from_now.change(hour: 13), seats_count: 5)
      booking = confirm_booking(user, trip, 1)
      login(user)

      post reschedule_booking_path(booking), params: { trip_id: target.id }

      replacement = Booking.find_by(trip: target, user: user)
      expect(replacement).to be_present
      expect(response).to redirect_to(booking_path(replacement))
      expect(booking.reload.status).to eq("rescheduled")
    end

    it "rejects an invalid target trip and leaves the original untouched" do
      trip = create(:trip, operator: operator, from_city: "Pune", to_city: "Mumbai", seats_count: 5)
      wrong_route = create(:trip, operator: operator, from_city: "Delhi", to_city: "Jaipur", seats_count: 5)
      booking = confirm_booking(user, trip, 1)
      login(user)

      post reschedule_booking_path(booking), params: { trip_id: wrong_route.id }

      expect(response).to redirect_to(reschedule_booking_path(booking))
      follow_redirect!
      expect(response.body).to include("same route")
      expect(booking.reload.status).to eq("confirmed")
    end

    describe "fare difference disclosure on the target-trip picker" do
      it "shows 'No fare difference' when the target trip costs the same" do
        trip = create(:trip, operator: operator, from_city: "Pune", to_city: "Mumbai", price: 500, seats_count: 5)
        create(:trip, operator: operator, from_city: "Pune", to_city: "Mumbai", price: 500,
                      travel_date: 3.days.from_now.to_date, departure_time: 3.days.from_now.change(hour: 9),
                      arrival_time: 3.days.from_now.change(hour: 13), seats_count: 5)
        booking = confirm_booking(user, trip, 1)
        login(user)

        get reschedule_booking_path(booking)

        expect(response.body).to include("No fare difference")
      end

      it "warns that the difference is not refunded when the target trip is cheaper" do
        trip = create(:trip, operator: operator, from_city: "Pune", to_city: "Mumbai", price: 500, seats_count: 5)
        create(:trip, operator: operator, from_city: "Pune", to_city: "Mumbai", price: 450,
                      travel_date: 3.days.from_now.to_date, departure_time: 3.days.from_now.change(hour: 9),
                      arrival_time: 3.days.from_now.change(hour: 13), seats_count: 5)
        booking = confirm_booking(user, trip, 1) # total = 500
        login(user)

        get reschedule_booking_path(booking)

        expect(response.body).to include("50")
        expect(response.body).to include("will not be refunded")
      end

      it "warns that additional payment is required when the target trip is more expensive" do
        trip = create(:trip, operator: operator, from_city: "Pune", to_city: "Mumbai", price: 500, seats_count: 5)
        create(:trip, operator: operator, from_city: "Pune", to_city: "Mumbai", price: 700,
                      travel_date: 3.days.from_now.to_date, departure_time: 3.days.from_now.change(hour: 9),
                      arrival_time: 3.days.from_now.change(hour: 13), seats_count: 5)
        booking = confirm_booking(user, trip, 1) # total = 500

        login(user)

        get reschedule_booking_path(booking)

        expect(response.body).to include("200")
        expect(response.body).to include("pay")
        expect(response.body).to include("outside the scope")
      end
    end
  end

  describe "cancellation via HTTP" do
    it "cancels a confirmed booking and shows the fee/refund" do
      trip = create(:trip, operator: operator, departure_time: 2.hours.from_now,
                            arrival_time: 6.hours.from_now, price: 500, seats_count: 5)
      booking = confirm_booking(user, trip, 2)
      login(user)

      post cancel_booking_path(booking)

      expect(response).to redirect_to(booking_path(booking))
      follow_redirect!
      expect(response.body).to include("Cancelled")
      expect(response.body).to include("950") # (500*2) - 50
      expect(booking.reload.status).to eq("cancelled")
    end
  end

  describe "GET /trips/:id for a nonexistent trip" do
    it "shows a normal handled response, not the Rails exception page" do
      get trip_path(id: 999_999)

      expect(response).to redirect_to(root_path)
      follow_redirect!
      expect(response.body).to include("no longer available")
    end
  end
end
