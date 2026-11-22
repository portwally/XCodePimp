import Charts
import SwiftUI

struct OverviewView: View {
    @Environment(AppModel.self) private var model

    private struct Slice: Identifiable {
        let category: CategoryID
        let size: Int64
        var id: String { category.rawValue }
    }

    private var slices: [Slice] {
        CategoryID.allCases
            .map { Slice(category: $0, size: model.totalSize($0)) }
            .filter { $0.size > 0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                summary
                if !slices.isEmpty { chart }
                grid
            }
            .padding(24)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Overview")
    }

    private var summary: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Xcode is using")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(model.totalSize.byteText)
                        .font(.system(size: 46, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    if !model.scanning.isEmpty || CategoryID.allCases.contains(where: model.isMeasuring) {
                        ProgressView().controlSize(.small)
                    }
                }
                Text("Your projects and source code are never part of this.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !model.suggestedItems.isEmpty {
                VStack(alignment: .trailing, spacing: 8) {
                    Text("\(model.suggestedSize.byteText) suggested")
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                    Button {
                        model.selectSafeSuggestions()
                        model.selection = .suggested
                    } label: {
                        Label("Review Suggestions", systemImage: "sparkles")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
        }
    }

    private var chart: some View {
        Chart(slices) { slice in
            BarMark(x: .value("Size", slice.size))
                .foregroundStyle(slice.category.color.gradient)
                .accessibilityLabel(slice.category.title)
                .accessibilityValue(slice.size.byteText)
        }
        .chartXAxis(.hidden)
        .chartXScale(domain: 0...max(model.totalSize, 1))
        .chartLegend(.hidden)
        .frame(height: 30)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var grid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 12)], spacing: 12) {
            ForEach(CategoryID.allCases) { category in
                Button {
                    model.selection = .category(category)
                } label: {
                    CategoryCard(category: category)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct CategoryCard: View {
    @Environment(AppModel.self) private var model
    let category: CategoryID

    var body: some View {
        let count = model.items(in: category).count
        HStack(spacing: 12) {
            Image(systemName: category.symbol)
                .font(.title2)
                .foregroundStyle(category.color)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(category.title).font(.headline).lineLimit(1)
                Text(model.scanning.contains(category) ? "Scanning…" : "\(count) item\(count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(model.totalSize(category).byteText)
                .font(.callout.weight(.medium))
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        .contentShape(RoundedRectangle(cornerRadius: 10))
    }
}
