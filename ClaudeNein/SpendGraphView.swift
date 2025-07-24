import SwiftUI

/// Enum representing graph periods
enum GraphPeriod: String, CaseIterable, Identifiable {
    case day = "Day"
    case month = "Month"
    case year = "Year"

    var id: String { rawValue }
}

struct SpendGraphView: View {
    @State private var period: GraphPeriod = .day
    @State private var values: [Double] = []

    private let dataStore = DataStore.shared

    var body: some View {
        VStack {
            Picker("Period", selection: $period) {
                ForEach(GraphPeriod.allCases) { p in
                    Text(p.rawValue).tag(p)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding()
            GeometryReader { geo in
                ZStack(alignment: .bottomLeading) {
                    Rectangle().fill(Color.clear)
                    drawBars(in: geo.size)
                }
            }
            .padding([.leading, .trailing, .bottom])
        }
        .frame(width: 400, height: 300)
        .onAppear(perform: loadData)
        .onChange(of: period) { _ in loadData() }
    }

    private func loadData() {
        switch period {
        case .day:
            values = dataStore.hourlySpend(for: Date())
        case .month:
            values = dataStore.dailySpend(for: Date())
        case .year:
            values = dataStore.monthlySpend(for: Date())
        }
    }

    @ViewBuilder
    private func drawBars(in size: CGSize) -> some View {
        let maxValue = values.max() ?? 1
        let barWidth = size.width / CGFloat(max(values.count, 1))
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: barWidth - 2,
                           height: maxValue > 0 ? CGFloat(value / maxValue) * size.height : 0)
            }
        }
    }
}

#if DEBUG
struct SpendGraphView_Previews: PreviewProvider {
    static var previews: some View {
        SpendGraphView()
    }
}
#endif
