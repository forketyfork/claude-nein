import Foundation
import OSLog

/// Manages pricing data for Claude models and calculates costs
class PricingManager {
    static let shared = PricingManager()

    private let userDefaults = UserDefaults.standard
    private let pricingCacheKey = "cached_pricing_data"
    private let pricingCacheTimeKey = "cached_pricing_time"
    private let cacheExpirationHours: Double = 4
    private let refreshIntervalHours: Double = 4
    private var refreshTimer: Timer?
    private let dataStore = DataStore.shared
    private let parser = LiteLLMParser()
    
    private var cachedPricing: ModelPricing?
    private var isInitialFetchComplete = false
    private var dataSource: PricingDataSource = .bundled

    private init() {
        Logger.calculator.debug("🔧 Initializing PricingManager")
        loadCachedPricing()
        if let dbPricing = dataStore.loadModelPricing() {
            cachedPricing = dbPricing
            dataSource = .cache
            Logger.calculator.info("💾 Loaded pricing data from database (\(dbPricing.models.count) models)")
        }
    }
    
    /// Initialize pricing data at app startup
    func initializePricingData() async {
        Logger.calculator.info("🚀 Starting initial pricing data fetch")

        do {
            let pricing = try await fetchPricingFromAPI()
            cachePricing(pricing)
            dataStore.saveModelPricing(pricing)
            dataSource = .api
            Logger.calculator.info("✅ Successfully fetched and cached pricing data from LiteLLM API (\(pricing.models.count) models)")
        } catch {
            Logger.calculator.warning("⚠️ Failed to fetch pricing data from API: \(error.localizedDescription)")
            
            // Try to use cached data if available
            if let cached = cachedPricing, !isCacheExpired() {
                dataSource = .cache
                Logger.calculator.info("💾 Using cached pricing data (\(cached.models.count) models)")
            } else {
                dataSource = .bundled
                Logger.calculator.notice("📦 Falling back to bundled pricing data")
            }
        }
        
        isInitialFetchComplete = true
        Logger.calculator.info("🏁 Initial pricing data setup complete using: \(self.dataSource.description)")
        startRefreshTimer()
    }
    
    /// Get current pricing data, using cache if available
    func getCurrentPricing() -> ModelPricing {
        if let cached = cachedPricing, !isCacheExpired() {
            return cached
        }
        
        // Return bundled data as fallback
        Logger.calculator.debug("📦 Using bundled pricing data as fallback")
        dataSource = .bundled
        return getBundledPricingData()
    }
    
    /// Get information about the current data source
    func getCurrentDataSource() -> PricingDataSource {
        return dataSource
    }
    
    /// Calculate cost for a usage entry with cost mode support
    func calculateCost(for entry: UsageEntry, mode: CostMode = .auto) -> Double {
        switch mode {
        case .display:
            // Always use costUSD, return 0 if not available
            return entry.cost ?? 0.0
            
        case .calculate:
            // Always calculate from tokens, ignore costUSD
            return calculateCostFromTokens(for: entry)
            
        case .auto:
            // Use costUSD when available, calculate otherwise
            if let precalculatedCost = entry.cost {
                return precalculatedCost
            } else {
                return calculateCostFromTokens(for: entry)
            }
        }
    }
    
    /// Calculate cost from token counts with separate cache pricing
    private func calculateCostFromTokens(for entry: UsageEntry) -> Double {
        let pricing = getCurrentPricing()
        guard let modelPricing = pricing.models[entry.model] else {
            // Unknown model, use a default rate or return 0
            Logger.calculator.notice("⚠️ Unknown model pricing for: \(entry.model)")
            return 0.0
        }
        
        let inputCost = Double(entry.tokenCounts.input) * modelPricing.inputPrice / 1_000_000
        let outputCost = Double(entry.tokenCounts.output) * modelPricing.outputPrice / 1_000_000
        
        // Calculate cache costs separately
        let cacheCreationCost = Double(entry.tokenCounts.cacheCreation ?? 0) * (modelPricing.cacheCreationPrice ?? 0) / 1_000_000
        let cacheReadCost = Double(entry.tokenCounts.cacheRead ?? 0) * (modelPricing.cacheReadPrice ?? 0) / 1_000_000
        
        return inputCost + outputCost + cacheCreationCost + cacheReadCost
    }
    
