import SwiftUI

struct SidebarView: View {
    @Binding var selectedFilter: TaskFilter
    let language: AppLanguage
    let tasks: [DownloadTask]
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.text("app_name", language: language))
                        .font(.system(size: 22, weight: .semibold))
                    Text(selectedFilter.displayName(language: language))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.top, 20)
            .padding(.bottom, 10)

            List(TaskFilter.allCases, selection: $selectedFilter) { filter in
                NavigationLink(value: filter) {
                    HStack(spacing: 10) {
                        Image(systemName: filter.icon)
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 24, height: 24)
                            .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                        Text(filter.displayName(language: language))
                            .font(.system(size: 14, weight: .medium))

                        Spacer()

                        Text(count(for: filter), format: .number)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .tag(filter)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            Divider()

            Button(action: onOpenSettings) {
                HStack {
                    Image(systemName: "gear")
                        .font(.system(size: 14))
                    Text(L10n.text("settings", language: language))
                        .font(.system(size: 13))
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(PlainButtonStyle())
            .contentShape(Rectangle())
            .padding(14)
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.42))
    }

    private func count(for filter: TaskFilter) -> Int {
        switch filter {
        case .all:
            return tasks.count
        case .downloading:
            return tasks.filter { $0.status == .downloading }.count
        case .waiting:
            return tasks.filter { $0.status == .waiting }.count
        case .completed:
            return tasks.filter { $0.status == .completed }.count
        case .stopped:
            return tasks.filter { $0.status == .paused || $0.status == .error }.count
        }
    }
}

struct SidebarItem: View {
    let filter: TaskFilter
    let language: AppLanguage
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: filter.icon)
                    .font(.system(size: 14))
                    .foregroundColor(isSelected ? .white : .secondary)
                    .frame(width: 20)

                Text(filter.displayName(language: language))
                    .font(.system(size: 14))
                    .foregroundColor(isSelected ? .white : .primary)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(PlainButtonStyle())
    }
}
