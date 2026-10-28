import NookKit
import SwiftUI

@main
struct Clock: Nooklet {
    var body: some NookScene {
        FloatingPanel(level: .desktop, position: .topTrailing) {
            ClockFace()
        }
    }
}

struct ClockFace: View {
    var body: some View {
        TimelineView(.everyMinute) { context in
            VStack(alignment: .leading, spacing: 2) {
                Text(context.date, format: .dateTime.hour().minute())
                    .font(.system(size: 56, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(context.date, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }
}