    /// Calculate costs for multiple entries with cost mode support
    func calculateTotalCost(for entries: [UsageEntry], mode: CostMode = .auto) -> Double {
        return entries.reduce(0.0) { total, entry in
            total + calculateCost(for: entry, mode: mode)
        }
    }
    
    // MARK: - Private Methods
    
    private func fetchPricingFromAPI() async throws -> ModelPricing {
        Logger.calculator.debug("🌐 Attempting to fetch pricing data from LiteLLM GitHub")
        
        guard let url = URL(string: "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json") else {
            Logger.calculator.error("❌ Invalid LiteLLM URL")
            throw PricingError.invalidURL
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            Logger.calculator.error("❌ Invalid HTTP response from LiteLLM API")
            throw PricingError.networkError
        }
        
        Logger.calculator.debug("📡 Received HTTP \(httpResponse.statusCode) from LiteLLM API")
        
        guard httpResponse.statusCode == 200 else {
            Logger.calculator.error("❌ HTTP error \(httpResponse.statusCode) from LiteLLM API")
            throw PricingError.networkError
        }
        
        Logger.calculator.debug("📄 Downloaded \(data.count) bytes from LiteLLM API")
        
        do {
            let pricing = try parser.parseModelPricing(from: data)
            Logger.calculator.info("✅ Successfully parsed LiteLLM data: \(pricing.models.count) models")
            return pricing
        } catch {
            Logger.calculator.error("❌ Failed to parse LiteLLM JSON: \(error.localizedDescription)")
            throw PricingError.decodingError
        }
    }
    
    
    private func getBundledPricingData() -> ModelPricing {
        Logger.calculator.debug("📦 Loading bundled pricing data")
        
        // Bundled fallback pricing for common Claude models
        // Based on official Anthropic pricing as of 2025
        let models = [
            "claude-3-5-sonnet-20241022": ModelPrice(inputPrice: 3.0, outputPrice: 15.0, cacheCreationPrice: 3.75, cacheReadPrice: 0.3),
            "claude-3-5-sonnet-20240620": ModelPrice(inputPrice: 3.0, outputPrice: 15.0, cacheCreationPrice: 3.75, cacheReadPrice: 0.3),
            "claude-3-5-haiku-20241022": ModelPrice(inputPrice: 0.8, outputPrice: 4.0, cacheCreationPrice: 1.0, cacheReadPrice: 0.08),
            "claude-3-opus-20240229": ModelPrice(inputPrice: 15.0, outputPrice: 75.0, cacheCreationPrice: 18.75, cacheReadPrice: 1.5),
            "claude-3-sonnet-20240229": ModelPrice(inputPrice: 3.0, outputPrice: 15.0, cacheCreationPrice: 3.75, cacheReadPrice: 0.3),
            "claude-3-haiku-20240307": ModelPrice(inputPrice: 0.25, outputPrice: 1.25, cacheCreationPrice: 0.3, cacheReadPrice: 0.03),
            "claude-sonnet-4-20250514": ModelPrice(inputPrice: 3.0, outputPrice: 15.0, cacheCreationPrice: 3.75, cacheReadPrice: 0.3),
            "claude-opus-4-20250514": ModelPrice(inputPrice: 15.0, outputPrice: 75.0, cacheCreationPrice: 18.75, cacheReadPrice: 1.5)
        ]
        
        Logger.calculator.debug("📦 Loaded bundled data for \(models.count) models")
        return ModelPricing(models: models)
    }
    
