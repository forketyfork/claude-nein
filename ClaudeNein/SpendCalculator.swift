import Foundation
import OSLog

/// Handles spend aggregation for different time periods
class SpendCalculator {
    private let pricingManager = PricingManager.shared
    private let calendar = Calendar.current
    
    /// Calculate spending summary from usage entries with cost mode support
    func calculateSpendSummary(from entries: [UsageEntry], costMode: CostMode = .auto) -> SpendSummary {
        Logger.calculator.debug("🔢 Calculating spend summary from \(entries.count) entries")
        let now = Date()
        
        // Filter entries by time periods
        let todayEntries = filterEntriesToday(entries, referenceDate: now)
        let weekEntries = filterEntriesThisWeek(entries, referenceDate: now)
        let monthEntries = filterEntriesThisMonth(entries, referenceDate: now)
        
        Logger.calculator.debug("📊 Filtered entries - Today: \(todayEntries.count), Week: \(weekEntries.count), Month: \(monthEntries.count)")
        
        // Calculate costs for each period using the specified cost mode
        let todaySpend = pricingManager.calculateTotalCost(for: todayEntries, mode: costMode)
        let weekSpend = pricingManager.calculateTotalCost(for: weekEntries, mode: costMode)
        let monthSpend = pricingManager.calculateTotalCost(for: monthEntries, mode: costMode)
        
        // Calculate model breakdown for the month
        let modelBreakdown = calculateModelBreakdown(from: monthEntries, costMode: costMode)
        
        Logger.calculator.info("💰 Spend summary - Today: $\(String(format: "%.4f", todaySpend)), Week: $\(String(format: "%.4f", weekSpend)), Month: $\(String(format: "%.4f", monthSpend))")
        
        return SpendSummary(
            todaySpend: todaySpend,
            weekSpend: weekSpend,
            monthSpend: monthSpend,
            lastUpdated: now,
            modelBreakdown: modelBreakdown
        )
    }
    
    /// Calculate daily spend for a specific date with cost mode support
    func calculateDailySpend(from entries: [UsageEntry], for date: Date, costMode: CostMode = .auto) -> Double {
        let dayEntries = filterEntriesForDay(entries, date: date)
        return pricingManager.calculateTotalCost(for: dayEntries, mode: costMode)
    }
    
    /// Calculate spend for a custom date range with cost mode support
    func calculateSpendInRange(from entries: [UsageEntry], startDate: Date, endDate: Date, costMode: CostMode = .auto) -> Double {
        let rangeEntries = entries.filter { entry in
            entry.timestamp >= startDate && entry.timestamp <= endDate
        }
        return pricingManager.calculateTotalCost(for: rangeEntries, mode: costMode)
    }
    
    /// Get spending breakdown by model for given entries with cost mode support
    func calculateModelBreakdown(from entries: [UsageEntry], costMode: CostMode = .auto) -> [String: Double] {
        var breakdown: [String: Double] = [:]
        
        for entry in entries {
            let cost = pricingManager.calculateCost(for: entry, mode: costMode)
            breakdown[entry.model, default: 0.0] += cost
        }
        
        return breakdown
    }
    
    // MARK: - Private Filtering Methods
    
    /// Filter entries for today (current calendar day)
    private func filterEntriesToday(_ entries: [UsageEntry], referenceDate: Date) -> [UsageEntry] {
        return filterEntriesForDay(entries, date: referenceDate)
    }
    
    /// Filter entries for a specific calendar day
    private func filterEntriesForDay(_ entries: [UsageEntry], date: Date) -> [UsageEntry] {
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
        
        return entries.filter { entry in
            entry.timestamp >= startOfDay && entry.timestamp < endOfDay
        }
    }
    
    /// Filter entries for the current calendar week starting from the locale's first weekday
    private func filterEntriesThisWeek(_ entries: [UsageEntry], referenceDate: Date) -> [UsageEntry] {
        guard let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: referenceDate)?.start else {
            return []
        }

        return entries.filter { entry in
            entry.timestamp >= startOfWeek && entry.timestamp <= referenceDate
        }
    }
    
    /// Filter entries for the current calendar month
    private func filterEntriesThisMonth(_ entries: [UsageEntry], referenceDate: Date) -> [UsageEntry] {
        let components = calendar.dateComponents([.year, .month], from: referenceDate)
        guard let startOfMonth = calendar.date(from: components),
              let endOfMonth = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: startOfMonth) else {
            return []
        }
        
        let endOfMonthMidnight = calendar.date(byAdding: .day, value: 1, to: endOfMonth) ?? endOfMonth
        
        return entries.filter { entry in
            entry.timestamp >= startOfMonth && entry.timestamp < endOfMonthMidnight
        }
    }
}

// MARK: - Extension for Formatting

extension SpendSummary {
    /// Format spend amount as currency string
    func formatSpend(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "en_US")
        formatter.currencyCode = "USD"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 4
        
        // Show more precision for small amounts
        if amount < 0.01 {
            formatter.maximumFractionDigits = 6
        }
        
        return formatter.string(from: NSNumber(value: amount)) ?? "$0.00"
    }
    
    /// Get formatted today's spend
    var formattedTodaySpend: String {
        return formatSpend(todaySpend)
    }
    
    /// Get formatted week's spend
    var formattedWeekSpend: String {
        return formatSpend(weekSpend)
    }
    
    /// Get formatted month's spend
    var formattedMonthSpend: String {
        return formatSpend(monthSpend)
    }
    
    /// Get formatted model breakdown
    var formattedModelBreakdown: [(model: String, spend: String)] {
        return modelBreakdown
            .sorted { $0.value > $1.value } // Sort by spend amount descending
            .map { (model: $0.key, spend: formatSpend($0.value)) }
    }
}
