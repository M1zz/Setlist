import Foundation
import SwiftData

// MARK: - What started the trip

enum TripSource: Codable, Hashable {
    case concert(ConcertSource)
    case content(ContentSource)
    case manual
}

struct ConcertSource: Codable, Hashable {
    let artist: String
    let venueName: String
    let venueLatitude: Double
    let venueLongitude: Double
    let city: String
    let country: String
    let showDate: Date
}

struct ContentSource: Codable, Hashable {
    let originalURL: URL
    let detectedPlaceName: String?
    let detectedCity: String
    let detectedCountry: String
    let detectedLatitude: Double?
    let detectedLongitude: Double?
    let caption: String?
}

// MARK: - The bundle itself

struct TravelBundle: Codable, Hashable, Identifiable {
    let id: UUID
    let source: TripSource
    var flights: [FlightOption]
    var hotels: [HotelOption]
    var activities: [ActivityOption]
    var suggestedDepartureDate: Date
    var suggestedReturnDate: Date
    var travelerCount: Int

    var estimatedTotalKRW: Int {
        let flight = flights.first?.priceKRW ?? 0
        let hotelNight = hotels.first?.pricePerNightKRW ?? 0
        let nights = Calendar.current.dateComponents(
            [.day], from: suggestedDepartureDate, to: suggestedReturnDate
        ).day ?? 1
        let activity = activities.first?.priceKRW ?? 0
        return (flight * travelerCount)
            + (hotelNight * max(nights, 1))
            + (activity * travelerCount)
    }
}

struct FlightOption: Codable, Hashable, Identifiable {
    let id: UUID
    let airline: String
    let flightNumber: String
    let fromAirport: String
    let toAirport: String
    let departureTime: Date
    let arrivalTime: Date
    let priceKRW: Int
    let mrtProductID: String
    let bookingURL: URL
}

struct HotelOption: Codable, Hashable, Identifiable {
    let id: UUID
    let name: String
    let address: String
    let latitude: Double
    let longitude: Double
    let distanceMetersFromAnchor: Int
    let starRating: Double
    let userRating: Double
    let pricePerNightKRW: Int
    let freeCancellation: Bool
    let mrtProductID: String
    let bookingURL: URL
    let thumbnailURL: URL?
}

struct ActivityOption: Codable, Hashable, Identifiable {
    let id: UUID
    let title: String
    let durationHours: Double
    let priceKRW: Int
    let rating: Double
    let thumbnailURL: URL?
    let mrtProductID: String
    let bookingURL: URL
}

// MARK: - Persistence

@Model
final class SavedTrip {
    var id: UUID
    var createdAt: Date
    var bundleData: Data
    var title: String
    var note: String?
    var ticketImageData: Data?

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        bundleData: Data,
        title: String,
        note: String? = nil,
        ticketImageData: Data? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.bundleData = bundleData
        self.title = title
        self.note = note
        self.ticketImageData = ticketImageData
    }

    var bundle: TravelBundle? {
        try? JSONDecoder.setlist.decode(TravelBundle.self, from: bundleData)
    }
}

// User-initiated booking attempt. Created the moment the user taps a Book
// CTA, before opening Safari. Reconciled later by matching the local
// `id.uuidString` against `/v1/reservations` response's `utmContent` field.

@Model
final class BookingIntent {
    var id: UUID
    var createdAt: Date
    var resolvedAt: Date?
    var title: String
    var productCategory: String       // "TNA", "HOTEL", "FLIGHT"
    var productGid: String
    var targetURLString: String
    var status: String                // "pending", "confirmed", "expired"
    var reservationNo: String?
    var statusKor: String?
    var actualSalePriceKRW: Int
    var ticketImageData: Data?

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        resolvedAt: Date? = nil,
        title: String,
        productCategory: String,
        productGid: String,
        targetURLString: String,
        status: String = "pending",
        reservationNo: String? = nil,
        statusKor: String? = nil,
        actualSalePriceKRW: Int = 0,
        ticketImageData: Data? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.resolvedAt = resolvedAt
        self.title = title
        self.productCategory = productCategory
        self.productGid = productGid
        self.targetURLString = targetURLString
        self.status = status
        self.reservationNo = reservationNo
        self.statusKor = statusKor
        self.actualSalePriceKRW = actualSalePriceKRW
        self.ticketImageData = ticketImageData
    }

    var isAttributionWindowOpen: Bool {
        // 24h cookie window from MRT. After this, even if user books, no
        // commission is attributed; keep the record but mark expired.
        Date().timeIntervalSince(createdAt) < 86_400
    }
}

@Model
final class BookedTrip {
    var id: UUID
    var bookedAt: Date
    var bundleData: Data
    var title: String
    var bookingReference: String
    var ticketImageData: Data?

    init(
        id: UUID = UUID(),
        bookedAt: Date = .now,
        bundleData: Data,
        title: String,
        bookingReference: String,
        ticketImageData: Data? = nil
    ) {
        self.id = id
        self.bookedAt = bookedAt
        self.bundleData = bundleData
        self.title = title
        self.bookingReference = bookingReference
        self.ticketImageData = ticketImageData
    }

    var bundle: TravelBundle? {
        try? JSONDecoder.setlist.decode(TravelBundle.self, from: bundleData)
    }
}

// MARK: - Coding helpers

extension JSONEncoder {
    static var setlist: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }
}

extension JSONDecoder {
    static var setlist: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
