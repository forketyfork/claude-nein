import Foundation

/// Handles spend aggregation for different time periods
class SpendCalculator {
    private let pricingManager = PricingManager.shared
    private let calendar = Calendar.current
    
    /// Calculate spending summary from usage entries
    func calculateSpendSummary(from entries: [UsageEntry]) -> SpendSummary {
        let now = Date()
        
        // Filter entries by time periods
        let todayEntries = filterEntriesToday(entries, referenceDate: now)
        let weekEntries = filterEntriesLastWeek(entries, referenceDate: now)
        let monthEntries = filterEntriesThisMonth(entries, referenceDate: now)
        
        // Calculate costs for each period
        let todaySpend = pricingManager.calculateTotalCost(for: todayEntries)
        let weekSpend = pricingManager.calculateTotalCost(for: weekEntries)
        let monthSpend = pricingManager.calculateTotalCost(for: monthEntries)
        
        // Calculate model breakdown for the month
        let modelBreakdown = calculateModelBreakdown(from: monthEntries)
        
        return SpendSummary(
            todaySpend: todaySpend,
            weekSpend: weekSpend,
            monthSpend: monthSpend,
            lastUpdated: now,
            modelBreakdown: modelBreakdown
        )
    }
    
    /// Calculate daily spend for a specific date
    func calculateDailySpend(from entries: [UsageEntry], for date: Date) -> Double {
        let dayEntries = filterEntriesForDay(entries, date: date)
        return pricingManager.calculateTotalCost(for: dayEntries)
    }
    
    /// Calculate spend for a custom date range
    func calculateSpendInRange(from entries: [UsageEntry], startDate: Date, endDate: Date) -> Double {
        let rangeEntries = entries.filter { entry in
            entry.timestamp >= startDate && entry.timestamp <= endDate
        }
        return pricingManager.calculateTotalCost(for: rangeEntries)
    }
    
    /// Get spending breakdown by model for given entries
    func calculateModelBreakdown(from entries: [UsageEntry]) -> [String: Double] {
        var breakdown: [String: Double] = [:]
        
        for entry in entries {
            let cost = pricingManager.calculateCost(for: entry)
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
    
    /// Filter entries for the last 7 days (not including today)
    private func filterEntriesLastWeek(_ entries: [UsageEntry], referenceDate: Date) -> [UsageEntry] {
        guard let weekAgo = calendar.date(byAdding: .day, value: -7, to: referenceDate) else {
            return []
        }
        
        return entries.filter { entry in
            entry.timestamp >= weekAgo && entry.timestamp <= referenceDate
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