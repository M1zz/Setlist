import Foundation

// Takes a parsed TripSource and fans out to MRT to build a full TravelBundle.

struct BundleBuilder {
    let mrt: MRTClientProtocol

    func buildFromConcert(
        _ concert: ConcertSource,
        originAirport: String = "ICN",
        travelers: Int = 1
    ) async throws -> TravelBundle {
        // Arrive the day before the show, depart the day after.
        let cal = Calendar(identifier: .gregorian)
        let departDate = cal.date(byAdding: .day, value: -1, to: concert.showDate)!
        let returnDate = cal.date(byAdding: .day, value: 1, to: concert.showDate)!

        async let flights = mrt.searchFlights(
            from: originAirport,
            to: airportCode(for: concert.city),
            departDate: departDate,
            returnDate: returnDate,
            passengers: travelers
        )
        async let hotels = mrt.searchHotelsNear(
            city: concert.city,
            latitude: concert.venueLatitude,
            longitude: concert.venueLongitude,
            radiusMeters: 2000,
            checkIn: departDate,
            checkOut: returnDate,
            guests: travelers
        )
        async let activities = mrt.searchActivities(
            city: concert.city,
            date: returnDate
        )

        let (f, h, a) = try await (flights, hotels, activities)
        return TravelBundle(
            id: UUID(),
            source: .concert(concert),
            flights: f,
            hotels: h,
            activities: a,
            suggestedDepartureDate: departDate,
            suggestedReturnDate: returnDate,
            travelerCount: travelers
        )
    }

    func buildFromContent(
        _ content: ContentSource,
        originAirport: String = "ICN",
        travelers: Int = 1
    ) async throws -> TravelBundle {
        // Default placeholder window: 30 days out, 3 nights.
        let cal = Calendar(identifier: .gregorian)
        let depart = cal.date(byAdding: .day, value: 30, to: .now)!
        let ret = cal.date(byAdding: .day, value: 33, to: .now)!

        async let flights = mrt.searchFlights(
            from: originAirport,
            to: airportCode(for: content.detectedCity),
            departDate: depart,
            returnDate: ret,
            passengers: travelers
        )
        let anchorLat = content.detectedLatitude ?? 35.6762
        let anchorLng = content.detectedLongitude ?? 139.6503
        async let hotels = mrt.searchHotelsNear(
            city: content.detectedCity,
            latitude: anchorLat,
            longitude: anchorLng,
            radiusMeters: 3000,
            checkIn: depart,
            checkOut: ret,
            guests: travelers
        )
        async let activities = mrt.searchActivities(
            city: content.detectedCity,
            date: depart
        )

        let (f, h, a) = try await (flights, hotels, activities)
        return TravelBundle(
            id: UUID(),
            source: .content(content),
            flights: f,
            hotels: h,
            activities: a,
            suggestedDepartureDate: depart,
            suggestedReturnDate: ret,
            travelerCount: travelers
        )
    }

    private func airportCode(for city: String) -> String {
        // Minimal lookup. MRT's flight calendar accepts either city or airport
        // codes for common hubs; we pass airport codes here because the
        // fare-query-landing-url endpoint specifically takes airport codes.
        let lookup: [String: String] = [
            "tokyo": "NRT", "osaka": "KIX", "fukuoka": "FUK",
            "yufuin": "OIT", "oita": "OIT", "beppu": "OIT",
            "sapporo": "CTS", "okinawa": "OKA", "nagoya": "NGO",
            "hiroshima": "HIJ", "kyoto": "KIX",
            "bangkok": "BKK", "bali": "DPS", "denpasar": "DPS",
            "phuket": "HKT", "chiang mai": "CNX",
            "singapore": "SIN", "ho chi minh city": "SGN",
            "da nang": "DAD", "hanoi": "HAN", "manila": "MNL",
            "cebu": "CEB", "taipei": "TPE", "kaohsiung": "KHH",
            "london": "LHR", "paris": "CDG", "madrid": "MAD",
            "barcelona": "BCN", "rome": "FCO", "amsterdam": "AMS",
            "berlin": "BER",
            "los angeles": "LAX", "new york": "JFK",
            "las vegas": "LAS", "san francisco": "SFO",
            "honolulu": "HNL", "guam": "GUM",
            "dubai": "DXB", "istanbul": "IST",
            "seoul": "ICN", "jeju": "CJU", "busan": "PUS"
        ]
        return lookup[city.lowercased()] ?? "NRT"
    }
}
