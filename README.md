# Setlist

iOS app that turns concert tickets and social content into bookable travel
bundles via MyRealTrip's partner API. Two entry points, one shared bundle
engine.

## What's here

```
Setlist/
├── SetlistApp.swift          # App entry + tab container
├── Models/
│   └── Models.swift          # TripSource, TravelBundle, options, SwiftData entities
├── Services/
│   ├── AIParsingService.swift  # Anthropic API + vision + web fetch
│   ├── MRTClient.swift         # MyRealTrip partner API (mocked until keys)
│   ├── BundleBuilder.swift     # Orchestrates MRT calls into a bundle
│   └── AppEnvironment.swift    # Service locator reading Info.plist
└── Views/
    ├── HomeView.swift          # Two hero CTAs + trending tours
    ├── ConcertImportView.swift # Ticket photo or text input
    ├── ContentImportView.swift # Paste reel/video URL
    ├── BundleDetailView.swift  # Flights + hotels + activities + book CTA
    ├── WishlistView.swift      # Saved trips (SwiftData)
    └── BookingsView.swift      # Confirmed bookings
```

## Getting it running

1. Create a new Xcode project (iOS App, SwiftUI, Swift, iOS 17+).
2. Drag the `Setlist/` folder contents into the project.
3. Delete the auto-generated `ContentView.swift` and `*App.swift` so ours
   are the only entry points.
4. Add `NSPhotoLibraryUsageDescription` to Info.plist for the ticket
   picker (PhotosUI requires it implicitly on some iOS versions; safer to
   set it).
5. Build and run. Mock data is enabled by default, so both flows work end
   to end without any keys.

See **[USAGE.md](USAGE.md)** for end-to-end walkthrough scenarios,
copy-pastable test inputs, and dummy ticket images you can drag into the
simulator.

## Swapping in real APIs

Both services are gated by `AppEnvironment.useMockData`. Flip it to
`false` once you have:

### Anthropic API key
Add to Info.plist (or an xcconfig that feeds Info.plist):

```
AnthropicAPIKey = sk-ant-...
```

Security note: embedding the key in the binary is fine for personal
testing and TestFlight among friends, but for App Store release, proxy
through your own lightweight backend. A Cloudflare Worker or Vercel
function that forwards to `api.anthropic.com` and signs requests with a
rotating short-lived token takes under an hour.

### MyRealTrip partner key
Sign up at https://partner.myrealtrip.com/welcome/marketing_partner. Once
you have the key:

```
MRTAPIKey = mrt-...
```

Then open `MRTClient.swift` and replace the three `fatalError` stubs with
real calls, using `docs.myrealtrip.com` as the reference. The protocol
and shape of `TravelBundle` should survive unchanged as long as MRT
returns at least these fields per product.

### MRT MCP server
If you want Claude to query MRT products directly (rather than your app
orchestrating the REST client), pass the MCP server URL into
`AIParsingService` and add it to the `tools` array in
`performAnthropicCall` with type `mcp_server`. That lets you collapse
"parse content" and "find matching products" into one round trip, which
is the natural fit for the reel-to-trip flow.

## The commission loop

Every `bookingURL` on `FlightOption`, `HotelOption`, and `ActivityOption`
should carry your partner ID as a query parameter once MRT issues it.
The 7% commission is attributed by that ID when the user completes
payment on MRT's domain.

The `openBooking()` function in `BundleDetailView` currently opens the
first flight's URL. For the real flow, build a single checkout URL that
bundles all selected items, or open them sequentially with a
checklist UI.

## Architecture decisions

**Why two import flows into one bundle?** The K-pop wedge drives early
volume with strong fandom signal and timing urgency. The reel flow is
the general-purpose top of funnel. Both produce the same `TravelBundle`
shape, so the detail/booking/save/wishlist surfaces are written once.

**Why mock everything first?** The whole app compiles and runs today
without any credentials. When MRT docs are finalized, you swap one file
and flip one boolean. No rewiring the UI layer.

**Why SwiftData over Core Data?** Faster iteration, matches the app
target (iOS 17+), and the schema is simple enough that future migration
needs are unlikely.

**Why the `Environment` singleton?** Deliberately minimal. As the app
grows, swap for a proper DI container (Factory, Needle, or plain
protocol injection into the root view).

## Next moves ranked

1. Real MRT API wiring (unblocks revenue).
2. Deep link from iOS share sheet so users can share a reel URL directly
   into the app without opening it first. This is the bread and butter
   of the reel-to-trip flow's virality.
3. Price change alerts via `BGAppRefreshTask` + MRT price endpoints.
4. Shared trip links so couples/friends can vote on a bundle before
   booking. Uses `CKShare` or a simple hosted page.
5. Concert calendar ingestion (Ticketmaster, Interpark) to populate the
   trending section with real tours.
