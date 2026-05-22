import SwiftUI

struct AgentStepCardView: View {
    let step: AgentStep
    let stepNumber: Int
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: OSpacing.sm) {
                // Step type icon
                Image(systemName: step.stepType.icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(iconColor)
                    .frame(width: 28, height: 28)
                    .background(iconBackground)
                    .clipShape(RoundedRectangle(cornerRadius: ORadius.sm))

                // Step info
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(stepNumber). \(step.label)")
                        .font(.oBodyMedium)
                        .foregroundStyle(Color.oTextPrimary)
                        .lineLimit(1)
                    Text(stepSubtitle)
                        .font(.oMicro)
                        .foregroundStyle(Color.oTextSecondary)
                        .lineLimit(1)
                }

                Spacer()

                // Overflow menu
                Menu {
                    Button("Delete", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.oTextTertiary)
                        .frame(width: 24, height: 24)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .opacity(isHovered || isSelected ? 1 : 0)
            }
            .padding(.horizontal, OSpacing.md)
            .padding(.vertical, OSpacing.sm)
            .background(cardBackground)
            .overlay(cardBorder)
            .clipShape(RoundedRectangle(cornerRadius: ORadius.md))
        }
        .buttonStyle(.plain)
        .onHover { over in isHovered = over }
        .accessibilityLabel("Step \(stepNumber): \(step.label), \(step.stepType.label)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - Computed appearance

    private var iconColor: Color {
        switch step.stepType {
        case .readMail:      return Color.oAccent
        case .readCalendar:  return Color.oMeshTeal
        case .readReminders: return Color.oSuccessGreen
        case .readFiles:     return Color.oWarningAmber
        case .readRSS:       return Color.oAccent
        case .think:         return Color.oAccent
        case .condition:     return Color.oWarningAmber
        case .output:        return Color.oSuccessGreen
        }
    }

    private var iconBackground: Color { iconColor.opacity(0.12) }

    private var cardBackground: Color {
        if isSelected { return Color.oAccentSoft }
        if isHovered  { return Color.oSurfaceSecondary }
        return Color.oSurface
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: ORadius.md)
            .stroke(isSelected ? Color.oAccent.opacity(0.4) : Color.oDivider, lineWidth: 1)
    }

    private var stepSubtitle: String {
        switch step.stepType {
        case .readMail:
            if let cfg = step.decodedConfig(MailStepConfig.self) {
                let from = cfg.fromFilter.isEmpty ? "Any sender" : "From: \(cfg.fromFilter)"
                return "\(from) · Last \(cfg.dateRangeHours)h"
            }
            return step.stepType.subtitle
        case .readCalendar:
            if let cfg = step.decodedConfig(CalendarStepConfig.self) {
                return calendarRangeLabel(cfg)
            }
            return step.stepType.subtitle
        case .readRSS:
            if let cfg = step.decodedConfig(RSSStepConfig.self), !cfg.feedURLs.isEmpty {
                return "\(cfg.feedURLs.count) feed\(cfg.feedURLs.count == 1 ? "" : "s")"
            }
            return "No feeds configured"
        case .think:
            if let cfg = step.decodedConfig(ThinkStepConfig.self), !cfg.systemPrompt.isEmpty {
                let prefix = cfg.systemPrompt.prefix(40)
                return String(prefix) + (cfg.systemPrompt.count > 40 ? "…" : "")
            }
            return "Use \(step.decodedConfig(ThinkStepConfig.self)?.modelRef.isEmpty == false ? step.decodedConfig(ThinkStepConfig.self)!.modelRef : "active model")"
        default:
            return step.stepType.subtitle
        }
    }

    private func calendarRangeLabel(_ cfg: CalendarStepConfig) -> String {
        switch cfg.rangeType {
        case .today:      return "Today"
        case .thisWeek:   return "This week"
        case .nextNDays:  return "Next \(cfg.rangeDays) days"
        case .lastNDays:  return "Last \(cfg.rangeDays) days"
        }
    }
}
