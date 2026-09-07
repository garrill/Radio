#if os(macOS)
import SwiftUI

struct MixtapeSettingsView: View {
    @EnvironmentObject var ntsService: NTSService
    @AppStorage("showInfiniteMixtapes") private var showInfiniteMixtapes = false
    @AppStorage("enabledMixtapes") private var enabledMixtapes = ""

    var body: some View {
        Form {
            Section {
                Toggle("Show infinite mixtapes", isOn: $showInfiniteMixtapes)
                Text("Adds a row of NTS Infinite Mixtape streams to the main window, below Stream 2.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Section("Mixtapes") {
                if ntsService.mixtapes.isEmpty {
                    Text("Loading mixtapes…")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(ntsService.mixtapes) { mixtape in
                        Toggle(isOn: binding(for: mixtape)) {
                            HStack(spacing: 10) {
                                artwork(for: mixtape)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(mixtape.title)
                                        .font(.system(size: 12, weight: .medium))
                                    Text(mixtape.subtitle)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                        }
                        .disabled(!showInfiniteMixtapes)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .padding(.bottom, 8)
        .onAppear { ntsService.fetchMixtapes() }
    }

    @ViewBuilder
    private func artwork(for mixtape: Mixtape) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4).fill(.secondary.opacity(0.12))
            if let url = mixtape.artworkURL {
                ArtworkImage(url: url, dimension: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .frame(width: 40, height: 40)
    }

    private func binding(for mixtape: Mixtape) -> Binding<Bool> {
        Binding(
            get: { MixtapeSelection.isEnabled(mixtape.alias, in: enabledMixtapes) },
            set: { _ in enabledMixtapes = MixtapeSelection.toggling(mixtape.alias, in: enabledMixtapes) }
        )
    }
}
#endif
