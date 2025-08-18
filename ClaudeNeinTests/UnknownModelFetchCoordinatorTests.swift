import XCTest
@testable import ClaudeNein

class UnknownModelFetchCoordinatorTests: XCTestCase {
    
    // MARK: - Test Helpers
    
    /// Create mock pricing data with specified models
    private func mockPricing(withModels models: [String]) -> ModelPricing {
        var modelPrices: [String: ModelPrice] = [:]
        for model in models {
            modelPrices[model] = ModelPrice(
                inputPrice: 3.0,
                outputPrice: 15.0,
                cacheCreationPrice: 3.75,
                cacheReadPrice: 0.3
            )
        }
        return ModelPricing(models: modelPrices)
    }
    
    /// Mock fetcher that succeeds after a delay
    private func successfulFetcher(withModels models: [String], delay: TimeInterval = 0.1) -> () async throws -> ModelPricing {
        return {
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            return self.mockPricing(withModels: models)
        }
    }
    
    /// Mock fetcher that always fails
    private func failingFetcher() -> () async throws -> ModelPricing {
        return {
            throw PricingError.networkError
        }
    }
    
    // MARK: - Tests
    
    /// Test that concurrent requests for the same unknown model result in a single fetch
    func testConcurrentRequestsForSameModel() async {
        let coordinator = UnknownModelFetchCoordinator()
        let fetchCallCount = Atomic<Int>(0)
        
        let fetcher: () async throws -> ModelPricing = {
            fetchCallCount.increment()
            try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
            return self.mockPricing(withModels: ["claude-new-model"])
        }
        
        // Launch multiple concurrent requests for the same model
        async let result1 = coordinator.requestPricingForUnknownModel("claude-new-model", fetcher: fetcher)
        async let result2 = coordinator.requestPricingForUnknownModel("claude-new-model", fetcher: fetcher)
        async let result3 = coordinator.requestPricingForUnknownModel("claude-new-model", fetcher: fetcher)
        
        let results = await [result1, result2, result3]
        
        // All should get the same result
        XCTAssertNotNil(results[0])
        XCTAssertNotNil(results[1])
        XCTAssertNotNil(results[2])
        
        // Should have only fetched once
        XCTAssertEqual(fetchCallCount.value, 1, "Should only fetch once for concurrent requests")
    }
    
    /// Test that requests for different unknown models still use a single fetch
    func testMultipleDifferentUnknownModels() async {
        let coordinator = UnknownModelFetchCoordinator()
        let fetchCallCount = Atomic<Int>(0)
        
        let fetcher: () async throws -> ModelPricing = {
            fetchCallCount.increment()
            try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
            return self.mockPricing(withModels: ["model-1", "model-2", "model-3"])
        }
        
        // Launch requests for different models
        async let result1 = coordinator.requestPricingForUnknownModel("model-1", fetcher: fetcher)
        async let result2 = coordinator.requestPricingForUnknownModel("model-2", fetcher: fetcher)
        async let result3 = coordinator.requestPricingForUnknownModel("model-3", fetcher: fetcher)
        
        let results = await [result1, result2, result3]
        
        // All should get results
        XCTAssertNotNil(results[0])
        XCTAssertNotNil(results[1])
        XCTAssertNotNil(results[2])
        
        // Should have only fetched once
        XCTAssertEqual(fetchCallCount.value, 1, "Should only fetch once for multiple unknown models")
        
        // Verify pending models were cleared
        let hasPending = await coordinator.hasPendingModels()
        XCTAssertFalse(hasPending, "Should have no pending models after successful fetch")
    }
    
    /// Test the 60-second cooldown between fetches
    func testCooldownBetweenFetches() async {
        let coordinator = UnknownModelFetchCoordinator()
        let fetchCallCount = Atomic<Int>(0)
        
        let fetcher: () async throws -> ModelPricing = {
            fetchCallCount.increment()
            // Return empty pricing (model not found)
            return self.mockPricing(withModels: [])
        }
        
        // First request
        let result1 = await coordinator.requestPricingForUnknownModel("unknown-model", fetcher: fetcher)
        XCTAssertNotNil(result1) // Should attempt fetch
        XCTAssertEqual(fetchCallCount.value, 1)
        
        // Immediate second request (within cooldown)
        let result2 = await coordinator.requestPricingForUnknownModel("unknown-model", fetcher: fetcher)
        XCTAssertNil(result2) // Should return nil due to cooldown
        XCTAssertEqual(fetchCallCount.value, 1, "Should not fetch again within cooldown")
        
        // Check time until next fetch
        let timeUntilNext = await coordinator.timeUntilNextFetch()
        XCTAssertGreaterThan(timeUntilNext, 0, "Should have time remaining in cooldown")
        XCTAssertLessThanOrEqual(timeUntilNext, 60, "Cooldown should be at most 60 seconds")
    }
    
    /// Test that failed fetches don't clear pending models
    func testFailedFetchKeepsPendingModels() async {
        let coordinator = UnknownModelFetchCoordinator()
        
        let failingFetcher: () async throws -> ModelPricing = {
            throw PricingError.networkError
        }
        
        // Request with failing fetcher
        let result = await coordinator.requestPricingForUnknownModel("failing-model", fetcher: failingFetcher)
        XCTAssertNil(result, "Should return nil on fetch failure")
        
        // Model should still be pending
        let hasPending = await coordinator.hasPendingModels()
        XCTAssertTrue(hasPending, "Should still have pending models after failed fetch")
    }
    
