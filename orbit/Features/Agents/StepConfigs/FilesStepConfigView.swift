import SwiftUI
import AppKit

struct FilesStepConfigView: View {
    let step: AgentStep
    let onChanged: () -> Void

    @State private var folderPath = ""
    @State private var recursive = false
    @State private var maxFiles = 20

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OSpacing.lg) {
                configRow("Folder") {
                    HStack(spacing: OSpacing.xs) {
                        Text(folderPath.isEmpty ? "No folder selected" : folderPath)
                            .font(.oCaption)
                            .foregroundStyle(folderPath.isEmpty ? Color.oTextTertiary : Color.oTextPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Button("Choose…") { pickFolder() }
                            .font(.oCaptionMed)
                            .buttonStyle(.bordered)
                            .tint(Color.oAccent)
                    }
                }

                configRow("Max files") {
                    HStack {
                        Stepper("\(maxFiles)", value: $maxFiles, in: 1...200, step: 10)
                            .onChange(of: maxFiles) { _, _ in save() }
                        Spacer()
                    }
                }

                Toggle("Include subfolders", isOn: $recursive)
                    .font(.oBody)
                    .onChange(of: recursive) { _, _ in save() }
                    .tint(Color.oAccent)

                privacyNote
            }
            .padding(OSpacing.md)
        }
        .onAppear { load() }
    }

    private func load() {
        let cfg = step.decodedConfig(FilesStepConfig.self) ?? FilesStepConfig()
        folderPath = cfg.folderPath
        recursive = cfg.recursive
        maxFiles = cfg.maxFiles
    }

    private func save() {
        var cfg = FilesStepConfig()
        cfg.folderPath = folderPath
        cfg.recursive = recursive
        cfg.maxFiles = maxFiles
        step.encodeConfig(cfg)
        onChanged()
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Folder"
        if panel.runModal() == .OK, let url = panel.url {
            folderPath = url.path
            save()
        }
    }
}
