import SwiftUI

struct PromptEditorSidebarView: View {
    @State private var selectedNav: String = "Overview"
    let snippets: [String]
    let recentTemplates: [PromptTemplate]
    let onInsertSnippet: (String) -> Void
    let onOpenTemplate: (PromptTemplate) -> Void

    private let navItems: [(icon: String, label: String)] = [
        ("square.grid.2x2", "Overview"),
        ("folder", "Categories"),
        ("chart.bar", "Dashboard"),
        ("arrow.left.arrow.right", "Comparison"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Navigation items
            VStack(alignment: .leading, spacing: 2) {
                ForEach(navItems, id: \.label) { item in
                    Button {
                        selectedNav = item.label
                    } label: {
                        HStack(spacing: OSpacing.sm) {
                            Image(systemName: item.icon)
                                .font(.system(size: 12))
                                .frame(width: 16, alignment: .center)
                                .foregroundStyle(selectedNav == item.label ? Color.oAccent : Color.oTextSecondary)

                            Text(item.label)
                                .font(.oBody)
                                .foregroundStyle(selectedNav == item.label ? Color.oAccent : Color.oTextPrimary)

                            Spacer()
                        }
                        .padding(.horizontal, OSpacing.sm)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: ORadius.sm)
                                .fill(selectedNav == item.label ? Color.oSidebarSelected : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, OSpacing.md)
            .padding(.horizontal, OSpacing.xs)

            Divider()
                .padding(.vertical, OSpacing.sm)

            // Snippets
            if !snippets.isEmpty {
                sectionHeader("SNIPPETS")

                ForEach(snippets, id: \.self) { snippet in
                    Button {
                        onInsertSnippet(snippet)
                    } label: {
                        Text(snippet)
                            .font(.oCaption)
                            .foregroundStyle(Color.oTextPrimary)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, OSpacing.sm)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: ORadius.sm)
                                    .fill(Color.oSurfaceSecondary.opacity(0.5))
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, OSpacing.xs)
            }

            if !recentTemplates.isEmpty {
                sectionHeader("RECENT TEMPLATES")

                ForEach(recentTemplates.prefix(5)) { template in
                    Button {
                        onOpenTemplate(template)
                    } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(template.name)
                                .font(.oCaptionMed)
                                .foregroundStyle(Color.oTextPrimary)
                                .lineLimit(1)

                            Text(template.updatedAt.formatted(date: .abbreviated, time: .omitted))
                                .font(.oMicro)
                                .foregroundStyle(Color.oTextTertiary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, OSpacing.sm)
                        .padding(.vertical, 3)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, OSpacing.xs)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.oMicro)
            .foregroundStyle(Color.oTextTertiary)
            .padding(.horizontal, OSpacing.sm + 16 + OSpacing.sm)
            .padding(.vertical, OSpacing.xs)
    }
}
