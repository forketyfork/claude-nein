import Foundation
import OSLog

extension Notification.Name {
    static let pricingDataUpdated = Notification.Name("pricingDataUpdated")
}

/// Actor that coordinates fetching of unknown model pricing data
actor UnknownModelFetchCoordinator {
    private struct LateFetchCompletion: Sendable {
        let resolvedModels: Set<String>
        let completion: (@Sendable (Set<String>) async -> Void)?
    }

    private var pendingUnknownModels = Set<String>()
    private var activeFetchTask: Task<ModelPricing?, Never>?
    private var activeFetchPricing: ModelPricing?
    private var pendingLateCompletions = [LateFetchCompletion]()
    private var lastFetchAttempt: Date = .distantPast
    private let fastRefreshInterval: TimeInterval
    private let now: @Sendable () -> Date
    private let onRequestRegistered: (@Sendable () -> Void)?

    init(
        fastRefreshInterval: TimeInterval = 60,
        now: @escaping @Sendable () -> Date = { Date() },
        onRequestRegistered: (@Sendable () -> Void)? = nil
    ) {
        self.fastRefreshInterval = fastRefreshInterval
        self.now = now
        self.onRequestRegistered = onRequestRegistered
    }

    /// Add an unknown model and get pricing if/when available
    func requestPricingForUnknownModel(
        _ modelName: String,
        fetcher: @escaping () async throws -> ModelPricing,
        onFetchCompleted: (@Sendable (ModelPricing, Set<String>) async -> Void)? = nil,
        onLateFetchCompleted: (@Sendable (Set<String>) async -> Void)? = nil,
        onFetchFailed: (@Sendable () async -> Void)? = nil,
        onRetryRequired: (@Sendable () async -> Void)? = nil
    ) async -> ModelPricing? {
        // Add to pending set
        pendingUnknownModels.insert(modelName)
        onRequestRegistered?()
        
        // Check if we should trigger a new fetch
        let requestTime = now()
        let timeSinceLastFetch = requestTime.timeIntervalSince(lastFetchAttempt)
        var startedFetch = false
        
        // If there's no active fetch and cooldown has passed, start a new fetch
        if activeFetchTask == nil && timeSinceLastFetch >= fastRefreshInterval {
            startedFetch = true
            startFetch(
                fetcher: fetcher,
                onFetchCompleted: onFetchCompleted,
                onFetchFailed: onFetchFailed
            )
        }
        
        // Wait for the active fetch task if there is one
        if let fetchTask = activeFetchTask {
            if !startedFetch, let activeFetchPricing {
                let lateResolvedModels = reconcileResolvedModels(in: activeFetchPricing)
                pendingLateCompletions.append(
                    LateFetchCompletion(
                        resolvedModels: lateResolvedModels,
                        completion: onLateFetchCompleted
                    )
                )
            }

            let pricing = await fetchTask.value
            if pricing == nil && !startedFetch {
                await onRetryRequired?()
            }
            return pricing
        }
        
        // No fetch available or in cooldown
        await onRetryRequired?()
        return nil
    }

    /// Fetch current pricing, joining any unknown-model fetch that is already in progress.
    func refreshPricing(
        fetcher: @escaping () async throws -> ModelPricing,
        onFetchCompleted: (@Sendable (ModelPricing, Set<String>) async -> Void)? = nil,
        onFetchFailed: (@Sendable () async -> Void)? = nil
    ) async -> ModelPricing? {
        onRequestRegistered?()

        if activeFetchTask == nil {
            startFetch(
                fetcher: fetcher,
                onFetchCompleted: onFetchCompleted,
                onFetchFailed: onFetchFailed
            )
        }

        guard let activeFetchTask else { return nil }
        return await activeFetchTask.value
    }
    
    /// Check if we have pending unknown models that need pricing
    func hasPendingModels() -> Bool {
        return !pendingUnknownModels.isEmpty
    }

    /// Get the time until next fetch is allowed
    func timeUntilNextFetch() -> TimeInterval {
        let timeSinceLastFetch = now().timeIntervalSince(lastFetchAttempt)
        return max(0, fastRefreshInterval - timeSinceLastFetch)
    }

    /// Reconcile externally fetched pricing with models waiting for resolution.
    func reconcileResolvedModels(in pricing: ModelPricing) -> Set<String> {
        let resolvedModels = pendingUnknownModels.intersection(Set(pricing.models.keys))
        pendingUnknownModels.subtract(resolvedModels)

        if !resolvedModels.isEmpty {
            Logger.calculator.info("✅ Resolved pricing for \(resolvedModels.count) unknown model(s)")
        }

        return resolvedModels
    }
    
    /// Clear a model from pending if it was resolved externally
    func markModelResolved(_ modelName: String) {
        pendingUnknownModels.remove(modelName)
    }

    private func startFetch(
        fetcher: @escaping () async throws -> ModelPricing,
        onFetchCompleted: (@Sendable (ModelPricing, Set<String>) async -> Void)?,
        onFetchFailed: (@Sendable () async -> Void)?
    ) {
        lastFetchAttempt = now()
        activeFetchPricing = nil
        pendingLateCompletions.removeAll()

        activeFetchTask = Task<ModelPricing?, Never> {
            do {
                let pricing = try await fetcher()
                let resolvedModels = reconcileResolvedModels(in: pricing)
                activeFetchPricing = pricing
                await onFetchCompleted?(pricing, resolvedModels)

                while !pendingLateCompletions.isEmpty {
                    let lateCompletions = pendingLateCompletions
                    pendingLateCompletions.removeAll()

                    for lateCompletion in lateCompletions {
                        await lateCompletion.completion?(lateCompletion.resolvedModels)
                    }
                }

                finishActiveFetch()
                return pricing
            } catch {
                Logger.calculator.warning("⚠️ Failed to fetch pricing: \(error.localizedDescription)")
                await onFetchFailed?()

                finishActiveFetch()
                return nil
            }
        }
    }

    private func finishActiveFetch() {
        activeFetchTask = nil
        activeFetchPricing = nil
        pendingLateCompletions.removeAll()
    }
}

