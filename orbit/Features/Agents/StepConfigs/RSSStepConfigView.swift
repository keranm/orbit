import SwiftUI

struct RSSStepConfigView: View {
    let step: AgentStep
    let onChanged: () -> Void

    @State private var feedURLs: [String] = []
    @State private var newFeedURL = ""
    @State private var maxItemsPerFeed = 10
    @State private var includeContent = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OSpacing.lg) {
                configRow("Feeds") {
                    VStack(spacing: OSpacing.xs) {
                        ForEach(feedURLs.indices, id: \.self) { i in
                            HStack(spacing: OSpacing.xs) {
                                Text(feedURLs[i])
                                    .font(.oCaption)
                                    .foregroundStyle(Color.oTextPrimary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Button {
                                    feedURLs.remove(at: i)
                                    save()
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(Color.oTextTertiary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, OSpacing.xs)
                            .padding(.vertical, OSpacing.xxs)
                            .background(Color.oSurfaceSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: ORadius.sm))
                        }

                        HStack(spacing: OSpacing.xs) {
                            TextField("https://feeds.example.com/rss", text: $newFeedURL)
                                .textFieldStyle(.plain)
                                .font(.oCaption)
                                .padding(OSpacing.xs)
                                .background(Color.oSurfaceSecondary)
                                .clipShape(RoundedRectangle(cornerRadius: ORadius.sm))
                                .onSubmit { addFeed() }

                            Button("Add") { addFeed() }
                                .font(.oCaptionMed)
                                .buttonStyle(.bordered)
                                .tint(Color.oAccent)
                                .disabled(newFeedURL.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                }

                if feedURLs.isEmpty {
                    Text("No feeds added yet. Paste an RSS feed URL above.")
                        .font(.oCaption)
                        .foregroundStyle(Color.oTextTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                configRow("Max items per feed") {
                    HStack {
                        Stepper("\(maxItemsPerFeed)", value: $maxItemsPerFeed, in: 1...50)
                            .onChange(of: maxItemsPerFeed) { _, _ in save() }
                        Spacer()
                    }
                }

                Toggle("Include full article text", isOn: $includeContent)
                    .font(.oBody)
                    .onChange(of: includeContent) { _, _ in save() }
                    .tint(Color.oAccent)

                privacyNote
            }
            .padding(OSpacing.md)
        }
        .onAppear { load() }
    }

    private func load() {
        let cfg = step.decodedConfig(RSSStepConfig.self) ?? RSSStepConfig()
        feedURLs = cfg.feedURLs
        maxItemsPerFeed = cfg.maxItemsPerFeed
        includeContent = cfg.includeContent
    }

    private func save() {
        var cfg = RSSStepConfig()
        cfg.feedURLs = feedURLs
        cfg.maxItemsPerFeed = maxItemsPerFeed
        cfg.includeContent = includeContent
        step.encodeConfig(cfg)
        onChanged()
    }

    private func addFeed() {
        let trimmed = newFeedURL.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !feedURLs.contains(trimmed) else { return }
        feedURLs.append(trimmed)
        newFeedURL = ""
        save()
    }
}
