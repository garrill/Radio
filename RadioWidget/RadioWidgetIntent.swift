import AppIntents
import WidgetKit

enum WidgetChannelChoice: String, AppEnum {
    case channel1
    case channel2

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Channel"
    static var caseDisplayRepresentations: [WidgetChannelChoice: DisplayRepresentation] = [
        .channel1: "Channel 1",
        .channel2: "Channel 2"
    ]
}

struct RadioWidgetConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Channel"
    static var description = IntentDescription("Choose which NTS channel the small widget shows.")

    @Parameter(title: "Channel", default: .channel1)
    var channel: WidgetChannelChoice
}