    /// Test that resolved models are removed from pending
    func testResolvedModelsRemovedFromPending() async {
        let coordinator = UnknownModelFetchCoordinator()
        
        // Request multiple models
        let fetcher = successfulFetcher(withModels: ["model-a", "model-c"]) // Note: model-b not included
        
        // Add three models to pending
        async let result1 = coordinator.requestPricingForUnknownModel("model-a", fetcher: fetcher)
        async let result2 = coordinator.requestPricingForUnknownModel("model-b", fetcher: fetcher)
        async let result3 = coordinator.requestPricingForUnknownModel("model-c", fetcher: fetcher)
        
        _ = await [result1, result2, result3]
        
        // model-b should still be pending since it wasn't in the response
        let hasPending = await coordinator.hasPendingModels()
        XCTAssertTrue(hasPending, "Should still have model-b pending")
        
        // Manually mark model-b as resolved
        await coordinator.markModelResolved("model-b")
        
        let stillHasPending = await coordinator.hasPendingModels()
        XCTAssertFalse(stillHasPending, "Should have no pending models after marking resolved")
    }
    
    /// Test rapid successive requests with different models
    func testRapidSuccessiveRequests() async {
        let coordinator = UnknownModelFetchCoordinator()
        let fetchCallCount = Atomic<Int>(0)
        
        let fetcher: () async throws -> ModelPricing = {
            fetchCallCount.increment()
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            return self.mockPricing(withModels: ["model-1", "model-2", "model-3", "model-4", "model-5"])
        }
        
        // Rapidly fire off requests
        var tasks: [Task<ModelPricing?, Never>] = []
        for i in 1...5 {
            let task = Task {
                await coordinator.requestPricingForUnknownModel("model-\(i)", fetcher: fetcher)
            }
            tasks.append(task)
            // Small delay between requests to simulate rapid but not simultaneous
            try? await Task.sleep(nanoseconds: 10_000_000) // 0.01 seconds
        }
        
        // Wait for all to complete
        var results: [ModelPricing?] = []
        for task in tasks {
            results.append(await task.value)
        }
        
        // All should have received pricing
        for result in results {
            XCTAssertNotNil(result)
        }
        
        // Should have only fetched once
        XCTAssertEqual(fetchCallCount.value, 1, "Should batch all rapid requests into single fetch")
    }
    
    /// Test that new requests after cooldown trigger new fetch
    func testRequestAfterCooldownTriggersNewFetch() async {
        // Note: This test would need to actually wait 60 seconds or mock time
        // For practical testing, we'll use a modified coordinator with shorter cooldown
        
        // Create a custom coordinator with very short cooldown for testing
        let coordinator = UnknownModelFetchCoordinatorWithCustomCooldown(cooldownSeconds: 0.5)
        let fetchCallCount = Atomic<Int>(0)
        
        let fetcher: () async throws -> ModelPricing = {
            fetchCallCount.increment()
            // Return empty (model not found) to keep it pending
            return self.mockPricing(withModels: [])
        }
        
        // First request
        _ = await coordinator.requestPricingForUnknownModel("test-model", fetcher: fetcher)
        XCTAssertEqual(fetchCallCount.value, 1)
        
        // Wait for cooldown to expire
        try? await Task.sleep(nanoseconds: 600_000_000) // 0.6 seconds
        
        // Second request after cooldown
        _ = await coordinator.requestPricingForUnknownModel("test-model", fetcher: fetcher)
        XCTAssertEqual(fetchCallCount.value, 2, "Should fetch again after cooldown expires")
    }
}

// MARK: - Test Helpers

/// Thread-safe counter for testing
private class Atomic<T> {
    private var value_: T
    private let lock = NSLock()
    
    init(_ value: T) {
        self.value_ = value
    }
    
    var value: T {
        lock.lock()
        defer { lock.unlock() }
        return value_
    }
    
    func set(_ newValue: T) {
        lock.lock()
        defer { lock.unlock() }
        value_ = newValue
    }
}

extension Atomic where T == Int {
    func increment() {
        lock.lock()
        defer { lock.unlock() }
        value_ += 1
    }
}

/// Modified coordinator with configurable cooldown for testing
actor UnknownModelFetchCoordinatorWithCustomCooldown {
    private var pendingUnknownModels = Set<String>()
    private var activeFetchTask: Task<ModelPricing?, Never>?
    private var lastFetchAttempt: Date = .distantPast
    private let fastRefreshInterval: TimeInterval
    
    init(cooldownSeconds: TimeInterval) {
        self.fastRefreshInterval = cooldownSeconds
    }
    
    func requestPricingForUnknownModel(_ modelName: String, fetcher: @escaping () async throws -> ModelPricing) async -> ModelPricing? {
        pendingUnknownModels.insert(modelName)
        
        let now = Date()
        let timeSinceLastFetch = now.timeIntervalSince(lastFetchAttempt)
        
        if activeFetchTask == nil && timeSinceLastFetch >= fastRefreshInterval {
            lastFetchAttempt = now
            
            let fetchTask = Task<ModelPricing?, Never> {
                do {
                    let pricing = try await fetcher()
                    let resolvedModels = pendingUnknownModels.intersection(Set(pricing.models.keys))
                    pendingUnknownModels.subtract(resolvedModels)
                    return pricing
                } catch {
                    return nil
                }
            }
            
            activeFetchTask = fetchTask
            
            Task {
                _ = await fetchTask.value
                self.activeFetchTask = nil
            }
        }
        
        if let fetchTask = activeFetchTask {
            return await fetchTask.value
        }
        
        return nil
    }
}