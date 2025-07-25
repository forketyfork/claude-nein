import SwiftUI

extension Array {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

/// Enum representing graph periods
enum GraphPeriod: String, CaseIterable, Identifiable {
    case day = "Day"
    case month = "Month"
    case year = "Year"

    var id: String { rawValue }
}

struct DataPoint {
    let x: Int
    let y: Double
    let label: String
}

struct SpendGraphView: View {
    @State private var period: GraphPeriod = .day
    @State private var dataPoints: [DataPoint] = []

    private let dataStore = DataStore.shared

    var body: some View {
        VStack(spacing: 0) {
            Picker("Period", selection: $period) {
                ForEach(GraphPeriod.allCases) { p in
                    Text(p.rawValue).tag(p)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding()
            
            VStack(alignment: .leading) {
                Text("Cumulative Spend")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, 70)
                
                GeometryReader { geo in
                    ZStack(alignment: .bottomLeading) {
                        drawGrid(in: geo.size)
                        drawYAxisLabels(in: geo.size)
                        drawXAxisLabels(in: geo.size)
                        drawLineGraph(in: geo.size)
                    }
                }
            }
            .padding([.leading, .trailing, .bottom])
        }
        .frame(minWidth: 900, minHeight: 700)
        .onAppear(perform: loadData)
        .onChange(of: period) { _ in loadData() }
    }

    private func loadData() {
        let rawValues: [Double]
        let currentDate = Date()
        let calendar = Calendar.current
        
        switch period {
        case .day:
            rawValues = dataStore.hourlySpend(for: currentDate)
        case .month:
            rawValues = dataStore.dailySpend(for: currentDate)
        case .year:
            rawValues = dataStore.monthlySpend(for: currentDate)
        }
        
        // Determine the current time position to limit data to present
        let currentTimeIndex: Int
        switch period {
        case .day:
            currentTimeIndex = calendar.component(.hour, from: currentDate)
        case .month:
            currentTimeIndex = calendar.component(.day, from: currentDate) - 1 // 0-based
        case .year:
            currentTimeIndex = calendar.component(.month, from: currentDate) - 1 // 0-based
        }
        
        // Only show data up to current time
        let limitedValues = Array(rawValues.prefix(currentTimeIndex + 1))
        
        // Convert to cumulative values and create data points with labels
        var cumulative = 0.0
        dataPoints = limitedValues.enumerated().map { index, value in
            cumulative += value
            return DataPoint(
                x: index,
                y: cumulative,
                label: timeLabel(for: index)
            )
        }
    }
    
    private func timeLabel(for index: Int) -> String {
        switch period {
        case .day:
            return String(format: "%02d:00", index)
        case .month:
            return "\(index + 1)"
        case .year:
            let monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", 
                             "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
            return monthNames[safe: index] ?? "\(index + 1)"
        }
    }

    @ViewBuilder
    private func drawGrid(in size: CGSize) -> some View {
        let graphArea = CGRect(x: 60, y: 10, width: size.width - 90, height: size.height - 60)
        
        Path { path in
            // Horizontal grid lines
            for i in 0...5 {
                let y = graphArea.minY + CGFloat(i) * graphArea.height / 5
                path.move(to: CGPoint(x: graphArea.minX, y: y))
                path.addLine(to: CGPoint(x: graphArea.maxX, y: y))
            }
            
            // Vertical grid lines
            let stepCount = max(dataPoints.count - 1, 1)
            for i in 0...stepCount {
                let x = graphArea.minX + CGFloat(i) * graphArea.width / CGFloat(stepCount)
                path.move(to: CGPoint(x: x, y: graphArea.minY))
                path.addLine(to: CGPoint(x: x, y: graphArea.maxY))
            }
        }
        .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)
    }
    
    @ViewBuilder
    private func drawYAxisLabels(in size: CGSize) -> some View {
        let graphArea = CGRect(x: 60, y: 10, width: size.width - 90, height: size.height - 60)
        let maxValue = dataPoints.map(\.y).max() ?? 1.0
        
        VStack(alignment: .trailing, spacing: 0) {
            ForEach(0...5, id: \.self) { i in
                let value = maxValue * Double(5 - i) / 5.0
                Text(String(format: "$%.2f", value))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(height: graphArea.height / 5, alignment: .trailing)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .frame(width: 50, height: graphArea.height)
        .position(x: 25, y: graphArea.midY)
    }
    
    @ViewBuilder 
    private func drawXAxisLabels(in size: CGSize) -> some View {
        let graphArea = CGRect(x: 60, y: 10, width: size.width - 90, height: size.height - 60)
        
        if !dataPoints.isEmpty {
            ZStack {
                ForEach(Array(dataPoints.enumerated()), id: \.offset) { index, point in
                    let shouldShow = shouldShowXLabel(index: index, total: dataPoints.count)
                    if shouldShow {
                        let x = graphArea.minX + CGFloat(point.x) * graphArea.width / CGFloat(max(dataPoints.count - 1, 1))
                        Text(point.label)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .rotationEffect(.degrees(-45))
                            .position(x: x, y: graphArea.maxY + 25)
                    }
                }
            }
        }
    }
    
    private func shouldShowXLabel(index: Int, total: Int) -> Bool {
        let maxLabels = 8
        if total <= maxLabels { return true }
        let step = max(total / maxLabels, 1)
        return index % step == 0 || index == total - 1
    }

    @ViewBuilder
    private func drawLineGraph(in size: CGSize) -> some View {
        let graphArea = CGRect(x: 60, y: 10, width: size.width - 90, height: size.height - 60)
        
        if dataPoints.count > 1 {
            let maxValue = dataPoints.map(\.y).max() ?? 1.0
            
            // Line path
            Path { path in
                for (index, point) in dataPoints.enumerated() {
                    let x = graphArea.minX + CGFloat(point.x) * graphArea.width / CGFloat(max(dataPoints.count - 1, 1))
                    let y = graphArea.maxY - (CGFloat(point.y / maxValue) * graphArea.height)
                    
                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            
            // Data points
            ForEach(Array(dataPoints.enumerated()), id: \.offset) { index, point in
                let x = graphArea.minX + CGFloat(point.x) * graphArea.width / CGFloat(max(dataPoints.count - 1, 1))
                let y = graphArea.maxY - (CGFloat(point.y / maxValue) * graphArea.height)
                
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 4, height: 4)
                    .position(x: x, y: y)
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
