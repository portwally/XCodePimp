import AppKit
import SwiftUI

/// Header plus sortable table, used for every category and for the Suggested view.
struct ItemListView: View {
    @Environment(AppModel.self) private var model

    let title: String
    let symbol: String
    let tint: Color
    let blurb: String
    let items: [CleanableItem]
    let isLoading: Bool
    var showsReason = false
    var category: CategoryID?

    @State private var sortOrder = [KeyPathComparator(\CleanableItem.sizeSort, order: .reverse)]
    @State private var highlighted: Set<String> = []

    private var sorted: [CleanableItem] { items.sorted(using: sortOrder) }
    private var totalSize: Int64 { items.reduce(0) { $0 + ($1.size ?? 0) } }

    var body: some View {
        // The table is the root so AppKit can manage its scroll view; the header rides along as an inset.
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    header
                    Divider()
                }
                .background(.bar)
            }
            .navigationTitle(title)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label(title, systemImage: symbol)
                    .font(.title2.weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(tint, .primary)
                Spacer()
                if isLoading { ProgressView().controlSize(.small) }
                Text(totalSize.byteText)
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            Text(blurb)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                if showsReason {
                    Button("Select Safe Items") { model.selectSafeSuggestions() }
                } else {
                    Button("Select Safe Items") { model.check(items) { $0.risk == .safe } }
                }
                Button("Select All") { model.check(items) }
                Button("Select None") { model.uncheck(items) }
                Spacer()
                if category == .projects {
                    Button {
                        model.chooseProjectRoots()
                    } label: {
                        Label("Add Folder…", systemImage: "folder.badge.plus")
                    }
                }
            }
            .controlSize(.small)
            .disabled(items.isEmpty && category != .projects)
        }
        .padding(16)
    }

    @ViewBuilder
    private var content: some View {
        if items.isEmpty {
            emptyState
        } else {
            table
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if isLoading {
            ProgressView("Scanning…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if category == .projects, model.projectRoots.isEmpty {
            ContentUnavailableView {
                Label("No Project Folders", systemImage: "folder.badge.questionmark")
            } description: {
                Text("Add the folders where you keep your projects. XcodePimp then lists build folders inside them — never source files.")
            } actions: {
                Button("Add Folder…") { model.chooseProjectRoots() }
            }
        } else {
            ContentUnavailableView(
                showsReason ? "Nothing to Suggest" : "Nothing Here",
                systemImage: "checkmark.seal",
                description: Text(showsReason ? "Everything stale has already been cleaned." : "This category is empty.")
            )
        }
    }

    private var table: some View {
        Table(sorted, selection: $highlighted, sortOrder: $sortOrder) {
            TableColumn("") { item in
                CheckCell(item: item)
            }
            .width(22)

            TableColumn("Name", value: \.title) { item in
                NameCell(item: item, reason: showsReason ? model.suggestions[item.id] : nil)
            }

            TableColumn("Size", value: \.sizeSort) { item in
                SizeCell(item: item)
            }
            .width(min: 70, ideal: 86, max: 110)

            TableColumn("Last Used", value: \.lastUsedSort) { item in
                DateCell(date: item.lastUsed)
            }
            .width(min: 80, ideal: 104, max: 140)

            TableColumn("Safety", value: \.riskSort) { item in
                RiskBadge(risk: item.risk)
            }
            .width(min: 64, ideal: 76, max: 90)
        }
        .contextMenu(forSelectionType: String.self) { ids in
            contextMenu(for: items.filter { ids.contains($0.id) })
        } primaryAction: { ids in
            reveal(items.filter { ids.contains($0.id) })
        }
    }

    @ViewBuilder
    private func contextMenu(for selected: [CleanableItem]) -> some View {
        if !selected.isEmpty {
            Button("Select for Cleaning") { model.check(selected) }
                .disabled(!selected.contains(where: \.isRemovable))
            Button("Deselect") { model.uncheck(selected) }
            Divider()
            Button("Reveal in Finder") { reveal(selected) }
                .disabled(!selected.contains { $0.path != nil })
            Button("Copy Path") {
                let text = selected.compactMap { $0.path?.path }.joined(separator: "\n")
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
            .disabled(!selected.contains { $0.path != nil })
            if selected.count == 1, let secondary = selected[0].secondary {
                Divider()
                Button(secondary.label + "…") { model.requestSecondary(selected[0]) }
            }
        }
    }

    private func reveal(_ selected: [CleanableItem]) {
        let urls = selected.compactMap(\.path).filter { FS.exists($0) }
        if !urls.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(urls) }
    }
}

private struct CheckCell: View {
    @Environment(AppModel.self) private var model
    let item: CleanableItem

    var body: some View {
        Toggle("Select \(item.title)", isOn: Binding(
            get: { model.isChecked(item) },
            set: { model.setChecked(item, $0) }
        ))
        .labelsHidden()
        .toggleStyle(.checkbox)
        .disabled(!item.isRemovable)
        .help(item.isRemovable ? "Select for cleaning" : "Shown for information only")
    }
}

private struct NameCell: View {
    let item: CleanableItem
    let reason: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(item.title)
                    .lineLimit(1)
                if let badge = item.badge {
                    Text(badge)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                }
            }
            Text(reason ?? item.detail)
                .font(.caption)
                .foregroundStyle(reason == nil ? .secondary : .primary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.vertical, 2)
        .help(item.path?.path ?? item.detail)
    }
}

private struct SizeCell: View {
    let item: CleanableItem

    var body: some View {
        if let size = item.size {
            Text(size.byteText).monospacedDigit()
        } else {
            ProgressView().controlSize(.small)
        }
    }
}

private struct DateCell: View {
    let date: Date?

    var body: some View {
        if let date {
            Text(date, format: .dateTime.day().month(.abbreviated).year())
                .foregroundStyle(.secondary)
                .help(date.formatted(.relative(presentation: .named)))
        } else {
            Text("—").foregroundStyle(.tertiary)
        }
    }
}

struct RiskBadge: View {
    let risk: Risk

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(risk.color).frame(width: 7, height: 7)
            Text(risk.label).font(.caption)
        }
        .help(risk.explanation)
    }
}
