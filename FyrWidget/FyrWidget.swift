import WidgetKit
import SwiftUI

/// Background gradient for widget that fills edge-to-edge
struct WidgetBackgroundGradient: View {
    let isOn: Bool
    let isConnected: Bool

    // Widget design colors (matching app's FyrDesign)
    private let warmBackground = Color(red: 0.15, green: 0.08, blue: 0.05)
    private let coolBackground = Color(red: 0.05, green: 0.08, blue: 0.15)

    var body: some View {
        LinearGradient(
            colors: backgroundColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var backgroundColors: [Color] {
        if !isConnected {
            return [coolBackground, coolBackground.opacity(0.9)]
        }
        return isOn
            ? [warmBackground, warmBackground.opacity(0.9)]
            : [coolBackground, coolBackground.opacity(0.9)]
    }
}

/// Fireplace status widget
struct FyrWidget: Widget {
    let kind: String = FyrAppGroup.widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FireplaceTimelineProvider()) { entry in
            FyrWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    // Use dynamic gradient based on fireplace state
                    WidgetBackgroundGradient(isOn: entry.isOn, isConnected: entry.isConnected)
                }
        }
        .configurationDisplayName("Fireplace Status")
        .description("Monitor your DRU fireplace status at a glance")
        .supportedFamilies([.systemMedium])
        .containerBackgroundRemovable(false)
    }
}

/// Widget entry containing fireplace data
struct FireplaceEntry: TimelineEntry {
    let date: Date
    let isOn: Bool
    let flameHeight: Int
    let temperature: Double
    let ecoModeActive: Bool
    let isConnected: Bool
    /// When the bridge last confirmed this state
    var updatedAt: Date?
    /// Whether `flameHeight` was set by Fyr (the bridge cannot report it)
    var flameHeightIsKnown = true

    /// Preview entry for widget gallery
    static var placeholder: FireplaceEntry {
        FireplaceEntry(
            date: Date(),
            isOn: true,
            flameHeight: 60,
            temperature: 21.5,
            ecoModeActive: false,
            isConnected: true
        )
    }

    /// Entry when data is unavailable
    static var disconnected: FireplaceEntry {
        FireplaceEntry(
            date: Date(),
            isOn: false,
            flameHeight: 0,
            temperature: 0,
            ecoModeActive: false,
            isConnected: false
        )
    }
}

#Preview(as: .systemMedium) {
    FyrWidget()
} timeline: {
    FireplaceEntry.placeholder
    FireplaceEntry.disconnected
}