/// Prevents duplicate work while pricing for a model is being resolved.
final class UnknownModelRequestGate: @unchecked Sendable {
    private let lock = NSLock()
    private var activeModels = Set<String>()
    private var retryAfter = [String: Date]()

    func begin(_ modelName: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        if let retryDate = retryAfter[modelName] {
            guard Date() >= retryDate else { return false }
            retryAfter.removeValue(forKey: modelName)
        }

        return activeModels.insert(modelName).inserted
    }

    func finish(_ modelName: String) {
        lock.lock()
        defer { lock.unlock() }
        activeModels.remove(modelName)
        retryAfter.removeValue(forKey: modelName)
    }

    func finishForRetry(_ modelName: String, after delay: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        activeModels.remove(modelName)
        retryAfter[modelName] = Date().addingTimeInterval(max(0, delay))
    }
}

/// Manages pricing data for Claude models and calculates costs
/// 
/// This class is marked as `@unchecked Sendable` because:
/// - It's a singleton with controlled access through `shared`
/// - All mutable state is protected by appropriate synchronization:
///   - `cachedPricing`, `dataSource`, `lastFetchDate` are only modified through synchronized methods
///   - `unknownModelCoordinator` is an actor with built-in thread safety
///   - Timer lifecycle is isolated to the main actor
/// - UserDefaults and DataStore have their own thread-safety mechanisms
final class PricingManager: @unchecked Sendable {
    static let shared = PricingManager()

    private let userDefaults = UserDefaults.standard
    private let pricingCacheKey = "cached_pricing_data"
    private let pricingCacheTimeKey = "cached_pricing_time"
    private let cacheExpirationHours: Double = 4
    private let normalRefreshIntervalHours: Double = 4
    private var refreshTimer: Timer?
    private let dataStore = DataStore.shared
    private let parser = LiteLLMParser()
    private let unknownModelCoordinator = UnknownModelFetchCoordinator()
    private let unknownModelRequestGate = UnknownModelRequestGate()
    
    private var cachedPricing: ModelPricing?
    private var isInitialFetchComplete = false
    private var dataSource: PricingDataSource = .bundled
    private(set) var lastFetchDate: Date = .distantPast

    private init() {
        Logger.calculator.debug("🔧 Initializing PricingManager")
        loadCachedPricing()
        // Restore last fetch time from user defaults if available
        let timestamp = userDefaults.double(forKey: pricingCacheTimeKey)
        if timestamp > 0 {
            lastFetchDate = Date(timeIntervalSince1970: timestamp)
        }
        if let dbPricing = dataStore.loadModelPricing() {
            cachedPricing = dbPricing
            dataSource = .cache
            Logger.calculator.info("💾 Loaded pricing data from database (\(dbPricing.models.count) models)")
        }
    }
    
