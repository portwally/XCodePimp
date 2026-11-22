import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        Form {
            Section("Suggestions") {
                Stepper(value: $model.staleDays, in: 7...365, step: 1) {
                    Text("Suggest derived data unused for \(model.staleDays) days")
                }
                Text("Simulator runtimes are suggested after three times that long.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Removing") {
                Toggle("Delete permanently instead of moving to the Trash", isOn: $model.permanentDelete)
                Toggle("Dry run — log what would be removed without removing it", isOn: $model.dryRun)
            }

            Section("Project folders") {
                if model.projectRoots.isEmpty {
                    Text("No folders added.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.projectRoots, id: \.path) { url in
                    HStack {
                        Image(systemName: "folder")
                        Text(url.path(percentEncoded: false))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button {
                            model.removeProjectRoot(url)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Stop scanning this folder")
                    }
                }
                Button("Add Folder…") { model.chooseProjectRoots() }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct HistoryView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.history.isEmpty {
                ContentUnavailableView(
                    "No History Yet",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Everything XcodePimp removes is recorded here.")
                )
            } else {
                Table(model.history) {
                    TableColumn("When") { entry in
                        Text(entry.date, format: .dateTime.day().month(.abbreviated).hour().minute())
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 110, ideal: 130, max: 160)

                    TableColumn("Item") { entry in
                        Label(entry.title, systemImage: entry.category.symbol)
                            .lineLimit(1)
                    }

                    TableColumn("Size") { entry in
                        Text(entry.size.byteText).monospacedDigit()
                    }
                    .width(min: 70, ideal: 86, max: 110)

                    TableColumn("Result") { entry in
                        Label(entry.message, systemImage: symbol(for: entry))
                            .foregroundStyle(entry.success ? Color.primary : Color.red)
                            .lineLimit(1)
                            .help(entry.message)
                    }
                }
            }
        }
        .navigationTitle("History")
        .toolbar {
            ToolbarItem {
                Button("Clear History") { model.clearHistory() }
                    .disabled(model.history.isEmpty)
            }
        }
    }

    private func symbol(for entry: HistoryEntry) -> String {
        if !entry.success { return "xmark.octagon" }
        return entry.dryRun ? "eye" : "checkmark.circle"
    }
}
