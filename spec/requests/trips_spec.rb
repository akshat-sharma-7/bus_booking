require "rails_helper"

RSpec.describe "Trips", type: :request do
  describe "GET /trips" do
    it "includes the popular cities in the From/To dropdowns" do
      get trips_path

      expect(response.body).to include("Indore")
      expect(response.body).to include("Ujjain")
    end

    it "offers Today / Tomorrow / Select Date quick-pick controls" do
      get trips_path

      expect(response.body).to include("Today")
      expect(response.body).to include("Tomorrow")
      expect(response.body).to include("Select Date")
    end

    it "still supports the full set of existing filters" do
      get trips_path, params: { from_city: "Pune", to_city: "Mumbai", min_rating: "4.0",
                                 price_min: "100", price_max: "2000", bus_type: "ac_seater",
                                 amenities: ["wifi"] }

      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /trips/:id seat map wording" do
    let(:trip) { create(:trip, seats_count: 3) }
    let(:available_seat) { trip.seats[0] }
    let(:held_seat) { trip.seats[1] }
    let(:booked_seat) { trip.seats[2] }

    before do
      held_seat.update!(status: :held)
      booked_seat.update!(status: :booked)
    end

    it 'shows a held seat as "Currently Unavailable" and never exposes the word "Held"' do
      get trip_path(trip)

      expect(response.body).not_to match(/\bHeld\b/)
      expect(response.body).to include("Currently Unavailable").or include("Currently unavailable")
    end

    it 'keeps the existing "Booked" wording for booked seats' do
      get trip_path(trip)

      expect(response.body).to include("Booked")
    end

    it "renders the available seat as a selectable checkbox, not a disabled cell" do
      get trip_path(trip)

      expect(response.body).to include(%(id="seat_#{available_seat.id}"))
      expect(response.body).not_to include(%(id="seat_#{held_seat.id}"))
      expect(response.body).not_to include(%(id="seat_#{booked_seat.id}"))
    end
  end
end
