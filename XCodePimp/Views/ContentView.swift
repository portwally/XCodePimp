import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 320)
        } detail: {
            detail
                .safeAreaInset(edge: .bottom, spacing: 0) { SelectionBar() }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await model.scan() }
                } label: {
                    Label("Rescan", systemImage: "arrow.clockwise")
                }
                .disabled(model.isBusy)
                .help("Scan all Xcode folders again")
            }
        }
        .sheet(item: $model.pendingClean) { request in
            ConfirmSheet(request: request)
        }
        .alert("XcodePimp", isPresented: Binding(
            get: { model.resultMessage != nil },
            set: { if !$0 { model.resultMessage = nil } }
        )) {
            Button("OK") { model.resultMessage = nil }
        } message: {
            Text(model.resultMessage ?? "")
        }
        .task { await model.scanIfNeeded() }
    }

    @ViewBuilder
    private var detail: some View {
        switch model.selection ?? .overview {
        case .overview:
            OverviewView()
        case .suggested:
            ItemListView(
                title: "Suggested",
                symbol: "sparkles",
                tint: .yellow,
                blurb: "Items that are stale, orphaned or superseded. Risk-free ones can be ticked with one click; anything that needs a download afterwards is left for you to decide.",
                items: model.suggestedItems,
                isLoading: !model.scanning.isEmpty,
                showsReason: true
            )
        case .history:
            HistoryView()
        case .category(let category):
            ItemListView(
                title: category.title,
                symbol: category.symbol,
                tint: category.color,
                blurb: category.blurb,
                items: model.items(in: category),
                isLoading: model.scanning.contains(category),
                category: category
            )
        }
    }
}

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        List(selection: $model.selection) {
            Section {
                Label("Overview", systemImage: "chart.bar.xaxis")
                    .tag(SidebarItem.overview)
                Label("Suggested", systemImage: "sparkles")
                    .badge(model.suggestedItems.isEmpty ? nil : Text(model.suggestedSize.byteText))
                    .tag(SidebarItem.suggested)
            }
            Section("Categories") {
                ForEach(CategoryID.allCases) { category in
                    Label(category.title, systemImage: category.symbol)
                        .badge(badge(for: category))
                        .tag(SidebarItem.category(category))
                }
            }
            Section {
                Label("History", systemImage: "clock.arrow.circlepath")
                    .tag(SidebarItem.history)
            }
        }
        .listStyle(.sidebar)
    }

    private func badge(for category: CategoryID) -> Text? {
        if model.scanning.contains(category) { return Text("…") }
        let size = model.totalSize(category)
        return size > 0 ? Text(size.byteText) : nil
    }
}

/// Bottom bar showing what is ticked and the button that starts cleaning.
struct SelectionBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let items = model.checkedItems
        if !items.isEmpty || model.isCleaning {
            HStack(spacing: 12) {
                if model.isCleaning {
                    ProgressView().controlSize(.small)
                    Text(model.cleanProgress ?? "Cleaning…")
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
                    Text("\(items.count) item\(items.count == 1 ? "" : "s") selected")
                    Text(model.checkedSize.byteText)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                    if model.dryRun {
                        Text("Dry run")
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.orange.opacity(0.2), in: Capsule())
                    }
                }
                Spacer()
                Button("Deselect All") { model.checked.removeAll() }
                    .disabled(model.isCleaning)
                Button {
                    model.requestCleanChecked()
                } label: {
                    Label("Clean…", systemImage: "trash")
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isCleaning || items.isEmpty)
                .keyboardShortcut(.delete, modifiers: .command)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)
            .overlay(alignment: .top) { Divider() }
        }
    }
}
