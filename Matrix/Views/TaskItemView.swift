import SwiftUI

struct TaskItemView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    let task: DownloadTask
    let isSelected: Bool
    let onSelect: () -> Void
    let onPauseResume: () -> Void
    let onDeleteRequest: () -> Void

    private var language: AppLanguage {
        settingsStore.settings.appLanguage
    }

    var body: some View {
        HStack(spacing: 14) {
            statusIcon
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 42, height: 42)
                .background(statusColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(task.filename)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(kindTitle)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.10), in: Capsule())
                        .lineLimit(1)

                    Spacer()

                    Text(formattedTotalSize)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        ProgressView(value: task.progress, total: 1.0)
                            .progressViewStyle(.linear)
                            .tint(statusColor)
                            .frame(height: 5)

                        Text("\(Int(task.progress * 100))%")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: 40, alignment: .trailing)
                    }

                    HStack(spacing: 8) {
                        StatusChip(text: task.status.displayName(language: language), tint: statusColor)

                        if task.status == .downloading {
                            StatusChip(text: task.formattedSpeed, tint: .blue)
                        }

                        if task.kind.isBitTorrent {
                            StatusChip(text: L10n.format("seeders", language: language, task.seeders), tint: .secondary, usesSecondaryForeground: true)
                            StatusChip(text: L10n.format("connections_count", language: language, task.connections), tint: .orange)
                        }

                        if let eta = task.remainingTime(language: language), task.status == .downloading {
                            Text("\(L10n.text("remaining", language: language)) \(eta)")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()
                    }
                }

                HStack(spacing: 10) {
                    Text(task.url)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    Text("\(task.formattedDownloadedSize) / \(task.formattedTotalSize)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }

            HStack(spacing: 8) {
                if task.status == .downloading || task.status == .waiting {
                    actionButton(symbol: "pause.fill", tint: .secondary, action: onPauseResume)
                } else if task.status == .paused || task.status == .error {
                    actionButton(symbol: "play.fill", tint: .accentColor, action: onPauseResume)
                }

                actionButton(symbol: "trash", tint: .red, action: onDeleteRequest)
            }
        }
        .padding(14)
        .background(backgroundFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isSelected ? Color.accentColor.opacity(0.35) : Color.white.opacity(0.58), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
    }

    private var backgroundFill: some ShapeStyle {
        if isSelected {
            return AnyShapeStyle(Color.accentColor.opacity(0.12))
        }
        return AnyShapeStyle(Color.white.opacity(0.24))
    }

    private var statusIcon: some View {
        switch task.status {
        case .downloading:
            return Image(systemName: "arrow.down.circle.fill")
                .foregroundColor(.blue)
        case .waiting:
            return Image(systemName: "clock")
                .foregroundColor(.orange)
        case .completed:
            return Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        case .paused:
            return Image(systemName: "pause.circle.fill")
                .foregroundColor(.yellow)
        case .error:
            return Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
        }
    }

    private var statusColor: Color {
        switch task.status {
        case .downloading:
            return .blue
        case .waiting:
            return .orange
        case .completed:
            return .green
        case .paused:
            return .yellow
        case .error:
            return .red
        }
    }

    private var formattedTotalSize: String {
        ByteCountFormatter.string(fromByteCount: task.totalSize, countStyle: .file)
    }

    private var kindTitle: String {
        task.kind.displayName(language: language)
    }

    @ViewBuilder
    private func actionButton(symbol: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct StatusChip: View {
    let text: String
    let tint: Color
    var usesSecondaryForeground = false

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(usesSecondaryForeground ? AnyShapeStyle(.secondary) : AnyShapeStyle(tint))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(usesSecondaryForeground ? 0.08 : 0.12), in: Capsule())
    }
}
