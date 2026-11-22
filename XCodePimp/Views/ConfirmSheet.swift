import SwiftUI

struct ConfirmSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let request: CleanRequest

    private var hasKeepItems: Bool { request.items.contains { $0.risk == .keep } }
    private var hasSimulatorItems: Bool {
        request.items.contains { if case .simctl = request.override ?? $0.action { true } else { false } }
    }
    private var hasFileItems: Bool {
        request.items.contains { if case .files = request.override ?? $0.action { true } else { false } }
    }
    private var touchesBuildData: Bool {
        request.items.contains { $0.category == .derivedData || $0.category == .projects }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(request.verb) \(request.items.count) item\(request.items.count == 1 ? "" : "s")?")
                    .font(.title2.weight(.semibold))
                Spacer()
                if request.override == nil {
                    Text(request.totalSize.byteText)
                        .font(.title2.weight(.semibold))
                        .monospacedDigit()
                }
            }

            List(request.items) { item in
                HStack {
                    Image(systemName: item.category.symbol)
                        .foregroundStyle(item.category.color)
                        .frame(width: 20)
                    VStack(alignment: .leading) {
                        Text(item.title).lineLimit(1)
                        Text(item.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()
                    RiskBadge(risk: item.risk)
                    Text((item.size ?? 0).byteText)
                        .monospacedDigit()
                        .frame(width: 80, alignment: .trailing)
                }
            }
            .listStyle(.bordered)
            .frame(minHeight: 160, maxHeight: 300)

            VStack(alignment: .leading, spacing: 6) {
                if model.dryRun {
                    note("eye", .orange, "Dry run is on. Nothing will be removed; the result is only logged in History.")
                }
                if hasFileItems {
                    if model.permanentDelete {
                        note("exclamationmark.triangle.fill", .red, "Files are deleted permanently. This cannot be undone.")
                    } else {
                        note("trash", .secondary, "Files are moved to the Trash. Space is freed once you empty it.")
                    }
                }
                if hasSimulatorItems {
                    note("iphone", .secondary, "Simulators and runtimes are removed by Xcode's simctl and do not go to the Trash.")
                }
                if hasKeepItems {
                    note("exclamationmark.triangle.fill", .red, "The selection includes archives. Without their dSYMs, crash reports for those builds can no longer be symbolicated.")
                }
                if touchesBuildData, model.isXcodeRunning {
                    note("hammer", .orange, "Xcode is running. Quit it first, or expect a full rebuild and re-index of open projects.")
                }
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(model.dryRun ? "Run Dry Run" : request.verb) {
                    dismiss()
                    Task { await model.perform(request) }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(hasKeepItems || model.permanentDelete ? .red : .accentColor)
            }
        }
        .padding(20)
        .frame(width: 600)
    }

    private func note(_ symbol: String, _ color: Color, _ text: String) -> some View {
        Label {
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol).foregroundStyle(color)
        }
    }
}
