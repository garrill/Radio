import WidgetKit
import SwiftUI
import AppIntents

extension WidgetConfiguration {
    func contentMarginsDisabledIfAvailable() -> some WidgetConfiguration {
        if #available(macOS 14.0, *) {
            return self.contentMarginsDisabled()
        } else {
            return self
        }
    }
}

struct RadioWidget: Widget {
    let kind: String = "RadioWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: RadioWidgetConfigurationIntent.self, provider: RadioWidgetProvider()) { entry in
            RadioWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("NTS Radio")
        .description("Shows what's live now and next on NTS.")
        .contentMarginsDisabledIfAvailable()
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

#Preview(as: .systemLarge) {
    RadioWidget()
} timeline: {
    SimpleEntry(
        date: Date(),
        channel1: ChannelDisplay(location: "London", title: "The Breakfast Show w/ Louise Chen", image: WidgetImages.placeholder, start: Date(), end: Date(), nextTitle: "Soup To Nuts w/ Scratcha", nextEnd: Date()),
        channel2: ChannelDisplay(location: "Manchester", title: "Mended Dreams w/ Claire Rousay", image: WidgetImages.placeholder, start: Date(), end: Date(), nextTitle: "Club Aerobics", nextEnd: Date()),
        selectedChannel: .channel1
    )
}
