import Foundation

/// Manages pricing data for Claude models and calculates costs
class PricingManager {
    static let shared = PricingManager()
    
    private let userDefaults = UserDefaults.standard
    private let pricingCacheKey = "cached_pricing_data"
    private let pricingCacheTimeKey = "cached_pricing_time"
    private let cacheExpirationHours: Double = 24
    
    private var cachedPricing: ModelPricing?
    
    private init() {
        loadCachedPricing()
    }
    
    /// Fetch pricing data from LiteLLM API with fallback to bundled data
    func fetchPricingData() async throws -> ModelPricing {
        // Try to fetch from API first
        if let apiPricing = try? await fetchPricingFromAPI() {
            cachePricing(apiPricing)
            return apiPricing
        }
        
        // Fallback to bundled pricing data
        return getBundledPricingData()
    }
    
    /// Get current pricing data, using cache if available
    func getCurrentPricing() -> ModelPricing {
        if let cached = cachedPricing, !isCacheExpired() {
            return cached
        }
        
        // Return bundled data as fallback
        return getBundledPricingData()
    }
    
    /// Calculate cost for a usage entry
    func calculateCost(for entry: UsageEntry) -> Double {
        // Use pre-calculated cost if available
        if let precalculatedCost = entry.cost {
            return precalculatedCost
        }
        
        let pricing = getCurrentPricing()
        guard let modelPricing = pricing.models[entry.model] else {
            // Unknown model, use a default rate or return 0
            print("⚠️ Unknown model pricing for: \(entry.model)")
            return 0.0
        }
        
        let inputCost = Double(entry.tokenCounts.input) * modelPricing.inputPrice / 1_000_000
        let outputCost = Double(entry.tokenCounts.output) * modelPricing.outputPrice / 1_000_000
        let cachedCost = Double(entry.tokenCounts.cached ?? 0) * (modelPricing.cachedPrice ?? 0) / 1_000_000
        
        return inputCost + outputCost + cachedCost
    }
    
    /// Calculate costs for multiple entries
    func calculateTotalCost(for entries: [UsageEntry]) -> Double {
        return entries.reduce(0.0) { total, entry in
            total + calculateCost(for: entry)
        }
    }
    
    // MARK: - Private Methods
    
    private func fetchPricingFromAPI() async throws -> ModelPricing {
        guard let url = URL(string: "https://litellm-api.up.railway.app/model_cost") else {
            throw PricingError.invalidURL
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw PricingError.networkError
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] else {
            throw PricingError.decodingError
        }
        
        return convertToModelPricing(from: json)
    }
    
    private func convertToModelPricing(from apiResponse: [String: [String: Any]]) -> ModelPricing {
        var models: [String: ModelPrice] = [:]
        
        for (modelName, pricing) in apiResponse {
            if let inputPrice = pricing["input_cost_per_token"] as? Double,
               let outputPrice = pricing["output_cost_per_token"] as? Double {
                let cachedPrice = pricing["cached_cost_per_token"] as? Double
                
                models[modelName] = ModelPrice(
                    inputPrice: inputPrice * 1_000_000, // Convert to per-million
                    outputPrice: outputPrice * 1_000_000,
                    cachedPrice: cachedPrice != nil ? cachedPrice! * 1_000_000 : nil
                )
            }
        }
        
        return ModelPricing(models: models)
    }
    
    private func getBundledPricingData() -> ModelPricing {
        // Bundled fallback pricing for common Claude models
        let models = [
            "claude-3-5-sonnet-20241022": ModelPrice(inputPrice: 3.0, outputPrice: 15.0, cachedPrice: 0.3),
            "claude-3-5-sonnet-20240620": ModelPrice(inputPrice: 3.0, outputPrice: 15.0, cachedPrice: 0.3),
            "claude-3-5-haiku-20241022": ModelPrice(inputPrice: 0.25, outputPrice: 1.25, cachedPrice: 0.03),
            "claude-3-opus-20240229": ModelPrice(inputPrice: 15.0, outputPrice: 75.0, cachedPrice: 1.5),
            "claude-3-sonnet-20240229": ModelPrice(inputPrice: 3.0, outputPrice: 15.0, cachedPrice: 0.3),
            "claude-3-haiku-20240307": ModelPrice(inputPrice: 0.25, outputPrice: 1.25, cachedPrice: 0.03)
        ]
        
        return ModelPricing(models: models)
    }
    
    private func cachePricing(_ pricing: ModelPricing) {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(pricing)
            userDefaults.set(data, forKey: pricingCacheKey)
            userDefaults.set(Date().timeIntervalSince1970, forKey: pricingCacheTimeKey)
            cachedPricing = pricing
        } catch {
            print("⚠️ Failed to cache pricing data: \(error)")
        }
    }
    
    private func loadCachedPricing() {
        guard let data = userDefaults.data(forKey: pricingCacheKey),
              !isCacheExpired() else {
            return
        }
        
        do {
            let decoder = JSONDecoder()
            cachedPricing = try decoder.decode(ModelPricing.self, from: data)
        } catch {
            print("⚠️ Failed to load cached pricing data: \(error)")
        }
    }
    
    private func isCacheExpired() -> Bool {
        let cacheTime = userDefaults.double(forKey: pricingCacheTimeKey)
        let expirationTime = cacheTime + (cacheExpirationHours * 3600)
        return Date().timeIntervalSince1970 > expirationTime
    }
}

// MARK: - Data Models

struct ModelPricing: Codable {
    let models: [String: ModelPrice]
}

struct ModelPrice: Codable {
    let inputPrice: Double    // Price per million tokens
    let outputPrice: Double   // Price per million tokens
    let cachedPrice: Double?  // Price per million cached tokens
}

// MARK: - API Response Types
// Removed LiteLLMPricingResponse typealias since we handle JSON manually

// MARK: - Errors

enum PricingError: Error {
    case invalidURL
    case networkError
    case decodingError
    case noPricingData
}