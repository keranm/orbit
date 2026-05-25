import SwiftUI
import SwiftData

/// Right-hand panel shown alongside all chat screens.
/// Contains the Nova companion at the top and a searchable list of previous chats below.
struct ChatHistoryPanel: View {
    /// ID of the chat currently open, used to highlight the active row.
    var activeChatID: UUID? = nil

    @Environment(AppState.self) private var appState
    @Query(sort: \Chat.updatedAt, order: .reverse) private var allChats: [Chat]

    @State private var searchText = ""
    @State private var filter: Filter = .all

    enum Filter: String, CaseIterable {
        case all = "All"
        case today = "Today"
        case week = "Week"
    }

    private var filteredChats: [Chat] {
        let base: [Chat]
        switch filter {
        case .all:
            base = allChats
        case .today:
            let start = Calendar.current.startOfDay(for: Date())
            base = allChats.filter { $0.updatedAt >= start }
        case .week:
            let start = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
            base = allChats.filter { $0.updatedAt >= start }
        }

        if searchText.isEmpty { return base }
        let q = searchText.lowercased()
        return base.filter { $0.title.lowercased().contains(q) }
    }

    var body: some View {
        VStack(spacing: 0) {
            novaSection
            Divider()
            historySection
        }
        .frame(width: 268)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.oBackground)
    }

    // MARK: - Nova

    private var novaSection: some View {
        VStack(spacing: OSpacing.xs) {
            NovaView(state: appState.novaState, size: 60)
                .onTapGesture { appState.handleNovaTap() }
                .padding(.top, OSpacing.xl)
                .padding(.bottom, OSpacing.sm)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - History

    private var historySection: some View {
        VStack(spacing: 0) {
            historyHeader
            Divider()
            if filteredChats.isEmpty {
                emptyState
            } else {
                chatList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var historyHeader: some View {
        VStack(spacing: OSpacing.sm) {
            // Title row
            HStack {
                Text("Previous Chats")
                    .font(.oCaptionMed)
                    .foregroundStyle(Color.oTextSecondary)
                Spacer()
            }

            // Search field
            HStack(spacing: OSpacing.xs) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.oTextTertiary)
                TextField("Search chats…", text: $searchText)
                    .font(.oCaption)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.oTextTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, OSpacing.sm)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: ORadius.sm)
                    .fill(Color.oSurfaceSecondary)
            )

            // Filter chips
            HStack(spacing: OSpacing.xs) {
                ForEach(Filter.allCases, id: \.self) { f in
                    filterChip(f)
                }
                Spacer()
            }
        }
        .padding(.horizontal, OSpacing.md)
        .padding(.top, OSpacing.md)
        .padding(.bottom, OSpacing.sm)
    }

    private func filterChip(_ f: Filter) -> some View {
        let active = filter == f
        return Button { filter = f } label: {
            Text(f.rawValue)
                .font(.oMicro)
                .foregroundStyle(active ? Color.oAccent : Color.oTextTertiary)
                .padding(.horizontal, OSpacing.sm)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(active ? Color.oAccentSoft : Color.oSurfaceSecondary)
                )
        }
        .buttonStyle(.plain)
    }

    private var chatList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(filteredChats) { chat in
                    chatRow(chat)
                    Divider()
                        .padding(.leading, OSpacing.md)
                }
            }
        }
    }

    private func chatRow(_ chat: Chat) -> some View {
        let isActive = chat.id == activeChatID
        return Button {
            appState.route = .chat(id: chat.id)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(chat.title)
                    .font(isActive ? .oCaptionMed : .oCaption)
                    .foregroundStyle(isActive ? Color.oAccent : Color.oTextPrimary)
                    .lineLimit(1)

                HStack(spacing: OSpacing.xs) {
                    Text(chat.updatedAt.relativeLabel)
                        .font(.oMicro)
                        .foregroundStyle(Color.oTextTertiary)

                    if let last = chat.lastMessage {
                        Text("·")
                            .font(.oMicro)
                            .foregroundStyle(Color.oTextTertiary)
                        Text(last.content)
                            .font(.oMicro)
                            .foregroundStyle(Color.oTextTertiary)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, OSpacing.md)
            .padding(.vertical, OSpacing.sm)
            .background(isActive ? Color.oAccentSoft : Color.clear)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    private var emptyState: some View {
        VStack(spacing: OSpacing.xs) {
            Text(searchText.isEmpty ? "No chats yet" : "No results")
                .font(.oCaption)
                .foregroundStyle(Color.oTextTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, OSpacing.xl)
    }
}

// MARK: - Date helper

private extension Date {
    var relativeLabel: String {
        let cal = Calendar.current
        if cal.isDateInToday(self) {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            return formatter.string(from: self)
        }
        if cal.isDateInYesterday(self) { return "Yesterday" }
        let days = cal.dateComponents([.day], from: self, to: Date()).day ?? 0
        if days < 7 {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE"
            return formatter.string(from: self)
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter.string(from: self)
    }
}