    private func cachePricing(_ pricing: ModelPricing) {
        Logger.calculator.debug("💾 Attempting to cache pricing data")
        
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(pricing)
            userDefaults.set(data, forKey: pricingCacheKey)
            userDefaults.set(Date().timeIntervalSince1970, forKey: pricingCacheTimeKey)
            cachedPricing = pricing
            Logger.calculator.info("💾 Successfully cached pricing data (\(pricing.models.count) models)")
        } catch {
            Logger.calculator.error("❌ Failed to cache pricing data: \(error.localizedDescription)")
        }
    }
    
    private func loadCachedPricing() {
        Logger.calculator.debug("🔍 Checking for cached pricing data")
        
        guard let data = userDefaults.data(forKey: pricingCacheKey) else {
            Logger.calculator.debug("📭 No cached pricing data found")
            return
        }
        
        if isCacheExpired() {
            Logger.calculator.debug("⏰ Cached pricing data has expired")
            return
        }
        
        do {
            let decoder = JSONDecoder()
            cachedPricing = try decoder.decode(ModelPricing.self, from: data)
            dataSource = .cache
            Logger.calculator.info("💾 Loaded cached pricing data (\(self.cachedPricing?.models.count ?? 0) models)")
        } catch {
            Logger.calculator.error("❌ Failed to load cached pricing data: \(error.localizedDescription)")
        }
    }
    
    private func isCacheExpired() -> Bool {
        let cacheTime = userDefaults.double(forKey: pricingCacheTimeKey)
        let expirationTime = cacheTime + (cacheExpirationHours * 3600)
        return Date().timeIntervalSince1970 > expirationTime
    }

    private func startRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshIntervalHours * 3600, repeats: true) { [weak self] _ in
            Task {
                await self?.refreshPricing()
            }
        }
    }

    @objc private func refreshPricing() async {
        do {
            let pricing = try await fetchPricingFromAPI()
            cachePricing(pricing)
            dataStore.saveModelPricing(pricing)
            dataSource = .api
            Logger.calculator.info("✅ Refreshed pricing data from API")
        } catch {
            Logger.calculator.warning("⚠️ Scheduled pricing fetch failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Data Models

struct ModelPricing: Codable {
    let models: [String: ModelPrice]
}

struct ModelPrice: Codable {
    let inputPrice: Double           // Price per million tokens
    let outputPrice: Double          // Price per million tokens
    let cacheCreationPrice: Double?  // Price per million cache creation tokens
    let cacheReadPrice: Double?      // Price per million cache read tokens
    
    /// Legacy cached price for backward compatibility (uses cache read price)
    var cachedPrice: Double? {
        return cacheReadPrice
    }
    
    /// Convenience initializer with legacy cached price
    init(inputPrice: Double, outputPrice: Double, cachedPrice: Double?) {
        self.inputPrice = inputPrice
        self.outputPrice = outputPrice
        self.cacheCreationPrice = cachedPrice
        self.cacheReadPrice = cachedPrice
    }
    
    /// Full initializer with separate cache prices
    init(inputPrice: Double, outputPrice: Double, cacheCreationPrice: Double?, cacheReadPrice: Double?) {
        self.inputPrice = inputPrice
        self.outputPrice = outputPrice
        self.cacheCreationPrice = cacheCreationPrice
        self.cacheReadPrice = cacheReadPrice
    }
}

// MARK: - Data Source Tracking

enum PricingDataSource: String, CaseIterable {
    case api = "api"
    case cache = "cache"
    case bundled = "bundled"
    
    var description: String {
        switch self {
        case .api:
            return "LiteLLM API"
        case .cache:
            return "cached data"
        case .bundled:
            return "bundled data"
        }
    }
}

// MARK: - Errors

enum PricingError: Error {
    case invalidURL
    case networkError
    case decodingError
    case noPricingData
}
