#!/usr/bin/env swift
// Renders a few demo concert ticket mockups as PNGs, for Setlist's
// ConcertImportView image-upload flow. Run from the Setlist repo root:
//   swift scripts/gen_tickets.swift
// Outputs go to docs/tickets/*.png.

import AppKit

struct Ticket {
    let fileName: String
    let headline: String
    let artist: String
    let subtitle: String
    let venue: String
    let city: String
    let dateLine: String
    let timeLine: String
    let seatLine: String
    let accent: NSColor
}

let tickets: [Ticket] = [
    .init(
        fileName: "ticket_bts_tokyo.png",
        headline: "WORLD TOUR",
        artist: "BTS",
        subtitle: "ARIRANG TOKYO",
        venue: "Tokyo Dome",
        city: "Tokyo, Japan",
        dateLine: "2026-06-15 (MON)",
        timeLine: "19:00",
        seatLine: "GATE 22 · 1F · A32",
        accent: NSColor(calibratedRed: 0.45, green: 0.21, blue: 0.91, alpha: 1)
    ),
    .init(
        fileName: "ticket_blackpink_gocheok.png",
        headline: "2026 WORLD TOUR",
        artist: "BLACKPINK",
        subtitle: "IN YOUR AREA",
        venue: "고척스카이돔 (Gocheok Sky Dome)",
        city: "Seoul, Korea",
        dateLine: "2026년 7월 3일",
        timeLine: "18:00",
        seatLine: "3층 315블록 A열 12번",
        accent: NSColor(calibratedRed: 0.92, green: 0.31, blue: 0.62, alpha: 1)
    ),
    .init(
        fileName: "ticket_newjeans_osaka.png",
        headline: "FAN MEETING",
        artist: "NewJeans",
        subtitle: "TOKKI PROJECT",
        venue: "Kyocera Dome Osaka",
        city: "Osaka, Japan",
        dateLine: "2026年10月5日",
        timeLine: "18:30",
        seatLine: "アリーナ B2 · 15-08",
        accent: NSColor(calibratedRed: 0.18, green: 0.55, blue: 0.89, alpha: 1)
    ),
    .init(
        fileName: "ticket_strayKids_msg.png",
        headline: "DOMINATE WORLD TOUR",
        artist: "Stray Kids",
        subtitle: "NEW YORK",
        venue: "Madison Square Garden",
        city: "New York, USA",
        dateLine: "2026/08/12",
        timeLine: "20:00",
        seatLine: "SECTION 116 · ROW H · SEAT 5",
        accent: NSColor(calibratedRed: 0.08, green: 0.60, blue: 0.50, alpha: 1)
    )
]

let size = NSSize(width: 1200, height: 720)
let outDir = "docs/tickets"

let fm = FileManager.default
try? fm.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func font(_ name: String, _ weight: NSFont.Weight, _ pointSize: CGFloat) -> NSFont {
    NSFont.systemFont(ofSize: pointSize, weight: weight)
}

