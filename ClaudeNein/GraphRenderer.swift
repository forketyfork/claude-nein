import SwiftUI

/// Represents a single point used for graph rendering
struct DataPoint {
    let x: Int
    let y: Double
    let label: String
}

/// Protocol defining a graph renderer implementation
protocol GraphRenderer: Identifiable where ID == String {
    /// Display name used in the UI picker
    var displayName: String { get }
    /// Caption shown above the graph
    var caption: String { get }
    /// Transform raw values into data points for drawing
    func transform(rawValues: [Double], labelFor: (Int) -> String) -> [DataPoint]
    /// Draw the graph for the provided data points
    func drawGraph(in size: CGSize, dataPoints: [DataPoint]) -> AnyView
}

/// Renders a cumulative line graph
final class CumulativeGraphRenderer: GraphRenderer {
    let id = "cumulative"
    let displayName = "Cumulative"
    let caption = "Cumulative Spend"

    func transform(rawValues: [Double], labelFor: (Int) -> String) -> [DataPoint] {
        var cumulative = 0.0
        return rawValues.enumerated().map { index, value in
            cumulative += value
            return DataPoint(x: index, y: cumulative, label: labelFor(index))
        }
    }

    func drawGraph(in size: CGSize, dataPoints: [DataPoint]) -> AnyView {
        let graphArea = CGRect(x: 60, y: 10, width: size.width - 90, height: size.height - 60)
        return AnyView(
            Group {
                if dataPoints.count > 1 {
                    let maxValue = max(dataPoints.map(\.y).max() ?? 1.0, 0.01)

                    Path { path in
                        for (index, point) in dataPoints.enumerated() {
                            let x = graphArea.minX + CGFloat(point.x) * graphArea.width / CGFloat(max(dataPoints.count - 1, 1))
                            let normalizedY = point.y.isFinite ? point.y / maxValue : 0.0
                            let y = graphArea.maxY - (CGFloat(normalizedY) * graphArea.height)

                            if x.isFinite && y.isFinite {
                                if index == 0 {
                                    path.move(to: CGPoint(x: x, y: y))
                                } else {
                                    path.addLine(to: CGPoint(x: x, y: y))
                                }
                            }
                        }
                    }
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                    ForEach(Array(dataPoints.enumerated()), id: \.offset) { _, point in
                        let x = graphArea.minX + CGFloat(point.x) * graphArea.width / CGFloat(max(dataPoints.count - 1, 1))
                        let normalizedY = point.y.isFinite ? point.y / maxValue : 0.0
                        let y = graphArea.maxY - (CGFloat(normalizedY) * graphArea.height)

                        if x.isFinite && y.isFinite {
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 4, height: 4)
                                .position(x: x, y: y)
                        }
                    }
                }
            }
        )
    }
}

/// Renders a bar graph
final class BarGraphRenderer: GraphRenderer {
    let id = "bar"
    let displayName = "Bar"
    let caption = "Spend"

    func transform(rawValues: [Double], labelFor: (Int) -> String) -> [DataPoint] {
        rawValues.enumerated().map { index, value in
            DataPoint(x: index, y: value, label: labelFor(index))
        }
    }

    func drawGraph(in size: CGSize, dataPoints: [DataPoint]) -> AnyView {
        let graphArea = CGRect(x: 60, y: 10, width: size.width - 90, height: size.height - 60)
        return AnyView(
            Group {
                if !dataPoints.isEmpty {
                    let maxValue = max(dataPoints.map(\.y).max() ?? 1.0, 0.01)
                    let barWidth = graphArea.width / CGFloat(dataPoints.count)

                    ForEach(Array(dataPoints.enumerated()), id: \.offset) { index, point in
                        let height = CGFloat(point.y / maxValue) * graphArea.height
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(width: barWidth * 0.8, height: height)
                            .position(
                                x: graphArea.minX + barWidth * (CGFloat(index) + 0.5),
                                y: graphArea.maxY - height / 2
                            )
                    }
                }
            }
        )
    }
}
