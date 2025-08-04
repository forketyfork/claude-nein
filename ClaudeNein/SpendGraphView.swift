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

struct SpendGraphView: View {
    @State private var period: GraphPeriod = .day
    @State private var dataPoints: [DataPoint] = []
    @State private var selectedDate: Date = Date()
    @State private var earliestDataDate: Date?
    @State private var selectedRendererType: GraphRendererType = GraphRendererType.bar

    private var monthBinding: Binding<Int> {
        Binding<Int>(
            get: { 
                let currentMonth = Calendar.current.component(.month, from: selectedDate)
                // Ensure the current month is within the available range
                let availableMonths = monthRange
                if availableMonths.contains(currentMonth) {
                    return currentMonth
                } else {
                    // Return the first available month if current is not available
                    return availableMonths.first ?? currentMonth
                }
            },
            set: { newMonth in
                var comps = Calendar.current.dateComponents([.year], from: selectedDate)
                comps.month = newMonth
                comps.day = 1
                if let newDate = Calendar.current.date(from: comps) {
                    selectedDate = newDate
                }
            }
        )
    }

    private var yearBinding: Binding<Int> {
        Binding<Int>(
            get: { Calendar.current.component(.year, from: selectedDate) },
            set: { newYear in
                var comps = Calendar.current.dateComponents([.month], from: selectedDate)
                comps.year = newYear
                if period == .year {
                    comps.month = 1
                    comps.day = 1
                } else if period == .month {
                    comps.day = 1
                }
                if let newDate = Calendar.current.date(from: comps) {
                    selectedDate = newDate
                }
            }
        )
    }

    private var yearRange: [Int] {
        let calendar = Calendar.current
        let current = calendar.component(.year, from: Date())
        
        let earliest: Int
        if let earliestDataDate = earliestDataDate {
            earliest = calendar.component(.year, from: earliestDataDate)
        } else {
            earliest = current
        }
        
        return Array(earliest...current)
    }
    
    private var monthRange: [Int] {
        guard let earliestDataDate = earliestDataDate else {
            return Array(1...12)
        }
        
        let calendar = Calendar.current
        let selectedYear = calendar.component(.year, from: selectedDate)
        let earliestYear = calendar.component(.year, from: earliestDataDate)
        let currentYear = calendar.component(.year, from: Date())
        let currentMonth = calendar.component(.month, from: Date())
        let earliestMonth = calendar.component(.month, from: earliestDataDate)
        
        let startMonth: Int
        let endMonth: Int
        
        if selectedYear == earliestYear {
            startMonth = earliestMonth
        } else {
            startMonth = 1
        }
        
        if selectedYear == currentYear {
            endMonth = currentMonth
        } else {
            endMonth = 12
        }
        
        return Array(startMonth...endMonth)
    }
    
    private var dateRange: ClosedRange<Date> {
        let latest = Date()
        let earliest = earliestDataDate ?? latest
        return earliest...latest
    }

    @ViewBuilder
    private var periodSelector: some View {
        switch period {
        case .day:
            HStack {
                DatePicker("", selection: $selectedDate, in: dateRange, displayedComponents: [.date])
                    .datePickerStyle(FieldDatePickerStyle())
                    .labelsHidden()
                    .frame(minWidth: 150)
                
                Button("Today") {
                    selectedDate = Date()
                }
                .disabled(Calendar.current.isDate(selectedDate, inSameDayAs: Date()))
            }
        case .month:
            HStack(spacing: 4) {
                Picker("", selection: monthBinding) {
                    ForEach(monthRange, id: \.self) { m in
                        Text(Calendar.current.monthSymbols[m-1]).tag(m)
                    }
                }
                .labelsHidden()
                .frame(width: 120)

                Picker("", selection: yearBinding) {
                    ForEach(yearRange, id: \.self) { y in
                        Text(String(format: "%d", y)).tag(y)
                    }
                }
                .labelsHidden()
                .frame(width: 80)
            }
            .frame(minWidth: 200)
        case .year:
            Picker("", selection: yearBinding) {
                ForEach(yearRange, id: \.self) { y in
                    Text(String(format: "%d", y)).tag(y)
                }
            }
            .labelsHidden()
            .frame(width: 100)
        }
    }

    private let dataStore = DataStore.shared

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Period", selection: $period) {
                    ForEach(GraphPeriod.allCases) { p in
                        Text(p.rawValue).tag(p)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()

                Spacer()

                Picker("Graph Type", selection: $selectedRendererType) {
                    ForEach(GraphRendererType.allCases) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .frame(width: 200)
                .padding()

            }
            // Navigation controls
            HStack {

                Spacer()
                
                HStack(spacing: 16) {
                    Button(action: goToPrevious) {
                        Image(systemName: "chevron.left")
                            .foregroundColor(.accentColor)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(isPreviousDisabled)
                    .frame(width: 44, height: 44)

                    periodSelector

                    Button(action: goToNext) {
                        Image(systemName: "chevron.right")
                            .foregroundColor(.accentColor)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(isNextDisabled)
                    .frame(width: 44, height: 44)
                }
                
                Spacer()
            }
            .padding(.horizontal)
            
            VStack(alignment: .leading) {
                Text(selectedRendererType.renderer.caption)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, 70)

                GeometryReader { geo in
                    ZStack(alignment: .bottomLeading) {
                        drawGrid(in: geo.size)
                        drawYAxisLabels(in: geo.size)
                        drawXAxisLabels(in: geo.size)
                        selectedRendererType.renderer.drawGraph(in: geo.size, dataPoints: dataPoints)
                    }
                }
            }
            .padding([.leading, .trailing, .bottom])
        }
        .frame(minWidth: 900, minHeight: 700)
        .onAppear {
            loadEarliestDate()
            loadData()
            setupDatabaseObserver()
        }
        .onChange(of: period) { _, _ in
            selectedDate = Date()
            loadData()
        }
        .onChange(of: selectedRendererType) { _, _ in loadData() }
        .onChange(of: selectedDate) { _, _ in loadData() }
    }

