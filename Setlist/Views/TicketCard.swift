import SwiftUI

// Skeuomorphic ticket card. A rounded rectangle with inward notches on
// both side edges and a dashed tear line across the body, tinted cream
// paper with layered soft shadows.

struct TicketShape: Shape {
    var cornerRadius: CGFloat = 18
    var notchRadius: CGFloat = 9
    var notchPositionFromBottom: CGFloat = 56

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let notchY = rect.height - notchPositionFromBottom

        // Top edge
        path.move(to: CGPoint(x: cornerRadius, y: 0))
        path.addLine(to: CGPoint(x: rect.width - cornerRadius, y: 0))
        path.addArc(
            center: CGPoint(x: rect.width - cornerRadius, y: cornerRadius),
            radius: cornerRadius,
            startAngle: .degrees(-90),
            endAngle: .degrees(0),
            clockwise: false
        )
        // Right edge to notch
        path.addLine(to: CGPoint(x: rect.width, y: notchY - notchRadius))
        path.addArc(
            center: CGPoint(x: rect.width, y: notchY),
            radius: notchRadius,
            startAngle: .degrees(-90),
            endAngle: .degrees(90),
            clockwise: true
        )
        // Right edge continues
        path.addLine(to: CGPoint(x: rect.width, y: rect.height - cornerRadius))
        path.addArc(
            center: CGPoint(x: rect.width - cornerRadius, y: rect.height - cornerRadius),
            radius: cornerRadius,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )
        // Bottom edge
        path.addLine(to: CGPoint(x: cornerRadius, y: rect.height))
        path.addArc(
            center: CGPoint(x: cornerRadius, y: rect.height - cornerRadius),
            radius: cornerRadius,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )
        // Left edge up to notch
        path.addLine(to: CGPoint(x: 0, y: notchY + notchRadius))
        path.addArc(
            center: CGPoint(x: 0, y: notchY),
            radius: notchRadius,
            startAngle: .degrees(90),
            endAngle: .degrees(-90),
            clockwise: true
        )
        // Left edge continues
        path.addLine(to: CGPoint(x: 0, y: cornerRadius))
        path.addArc(
            center: CGPoint(x: cornerRadius, y: cornerRadius),
            radius: cornerRadius,
            startAngle: .degrees(180),
            endAngle: .degrees(270),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

struct TicketCard<Top: View, Bottom: View>: View {
    let accent: Color
    var notchFromBottom: CGFloat = 56
    @ViewBuilder var top: Top
    @ViewBuilder var bottom: Bottom

    var body: some View {
        let shape = TicketShape(notchPositionFromBottom: notchFromBottom)
        ZStack(alignment: .topLeading) {
            // Paper
            shape.fill(paperGradient)
            // Accent strip clipped to ticket outline
            Rectangle()
                .fill(accent)
                .frame(width: 10)
                .clipShape(shape)
                .allowsHitTesting(false)
            // Content
            VStack(alignment: .leading, spacing: 0) {
                top
                    .padding(.leading, 22)
                    .padding(.trailing, 18)
                    .padding(.top, 16)
                    .padding(.bottom, notchFromBottom / 2 + 8)
                    .frame(maxWidth: .infinity, alignment: .leading)

                perforation
                    .padding(.horizontal, 14)

                bottom
                    .padding(.leading, 22)
                    .padding(.trailing, 18)
                    .padding(.top, notchFromBottom / 2 + 2)
                    .padding(.bottom, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .overlay {
            shape.stroke(Color.black.opacity(0.06), lineWidth: 1)
        }
        // Skeuomorphic depth — two layered shadows simulating paper
        .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 4)
        .shadow(color: Color.black.opacity(0.05), radius: 1, x: 0, y: 1)
        .contentShape(shape)
    }

    private var paperGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.995, green: 0.99, blue: 0.98),
                Color(red: 0.955, green: 0.945, blue: 0.93)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var perforation: some View {
        GeometryReader { geo in
            Path { p in
                p.move(to: CGPoint(x: 0, y: 0.5))
                p.addLine(to: CGPoint(x: geo.size.width, y: 0.5))
            }
            .stroke(
                Color.black.opacity(0.18),
                style: StrokeStyle(lineWidth: 1, dash: [4, 4])
            )
        }
        .frame(height: 1)
    }
}

// MARK: - Stub barcode for authenticity

struct TicketBarcode: View {
    let seed: String

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(stripes.enumerated()), id: \.offset) { _, w in
                Rectangle()
                    .fill(Color.black.opacity(0.85))
                    .frame(width: w, height: 26)
            }
        }
    }

    private var stripes: [CGFloat] {
        // Pseudo-random but stable per seed
        var hasher = Hasher()
        hasher.combine(seed)
        let base = abs(hasher.finalize())
        return (0..<20).map { i in
            let v = (base >> (i % 20)) & 0x3
            return CGFloat(v) + 1 // 1..4 pt wide
        }
    }
}