    /// Initialize pricing data at app startup
    func initializePricingData() async {
        Logger.calculator.info("🚀 Starting initial pricing data fetch")

        let pricing = await unknownModelCoordinator.refreshPricing(fetcher: { [weak self] in
            guard let self = self else { throw PricingError.noPricingData }
            return try await self.fetchPricingFromAPI()
        }, onFetchCompleted: { [weak self] pricing, resolvedModels in
            guard let self = self else { return }
            await self.finalizeFetchedPricing(pricing, resolvedModels: resolvedModels)
        })

        if let pricing {
            Logger.calculator.info("✅ Successfully fetched and cached pricing data from LiteLLM API (\(pricing.models.count) models)")
        } else {
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
        if pricing == nil {
            startRefreshTimer()
        }
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

    /// Get the time pricing data was last fetched
    func getLastFetchDate() -> Date {
        return lastFetchDate
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
            // Unknown model, coordinate fetching through the actor
            Logger.calculator.notice("⚠️ Unknown model pricing for: \(entry.model)")

            let modelName = entry.model
            let requestGate = unknownModelRequestGate
            guard requestGate.begin(modelName) else { return 0.0 }

            Task { [weak self, requestGate] in
                guard let self = self else {
                    requestGate.finish(modelName)
                    return
                }

                // Request pricing through the coordinator
                let fetchedPricing = await unknownModelCoordinator.requestPricingForUnknownModel(modelName, fetcher: { [weak self] in
                    guard let self = self else { throw PricingError.noPricingData }
                    return try await self.fetchPricingFromAPI()
                }, onFetchCompleted: { [weak self] pricing, resolvedModels in
                    guard let self = self else { return }
                    await self.finalizeFetchedPricing(pricing, resolvedModels: resolvedModels)
                }, onLateFetchCompleted: { [weak self] resolvedModels in
                    guard let self = self else { return }
                    await self.finalizeLateFetch(resolvedModels)
                }, onFetchFailed: { [weak self] in
                    guard let self = self else { return }
                    await self.scheduleRefreshIfNeeded()
                }, onRetryRequired: { [weak self] in
                    guard let self = self else { return }
                    await self.scheduleRefreshIfNeeded()
                })

                if let fetchedPricing, fetchedPricing.models[modelName] != nil {
                    requestGate.finish(modelName)
                } else {
                    let retryDelay = await unknownModelCoordinator.timeUntilNextFetch()
                    requestGate.finishForRetry(modelName, after: retryDelay)
                }
            }
            
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
            let now = Date()
            userDefaults.set(now.timeIntervalSince1970, forKey: pricingCacheTimeKey)
            lastFetchDate = now
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
            let timestamp = userDefaults.double(forKey: pricingCacheTimeKey)
            if timestamp > 0 {
                lastFetchDate = Date(timeIntervalSince1970: timestamp)
            }
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
        Task {
            await scheduleRefreshIfNeeded()
        }
    }
    
    /// Schedule refresh based on whether we have pending unknown models
    private func scheduleRefreshIfNeeded() async {
        let hasPending = await unknownModelCoordinator.hasPendingModels()
        let interval: TimeInterval
        
        if hasPending {
            // Fast refresh mode for unknown models
            let timeUntilNext = await unknownModelCoordinator.timeUntilNextFetch()
            interval = max(timeUntilNext, 1.0) // At least 1 second
            Logger.calculator.info("⚡ Scheduling fast refresh in \(Int(interval)) seconds for unknown models")
        } else {
            // Normal refresh mode
            interval = normalRefreshIntervalHours * 3600
            Logger.calculator.info("⏰ Scheduling normal refresh in \(self.normalRefreshIntervalHours) hours")
        }
        await installRefreshTimer(after: interval)
    }

    @MainActor
    private func installRefreshTimer(after interval: TimeInterval) {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                await self.refreshPricing()
            }
        }
    }

    /// Manually trigger a pricing refresh
    func refreshPricingNow() async {
        await refreshPricing()
    }

    @objc private func refreshPricing() async {
        _ = await unknownModelCoordinator.refreshPricing(fetcher: { [weak self] in
            guard let self = self else { throw PricingError.noPricingData }
            return try await self.fetchPricingFromAPI()
        }, onFetchCompleted: { [weak self] pricing, resolvedModels in
            guard let self = self else { return }
            await self.finalizeFetchedPricing(pricing, resolvedModels: resolvedModels)
        }, onFetchFailed: { [weak self] in
            guard let self = self else { return }
            await self.scheduleRefreshIfNeeded()
        })
    }

    private func finalizeFetchedPricing(_ pricing: ModelPricing, resolvedModels: Set<String>) async {
        cachePricing(pricing)
        dataStore.saveModelPricing(pricing)
        dataSource = .api
        Logger.calculator.info("✅ Refreshed pricing data from API")

        await finalizeModelResolution(resolvedModels, notify: true)
    }

    private func finalizeLateFetch(_ resolvedModels: Set<String>) async {
        await finalizeModelResolution(resolvedModels, notify: !resolvedModels.isEmpty)
    }

    private func finalizeModelResolution(_ resolvedModels: Set<String>, notify: Bool) async {
        await applyResolvedModels(resolvedModels)

        if notify {
            NotificationCenter.default.post(name: .pricingDataUpdated, object: nil)
        }

        await scheduleRefreshIfNeeded()
    }

    private func applyResolvedModels(_ resolvedModels: Set<String>) async {
        for modelName in resolvedModels {
            await recalculateCostsForModel(modelName)
        }
    }
    
    
    /// Recalculate costs for all entries with a specific model using efficient batch processing
    private func recalculateCostsForModel(_ modelName: String) async {
        Logger.calculator.info("💰 Recalculating costs for model: \(modelName)")
        
        // Process entries in batches using the cursor approach
        await dataStore.processEntriesForModel(modelName, batchSize: 100) { [weak self] entries in
            guard let self = self else { return entries }
            
            // Recalculate costs for this batch
            return entries.map { entry in
                let newCost = self.calculateCostFromTokens(for: entry)
                return UsageEntry(
                    id: entry.id,
                    timestamp: entry.timestamp,
                    model: entry.model,
                    tokenCounts: entry.tokenCounts,
                    cost: newCost,
                    sessionId: entry.sessionId,
                    projectPath: entry.projectPath,
                    requestId: entry.requestId,
                    originalMessageId: entry.originalMessageId
                )
            }
        }
        
        Logger.calculator.info("✅ Completed batch processing for model \(modelName)")
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