for ticket in tickets {
    let image = NSImage(size: size)
    image.lockFocus()

    // Background
    NSColor.white.setFill()
    NSRect(origin: .zero, size: size).fill()

    // Accent side bar
    ticket.accent.setFill()
    NSRect(x: 0, y: 0, width: 140, height: size.height).fill()

    // Faint accent wash top-right
    ticket.accent.withAlphaComponent(0.08).setFill()
    NSRect(x: size.width - 420, y: size.height - 220, width: 420, height: 220).fill()

    // Perforation dashed line
    let dashed = NSBezierPath()
    dashed.move(to: NSPoint(x: 180, y: 180))
    dashed.line(to: NSPoint(x: size.width - 60, y: 180))
    dashed.lineWidth = 2
    let pattern: [CGFloat] = [10, 8]
    dashed.setLineDash(pattern, count: 2, phase: 0)
    NSColor(calibratedWhite: 0.75, alpha: 1).setStroke()
    dashed.stroke()

    // Title small label
    let smallAttrs: [NSAttributedString.Key: Any] = [
        .foregroundColor: ticket.accent,
        .font: font("HelveticaNeue", .semibold, 22),
        .kern: 6.0
    ]
    ticket.headline.uppercased().draw(
        at: NSPoint(x: 180, y: size.height - 100),
        withAttributes: smallAttrs
    )

    // Artist huge
    let artistAttrs: [NSAttributedString.Key: Any] = [
        .foregroundColor: NSColor.black,
        .font: font("HelveticaNeue", .heavy, 96),
        .kern: -1.0
    ]
    ticket.artist.draw(at: NSPoint(x: 175, y: size.height - 240), withAttributes: artistAttrs)

    // Subtitle
    let subAttrs: [NSAttributedString.Key: Any] = [
        .foregroundColor: NSColor(calibratedWhite: 0.30, alpha: 1),
        .font: font("HelveticaNeue", .medium, 30)
    ]
    ticket.subtitle.draw(at: NSPoint(x: 180, y: size.height - 300), withAttributes: subAttrs)

    // Venue label + value
    let labelAttrs: [NSAttributedString.Key: Any] = [
        .foregroundColor: NSColor(calibratedWhite: 0.55, alpha: 1),
        .font: font("HelveticaNeue", .medium, 18),
        .kern: 2.0
    ]
    let valueAttrs: [NSAttributedString.Key: Any] = [
        .foregroundColor: NSColor.black,
        .font: font("HelveticaNeue", .semibold, 34)
    ]

    "VENUE".draw(at: NSPoint(x: 180, y: size.height - 420), withAttributes: labelAttrs)
    ticket.venue.draw(at: NSPoint(x: 180, y: size.height - 462), withAttributes: valueAttrs)

    "CITY".draw(at: NSPoint(x: 180, y: size.height - 530), withAttributes: labelAttrs)
    ticket.city.draw(at: NSPoint(x: 180, y: size.height - 572), withAttributes: valueAttrs)

    // Right column: date/time/seat
    "DATE".draw(at: NSPoint(x: 760, y: size.height - 420), withAttributes: labelAttrs)
    ticket.dateLine.draw(at: NSPoint(x: 760, y: size.height - 462), withAttributes: valueAttrs)

    "TIME".draw(at: NSPoint(x: 760, y: size.height - 530), withAttributes: labelAttrs)
    ticket.timeLine.draw(at: NSPoint(x: 760, y: size.height - 572), withAttributes: valueAttrs)

    // Bottom section (under the perforation)
    "SEAT".draw(at: NSPoint(x: 180, y: 120), withAttributes: labelAttrs)
    ticket.seatLine.draw(
        at: NSPoint(x: 180, y: 80),
        withAttributes: [
            .foregroundColor: NSColor.black,
            .font: font("HelveticaNeue", .semibold, 28)
        ]
    )

    // Fake barcode (stripes)
    NSColor.black.setFill()
    let widths: [CGFloat] = [2, 4, 1, 3, 2, 5, 1, 3, 4, 2, 3, 1, 4, 2, 3, 2, 5, 1, 3, 2, 4, 1, 2, 3]
    var x: CGFloat = 820
    for w in widths {
        NSRect(x: x, y: 70, width: w, height: 80).fill()
        x += w + 3
    }
    "*\(ticket.artist.uppercased())*"
        .draw(
            at: NSPoint(x: 820, y: 40),
            withAttributes: [
                .foregroundColor: NSColor(calibratedWhite: 0.45, alpha: 1),
                .font: font("Menlo", .regular, 14)
            ]
        )

    image.unlockFocus()

    // Save as PNG
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let data = rep.representation(using: .png, properties: [:]) else {
        print("  ! failed to encode \(ticket.fileName)")
        continue
    }
    let url = URL(fileURLWithPath: outDir).appendingPathComponent(ticket.fileName)
    try? data.write(to: url)
    print("  wrote \(ticket.fileName) (\((data.count + 999) / 1000) KB)")
}

print("done.")
