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
    
    /// Mock fetcher that always fails
    private func failingFetcher() -> () async throws -> ModelPricing {
        return {
            throw PricingError.networkError
        }
    }
    
    // MARK: - Tests
    
    /// Test that concurrent requests for the same unknown model result in a single fetch
    func testConcurrentRequestsForSameModel() async {
        let requestsRegistered = expectation(description: "all requests are registered")
        requestsRegistered.expectedFulfillmentCount = 3
        let coordinator = UnknownModelFetchCoordinator(onRequestRegistered: {
            requestsRegistered.fulfill()
        })
        let fetchCallCount = Atomic<Int>(0)
        let fetchStarted = AsyncGate()
        let releaseFetch = AsyncGate()

        let fetcher: () async throws -> ModelPricing = {
            fetchCallCount.increment()
            await fetchStarted.open()
            await releaseFetch.wait()
            return self.mockPricing(withModels: ["claude-new-model"])
        }
        
        // Launch multiple concurrent requests for the same model
        async let result1 = coordinator.requestPricingForUnknownModel("claude-new-model", fetcher: fetcher)
        async let result2 = coordinator.requestPricingForUnknownModel("claude-new-model", fetcher: fetcher)
        async let result3 = coordinator.requestPricingForUnknownModel("claude-new-model", fetcher: fetcher)

        await fetchStarted.wait()
        await fulfillment(of: [requestsRegistered], timeout: 1)
        await releaseFetch.open()

        let results = await [result1, result2, result3]
        
        // All should get the same result
        XCTAssertNotNil(results[0])
        XCTAssertNotNil(results[1])
        XCTAssertNotNil(results[2])
        
        // Should have only fetched once
        XCTAssertEqual(fetchCallCount.value, 1, "Should only fetch once for concurrent requests")
    }

    /// Test that shared fetch completion work is performed once for concurrent requests.
    func testConcurrentRequestsInvokeSharedResolutionHandlerOnce() async {
        let requestsRegistered = expectation(description: "all requests are registered")
        requestsRegistered.expectedFulfillmentCount = 3
        let coordinator = UnknownModelFetchCoordinator(onRequestRegistered: {
            requestsRegistered.fulfill()
        })
        let completionCallCount = Atomic<Int>(0)
        let resolvedModelCount = Atomic<Int>(0)
        let fetchedModelCount = Atomic<Int>(0)
        let fetchStarted = AsyncGate()
        let releaseFetch = AsyncGate()

        let fetcher: () async throws -> ModelPricing = {
            await fetchStarted.open()
            await releaseFetch.wait()
            return self.mockPricing(withModels: ["claude-new-model"])
        }
        let onFetchCompleted: @Sendable (ModelPricing, Set<String>) async -> Void = { pricing, resolvedModels in
            completionCallCount.increment()
            fetchedModelCount.set(pricing.models.count)
            resolvedModelCount.set(resolvedModels.count)
        }

        async let result1 = coordinator.requestPricingForUnknownModel(
            "claude-new-model",
            fetcher: fetcher,
            onFetchCompleted: onFetchCompleted
        )
        async let result2 = coordinator.requestPricingForUnknownModel(
            "claude-new-model",
            fetcher: fetcher,
            onFetchCompleted: onFetchCompleted
        )
        async let result3 = coordinator.requestPricingForUnknownModel(
            "claude-new-model",
            fetcher: fetcher,
            onFetchCompleted: onFetchCompleted
        )

        await fetchStarted.wait()
        await fulfillment(of: [requestsRegistered], timeout: 1)
        await releaseFetch.open()

        let results = await [result1, result2, result3]

        XCTAssertTrue(results.allSatisfy { $0 != nil })
        XCTAssertEqual(completionCallCount.value, 1)
        XCTAssertEqual(fetchedModelCount.value, 1)
        XCTAssertEqual(resolvedModelCount.value, 1)
    }

    /// Test that only one task owns resolution work for a model at a time.
    func testUnknownModelRequestGateDeduplicatesAndCanBeReused() async {
        let gate = UnknownModelRequestGate()

        let acquiredCount = await withTaskGroup(of: Bool.self, returning: Int.self) { group in
            for _ in 0..<100 {
                group.addTask {
                    gate.begin("claude-new-model")
                }
            }

            var count = 0
            for await acquired in group where acquired {
                count += 1
            }
            return count
        }

        XCTAssertEqual(acquiredCount, 1)

        gate.finishForRetry("claude-new-model", after: 60)
        let acquiredDuringRetryWindow = gate.begin("claude-new-model")
        XCTAssertFalse(acquiredDuringRetryWindow)

        gate.finish("claude-new-model")
        let acquiredAfterReset = gate.begin("claude-new-model")
        XCTAssertTrue(acquiredAfterReset)
        gate.finish("claude-new-model")
    }

    /// Test that requests for different unknown models still use a single fetch
    func testMultipleDifferentUnknownModels() async {
        let requestsRegistered = expectation(description: "all requests are registered")
        requestsRegistered.expectedFulfillmentCount = 3
        let coordinator = UnknownModelFetchCoordinator(onRequestRegistered: {
            requestsRegistered.fulfill()
        })
        let fetchCallCount = Atomic<Int>(0)
        let fetchStarted = AsyncGate()
        let releaseFetch = AsyncGate()

        let fetcher: () async throws -> ModelPricing = {
            fetchCallCount.increment()
            await fetchStarted.open()
            await releaseFetch.wait()
            return self.mockPricing(withModels: ["model-1", "model-2", "model-3"])
        }
        
        // Launch requests for different models
        async let result1 = coordinator.requestPricingForUnknownModel("model-1", fetcher: fetcher)
        async let result2 = coordinator.requestPricingForUnknownModel("model-2", fetcher: fetcher)
        async let result3 = coordinator.requestPricingForUnknownModel("model-3", fetcher: fetcher)

        await fetchStarted.wait()
        await fulfillment(of: [requestsRegistered], timeout: 1)
        await releaseFetch.open()

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

    /// Test that a shared refresh reconciles models waiting for resolution.
    func testSharedRefreshReconcilesPendingModels() async {
        let time = Atomic(Date(timeIntervalSince1970: 1_000))
        let coordinator = UnknownModelFetchCoordinator(now: { time.value })
        let fetcher: () async throws -> ModelPricing = {
            self.mockPricing(withModels: [])
        }

        let result = await coordinator.requestPricingForUnknownModel("model-from-scheduled-refresh", fetcher: fetcher)
        XCTAssertNotNil(result)

        time.set(Date(timeIntervalSince1970: 1_060))
        let refreshedPricing = await coordinator.refreshPricing(
            fetcher: { self.mockPricing(withModels: ["model-from-scheduled-refresh"]) }
        )

        XCTAssertNotNil(refreshedPricing)
        let hasPending = await coordinator.hasPendingModels()
        XCTAssertFalse(hasPending)
    }

    /// Test that manual and scheduled refreshes share an in-flight unknown-model fetch.
    func testRefreshJoinsInFlightUnknownModelFetch() async {
        let requestsRegistered = expectation(description: "both refresh requests are registered")
        requestsRegistered.expectedFulfillmentCount = 2
        let coordinator = UnknownModelFetchCoordinator(onRequestRegistered: {
            requestsRegistered.fulfill()
        })
        let unknownFetchStarted = AsyncGate()
        let releaseUnknownFetch = AsyncGate()
        let unknownFetchCount = Atomic<Int>(0)
        let refreshFetchCount = Atomic<Int>(0)
        let completionCount = Atomic<Int>(0)

        let unknownRequest = Task {
            await coordinator.requestPricingForUnknownModel(
                "model-a",
                fetcher: {
                    unknownFetchCount.increment()
                    await unknownFetchStarted.open()
                    await releaseUnknownFetch.wait()
                    return self.mockPricing(withModels: ["model-a"])
                },
                onFetchCompleted: { _, _ in
                    completionCount.increment()
                }
            )
        }

        await unknownFetchStarted.wait()

        let refreshRequest = Task {
            await coordinator.refreshPricing(
                fetcher: {
                    refreshFetchCount.increment()
                    return self.mockPricing(withModels: ["model-a"])
                },
                onFetchCompleted: { _, _ in
                    completionCount.increment()
                }
            )
        }

        await fulfillment(of: [requestsRegistered], timeout: 1)
        await releaseUnknownFetch.open()

        let unknownResult = await unknownRequest.value
        let refreshResult = await refreshRequest.value
        XCTAssertNotNil(unknownResult)
        XCTAssertNotNil(refreshResult)
        XCTAssertEqual(unknownFetchCount.value, 1)
        XCTAssertEqual(refreshFetchCount.value, 0)
        XCTAssertEqual(completionCount.value, 1)
    }

    /// Test that each successful external refresh restarts the unknown-model retry cooldown.
    func testRefreshRestartsCooldownForUnresolvedModels() async {
        let initialTime = Date(timeIntervalSince1970: 1_000)
        let time = Atomic(initialTime)
        let coordinator = UnknownModelFetchCoordinator(now: { time.value })
        let emptyPricing: () async throws -> ModelPricing = {
            self.mockPricing(withModels: [])
        }

        let initialResult = await coordinator.requestPricingForUnknownModel("unresolved-model", fetcher: emptyPricing)
        XCTAssertNotNil(initialResult)

        time.set(initialTime.addingTimeInterval(60))
        let refreshedResult = await coordinator.refreshPricing(fetcher: emptyPricing)
        XCTAssertNotNil(refreshedResult)

        let timeUntilNextFetch = await coordinator.timeUntilNextFetch()
        XCTAssertEqual(timeUntilNextFetch, 60, accuracy: 0.001)
    }

    /// Test that failed external refreshes restart the unknown-model retry cooldown.
    func testFailedRefreshRestartsCooldownForUnresolvedModels() async {
        let initialTime = Date(timeIntervalSince1970: 1_000)
        let time = Atomic(initialTime)
        let coordinator = UnknownModelFetchCoordinator(now: { time.value })
        let emptyPricing: () async throws -> ModelPricing = {
            self.mockPricing(withModels: [])
        }

        let initialResult = await coordinator.requestPricingForUnknownModel("unresolved-model", fetcher: emptyPricing)
        XCTAssertNotNil(initialResult)

        time.set(initialTime.addingTimeInterval(60))
        let refreshedResult = await coordinator.refreshPricing(fetcher: failingFetcher())
        XCTAssertNil(refreshedResult)

        let timeUntilNextFetch = await coordinator.timeUntilNextFetch()
        XCTAssertEqual(timeUntilNextFetch, 60, accuracy: 0.001)
    }

    /// Test that models registered before resolution are included in shared completion work.
    func testEarlyJoinerDoesNotReceiveLateCompletionCallback() async {
        let requestsRegistered = expectation(description: "both models are registered")
        requestsRegistered.expectedFulfillmentCount = 2
        let coordinator = UnknownModelFetchCoordinator(onRequestRegistered: {
            requestsRegistered.fulfill()
        })
        let fetchStarted = AsyncGate()
        let releaseFetch = AsyncGate()
        let lateCompletionCount = Atomic<Int>(0)

        let fetcher: () async throws -> ModelPricing = {
            await fetchStarted.open()
            await releaseFetch.wait()
            return self.mockPricing(withModels: ["model-a", "model-b"])
        }

        let firstRequest = Task {
            await coordinator.requestPricingForUnknownModel("model-a", fetcher: fetcher)
        }

        await fetchStarted.wait()

        let secondRequest = Task {
            await coordinator.requestPricingForUnknownModel(
                "model-b",
                fetcher: fetcher,
                onLateFetchCompleted: { _ in
                    lateCompletionCount.increment()
                }
            )
        }

        await fulfillment(of: [requestsRegistered], timeout: 1)
        await releaseFetch.open()

        let firstResult = await firstRequest.value
        let secondResult = await secondRequest.value

        XCTAssertNotNil(firstResult)
        XCTAssertNotNil(secondResult)
        XCTAssertEqual(lateCompletionCount.value, 0)
    }

    /// Test that models added while shared completion is suspended are reconciled and reported separately.
    func testLateJoinerReceivesResolutionCallback() async {
        let requestsRegistered = expectation(description: "both models are registered")
        requestsRegistered.expectedFulfillmentCount = 2
        let coordinator = UnknownModelFetchCoordinator(onRequestRegistered: {
            requestsRegistered.fulfill()
        })
        let callbackStarted = AsyncGate()
        let releaseCallback = AsyncGate()
        let sharedCallbackCount = Atomic<Int>(0)
        let lateResolvedModels = Atomic<Set<String>>([])

        let fetcher: () async throws -> ModelPricing = {
            self.mockPricing(withModels: ["model-a", "model-b"])
        }

        let firstRequest = Task {
            await coordinator.requestPricingForUnknownModel(
                "model-a",
                fetcher: fetcher,
                onFetchCompleted: { _, resolvedModels in
                    sharedCallbackCount.increment()
                    XCTAssertEqual(resolvedModels, ["model-a"])
                    await callbackStarted.open()
                    await releaseCallback.wait()
                },
                onLateFetchCompleted: { _ in
                    XCTFail("The initial request should not receive a late resolution callback")
                }
            )
        }

        await callbackStarted.wait()

        let lateRequest = Task {
            await coordinator.requestPricingForUnknownModel(
                "model-b",
                fetcher: fetcher,
                onLateFetchCompleted: { resolvedModels in
                    lateResolvedModels.set(resolvedModels)
                }
            )
        }

        await fulfillment(of: [requestsRegistered], timeout: 1)

        await releaseCallback.open()
        let firstResult = await firstRequest.value
        let lateResult = await lateRequest.value
        XCTAssertNotNil(firstResult)
        XCTAssertNotNil(lateResult)
        XCTAssertEqual(sharedCallbackCount.value, 1)
        XCTAssertEqual(lateResolvedModels.value, ["model-b"])
        let hasPending = await coordinator.hasPendingModels()
        XCTAssertFalse(hasPending)
    }

    /// Test that a late joiner missing from the response still completes the fetch lifecycle.
    func testLateUnresolvedJoinerReceivesCompletionCallback() async {
        let requestsRegistered = expectation(description: "both models are registered")
        requestsRegistered.expectedFulfillmentCount = 2
        let coordinator = UnknownModelFetchCoordinator(onRequestRegistered: {
            requestsRegistered.fulfill()
        })
        let callbackStarted = AsyncGate()
        let releaseCallback = AsyncGate()
        let lateCompletionCount = Atomic<Int>(0)
        let lateResolvedModels = Atomic<Set<String>>([])

        let fetcher: () async throws -> ModelPricing = {
            self.mockPricing(withModels: ["model-a"])
        }

        let firstRequest = Task {
            await coordinator.requestPricingForUnknownModel(
                "model-a",
                fetcher: fetcher,
                onFetchCompleted: { _, _ in
                    await callbackStarted.open()
                    await releaseCallback.wait()
                }
            )
        }

        await callbackStarted.wait()

        let lateRequest = Task {
            await coordinator.requestPricingForUnknownModel(
                "model-b",
                fetcher: fetcher,
                onLateFetchCompleted: { resolvedModels in
                    lateCompletionCount.increment()
                    lateResolvedModels.set(resolvedModels)
                }
            )
        }

        await fulfillment(of: [requestsRegistered], timeout: 1)
        await releaseCallback.open()

        let firstResult = await firstRequest.value
        let lateResult = await lateRequest.value
        let hasPendingModels = await coordinator.hasPendingModels()

        XCTAssertNotNil(firstResult)
        XCTAssertNotNil(lateResult)
        XCTAssertEqual(lateCompletionCount.value, 1)
        XCTAssertTrue(lateResolvedModels.value.isEmpty)
        XCTAssertTrue(hasPendingModels)
    }
    
    /// Test the 60-second cooldown between fetches
    func testCooldownBetweenFetches() async {
        let time = Atomic(Date(timeIntervalSince1970: 1_000))
        let coordinator = UnknownModelFetchCoordinator(now: { time.value })
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

    /// Test that a model discovered during a completed refresh's cooldown schedules a retry.
    func testCooldownRequestSchedulesRetry() async {
        let initialTime = Date(timeIntervalSince1970: 1_000)
        let time = Atomic(initialTime)
        let coordinator = UnknownModelFetchCoordinator(now: { time.value })
        let retryScheduledCount = Atomic<Int>(0)
        let initialRefresh = await coordinator.refreshPricing(
            fetcher: { self.mockPricing(withModels: []) }
        )
        XCTAssertNotNil(initialRefresh)

        time.set(initialTime.addingTimeInterval(10))
        let unusedFetcher: () async throws -> ModelPricing = {
            XCTFail("A refresh must not start during the cooldown")
            return self.mockPricing(withModels: [])
        }
        let cooldownRequest = await coordinator.requestPricingForUnknownModel(
            "model-discovered-during-cooldown",
            fetcher: unusedFetcher,
            onRetryRequired: {
                retryScheduledCount.increment()
            }
        )

        XCTAssertNil(cooldownRequest)
        XCTAssertEqual(retryScheduledCount.value, 1)
        let timeUntilNextFetch = await coordinator.timeUntilNextFetch()
        XCTAssertEqual(timeUntilNextFetch, 50, accuracy: 0.001)
    }

    /// Test that a request joining a failed refresh schedules the unknown-model retry.
    func testRequestJoiningFailedRefreshSchedulesRetry() async {
        let requestsRegistered = expectation(description: "refresh and unknown-model request are registered")
        requestsRegistered.expectedFulfillmentCount = 2
        let fixedTime = Date(timeIntervalSince1970: 1_000)
        let coordinator = UnknownModelFetchCoordinator(
            now: { fixedTime },
            onRequestRegistered: {
                requestsRegistered.fulfill()
            }
        )
        let fetchStarted = AsyncGate()
        let releaseFetch = AsyncGate()
        let fetchFailureCount = Atomic<Int>(0)
        let retryRequiredCount = Atomic<Int>(0)

        let refreshTask = Task {
            await coordinator.refreshPricing(
                fetcher: {
                    await fetchStarted.open()
                    await releaseFetch.wait()
                    throw PricingError.networkError
                },
                onFetchFailed: {
                    fetchFailureCount.increment()
                }
            )
        }

        await fetchStarted.wait()
        let joinedRequestTask = Task {
            await coordinator.requestPricingForUnknownModel(
                "model-joining-failed-refresh",
                fetcher: {
                    XCTFail("A joining request must not start another fetch")
                    return self.mockPricing(withModels: [])
                },
                onRetryRequired: {
                    retryRequiredCount.increment()
                }
            )
        }
        await fulfillment(of: [requestsRegistered], timeout: 1)

        await releaseFetch.open()

        let refreshResult = await refreshTask.value
        let joinedRequestResult = await joinedRequestTask.value
        let hasPendingModels = await coordinator.hasPendingModels()

        XCTAssertNil(refreshResult)
        XCTAssertNil(joinedRequestResult)
        XCTAssertEqual(fetchFailureCount.value, 1)
        XCTAssertEqual(retryRequiredCount.value, 1)
        XCTAssertTrue(hasPendingModels)
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
        let requestsRegistered = expectation(description: "all requests are registered")
        requestsRegistered.expectedFulfillmentCount = 3
        let coordinator = UnknownModelFetchCoordinator(onRequestRegistered: {
            requestsRegistered.fulfill()
        })
        let fetchStarted = AsyncGate()
        let releaseFetch = AsyncGate()
        let fetcher: () async throws -> ModelPricing = {
            await fetchStarted.open()
            await releaseFetch.wait()
            return self.mockPricing(withModels: ["model-a", "model-c"])
        }
        
        // Add three models to pending
        async let result1 = coordinator.requestPricingForUnknownModel("model-a", fetcher: fetcher)
        async let result2 = coordinator.requestPricingForUnknownModel("model-b", fetcher: fetcher)
        async let result3 = coordinator.requestPricingForUnknownModel("model-c", fetcher: fetcher)

        await fetchStarted.wait()
        await fulfillment(of: [requestsRegistered], timeout: 1)
        await releaseFetch.open()

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
        let requestsRegistered = expectation(description: "all models are registered")
        requestsRegistered.expectedFulfillmentCount = 5
        let coordinator = UnknownModelFetchCoordinator(onRequestRegistered: {
            requestsRegistered.fulfill()
        })
        let fetchCallCount = Atomic<Int>(0)
        let fetchStarted = AsyncGate()
        let releaseFetch = AsyncGate()
        
        let fetcher: () async throws -> ModelPricing = {
            fetchCallCount.increment()
            await fetchStarted.open()
            await releaseFetch.wait()
            return self.mockPricing(withModels: ["model-1", "model-2", "model-3", "model-4", "model-5"])
        }
        
        // Rapidly fire off requests
        var tasks: [Task<ModelPricing?, Never>] = []
        for i in 1...5 {
            let task = Task {
                await coordinator.requestPricingForUnknownModel("model-\(i)", fetcher: fetcher)
            }
            tasks.append(task)
        }

        await fetchStarted.wait()
        await fulfillment(of: [requestsRegistered], timeout: 1)
        await releaseFetch.open()
        
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
        let initialTime = Date(timeIntervalSince1970: 1_000)
        let time = Atomic(initialTime)
        let coordinator = UnknownModelFetchCoordinator(
            fastRefreshInterval: 0.5,
            now: { time.value }
        )
        let fetchCallCount = Atomic<Int>(0)
        
        let fetcher: () async throws -> ModelPricing = {
            fetchCallCount.increment()
            // Return empty (model not found) to keep it pending
            return self.mockPricing(withModels: [])
        }
        
        // First request
        _ = await coordinator.requestPricingForUnknownModel("test-model", fetcher: fetcher)
        XCTAssertEqual(fetchCallCount.value, 1)
        
        time.set(initialTime.addingTimeInterval(0.6))
        
        // Second request after cooldown
        _ = await coordinator.requestPricingForUnknownModel("test-model", fetcher: fetcher)
        XCTAssertEqual(fetchCallCount.value, 2, "Should fetch again after cooldown expires")
    }
}

// MARK: - Test Helpers

/// Thread-safe counter for testing
private final class Atomic<T>: @unchecked Sendable {
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

private actor AsyncGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen {
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func open() {
        isOpen = true
        let pendingWaiters = waiters
        waiters.removeAll()
        for waiter in pendingWaiters {
            waiter.resume()
        }
    }
}

extension Atomic where T == Int {
    func increment() {
        lock.lock()
        defer { lock.unlock() }
        value_ += 1
    }
}
