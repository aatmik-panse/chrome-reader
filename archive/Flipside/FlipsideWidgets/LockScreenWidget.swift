import WidgetKit
import SwiftUI

// MARK: - Lock Screen Widget Definition

struct LockScreenWidget: Widget {
    let kind = "FlipsideLockScreenWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: ReadingWidgetConfigurationIntent.self,
            provider: LockScreenTimelineProvider()
        ) { entry in
            LockScreenEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Reading Progress")
        .description("Track your reading progress on the Lock Screen.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular])
    }
}

// MARK: - Entry View

struct LockScreenEntryView: View {
    let entry: ReadingEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                circularView
            case .accessoryRectangular:
                rectangularView
            default:
                rectangularView
            }
        }
        .widgetURL(URL(string: "flipside://read"))
    }

    // MARK: - Accessory Rectangular

    private var rectangularView: some View {
        Group {
            if entry.hasBook {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Image(systemName: "book.fill")
                            .font(.system(size: 10, weight: .semibold))

                        Text(entry.bookTitle)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                    }

                    Gauge(value: entry.percentage, in: 0...1) {
                        EmptyView()
                    } currentValueLabel: {
                        EmptyView()
                    } minimumValueLabel: {
                        Text("p.\(entry.currentPage + 1)")
                            .font(.system(size: 10))
                    } maximumValueLabel: {
                        Text("\(Int(entry.percentage * 100))%")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .gaugeStyle(.accessoryLinear)

                    if !entry.chapterTitle.isEmpty {
                        Text(entry.chapterTitle)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Image(systemName: "book.closed.fill")
                            .font(.system(size: 10))
                        Text("Flipside")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    Text("No book selected")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Accessory Circular

    private var circularView: some View {
        Group {
            if entry.hasBook {
                Gauge(value: entry.percentage, in: 0...1) {
                    Image(systemName: "book.fill")
                        .font(.system(size: 12))
                } currentValueLabel: {
                    Text("\(Int(entry.percentage * 100))")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                }
                .gaugeStyle(.accessoryCircular)
            } else {
                ZStack {
                    AccessoryWidgetBackground()

                    Image(systemName: "book.closed.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("Rectangular", as: .accessoryRectangular) {
    LockScreenWidget()
} timeline: {
    ReadingEntry.placeholder
}

#Preview("Circular", as: .accessoryCircular) {
    LockScreenWidget()
} timeline: {
    ReadingEntry.placeholder
}