    private func loadEarliestDate() {
        earliestDataDate = dataStore.getEarliestDataDate()
    }
    
    private func setupDatabaseObserver() {
        NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextDidSave,
            object: dataStore.context,
            queue: .main
        ) { _ in
            loadEarliestDate()
        }
    }
    
    private func loadData() {
        let rawValues: [Double]
        let calendar = Calendar.current
        let renderer = selectedRendererType.renderer
        
        switch period {
        case .day:
            rawValues = dataStore.hourlySpend(for: selectedDate)
        case .month:
            rawValues = dataStore.dailySpend(for: selectedDate)
        case .year:
            rawValues = dataStore.monthlySpend(for: selectedDate)
        }
        
        // Determine the current time position to limit data to present
        let currentTimeIndex: Int
        let isCurrentPeriod = calendar.isDate(selectedDate, equalTo: Date(), toGranularity: periodGranularity)
        
        if isCurrentPeriod {
            switch period {
            case .day:
                currentTimeIndex = calendar.component(.hour, from: Date())
            case .month:
                currentTimeIndex = calendar.component(.day, from: Date()) - 1 // 0-based
            case .year:
                currentTimeIndex = calendar.component(.month, from: Date()) - 1 // 0-based
            }
        } else {
            // For past periods, show all data
            currentTimeIndex = rawValues.count - 1
        }
        
        // Only show data up to current time (for current period) or all data (for past periods)
        let limitedValues = Array(rawValues.prefix(currentTimeIndex + 1))

        dataPoints = renderer.transform(
            rawValues: limitedValues,
            labelFor: timeLabel(for:)
        )
    }
    
    private var periodGranularity: Calendar.Component {
        switch period {
        case .day:
            return .day
        case .month:
            return .month
        case .year:
            return .year
        }
    }
    
    
    private var isNextDisabled: Bool {
        let calendar = Calendar.current
        let now = Date()
        
        switch period {
        case .day:
            return calendar.isDate(selectedDate, inSameDayAs: now) || selectedDate > now
        case .month:
            let selectedMonth = calendar.component(.month, from: selectedDate)
            let selectedYear = calendar.component(.year, from: selectedDate)
            let currentMonth = calendar.component(.month, from: now)
            let currentYear = calendar.component(.year, from: now)
            return (selectedYear == currentYear && selectedMonth >= currentMonth) || selectedYear > currentYear
        case .year:
            let selectedYear = calendar.component(.year, from: selectedDate)
            let currentYear = calendar.component(.year, from: now)
            return selectedYear >= currentYear
        }
    }
    
    private var isPreviousDisabled: Bool {
        guard let earliestDataDate = earliestDataDate else {
            return false
        }
        
        let calendar = Calendar.current
        
        switch period {
        case .day:
            return calendar.isDate(selectedDate, inSameDayAs: earliestDataDate) || selectedDate < earliestDataDate
        case .month:
            let selectedMonth = calendar.component(.month, from: selectedDate)
            let selectedYear = calendar.component(.year, from: selectedDate)
            let earliestMonth = calendar.component(.month, from: earliestDataDate)
            let earliestYear = calendar.component(.year, from: earliestDataDate)
            return (selectedYear == earliestYear && selectedMonth <= earliestMonth) || selectedYear < earliestYear
        case .year:
            let selectedYear = calendar.component(.year, from: selectedDate)
            let earliestYear = calendar.component(.year, from: earliestDataDate)
            return selectedYear <= earliestYear
        }
    }
    
    private func goToPrevious() {
        let calendar = Calendar.current
        switch period {
        case .day:
            selectedDate = calendar.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
        case .month:
            selectedDate = calendar.date(byAdding: .month, value: -1, to: selectedDate) ?? selectedDate
        case .year:
            selectedDate = calendar.date(byAdding: .year, value: -1, to: selectedDate) ?? selectedDate
        }
    }
    
    private func goToNext() {
        let calendar = Calendar.current
        switch period {
        case .day:
            selectedDate = calendar.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
        case .month:
            selectedDate = calendar.date(byAdding: .month, value: 1, to: selectedDate) ?? selectedDate
        case .year:
            selectedDate = calendar.date(byAdding: .year, value: 1, to: selectedDate) ?? selectedDate
        }
    }
    
    private func timeLabel(for index: Int) -> String {
        switch period {
        case .day:
            return String(format: "%02d:00", index)
        case .month:
            // For month view, show day of month (1-31)
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
                if x.isFinite {
                    path.move(to: CGPoint(x: x, y: graphArea.minY))
                    path.addLine(to: CGPoint(x: x, y: graphArea.maxY))
                }
            }
        }
        .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)
    }
    
    @ViewBuilder
    private func drawYAxisLabels(in size: CGSize) -> some View {
        let graphArea = CGRect(x: 60, y: 10, width: size.width - 90, height: size.height - 60)
        let maxValue = max(dataPoints.map(\.y).max() ?? 1.0, 0.01)
        
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
                        if x.isFinite {
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
    }
    
    private func shouldShowXLabel(index: Int, total: Int) -> Bool {
        let maxLabels = 8
        if total <= maxLabels { return true }
        let step = max(total / maxLabels, 1)
        return index % step == 0 || index == total - 1
    }

}

#if DEBUG
struct SpendGraphView_Previews: PreviewProvider {
    static var previews: some View {
        SpendGraphView()
    }
}
#endif
