import Foundation
import CoreData
import OSLog

/// Singleton managing Core Data persistence for usage entries
class DataStore {
    static let shared = DataStore()

    let context: NSManagedObjectContext

    private let logger = Logger(subsystem: "ClaudeNein", category: "DataStore")

    init(inMemory: Bool = false) {
        if (inMemory) {
            // Use Bundle(for: DataStore.self) to ensure we get the bundle containing the Core Data model
            // This works in both Xcode IDE and command-line test execution
            let bundle = Bundle(for: DataStore.self)
            let model: NSManagedObjectModel
            if let modelURL = bundle.url(forResource: "Model", withExtension: "momd"),
               let explicitModel = NSManagedObjectModel(contentsOf: modelURL) {
                model = explicitModel
            } else if let mergedModel = NSManagedObjectModel.mergedModel(from: [bundle]) {
                model = mergedModel
            } else {
                fatalError("Failed to load Core Data model for in-memory store. Bundle: \(bundle)")
            }
            
            let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
            do {
                try coordinator.addPersistentStore(
                    ofType: NSInMemoryStoreType, configurationName: nil, at: nil, options: nil
                )
            } catch {
                fatalError("Error creating test store: \(error)")
            }
            context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
            context.persistentStoreCoordinator = coordinator
        } else {
            let bundle = Bundle(for: DataStore.self)
            guard let modelURL = bundle.url(forResource: "Model", withExtension: "momd") else {
                let bundleContents = bundle.urls(forResourcesWithExtension: "momd", subdirectory: nil) ?? []
                fatalError("Failed to locate 'Model.momd' in bundle \(bundle). Available .momd files: \(bundleContents)")
            }
            
            guard let model = NSManagedObjectModel(contentsOf: modelURL) else {
                fatalError("Failed to initialize NSManagedObjectModel from valid URL: \(modelURL.absoluteString). Check if the model file is corrupted.")
            }
            
            let container: NSPersistentContainer = NSPersistentContainer(name: "UsageData", managedObjectModel: model)
            
            context = container.viewContext

            container.loadPersistentStores { _, error in
                if let error = error {
                    self.logger.error("Failed to load store: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Insert or update usage entries based on a unique hash
    func upsertEntries(_ entries: [UsageEntry]) async {
        guard !entries.isEmpty else { return }
        
        self.logger.info("📝 Starting upsert of \(entries.count) entries")
        
        await context.perform {
            // Deduplicate incoming entries by their unique hash
            var seenHashes = Set<String>()
            let deduplicatedEntries = entries.compactMap { entry -> UsageEntry? in
                guard let hash = entry.uniqueHash() else { 
                    return entry // Keep entries without hash for later filtering
                }
                if seenHashes.contains(hash) {
                    self.logger.debug("🔄 Skipping duplicate incoming entry with hash: \(hash)")
                    return nil
                }
                seenHashes.insert(hash)
                return entry
            }
            
            // Create unique hashes for deduplicated entries
            let entryHashes = deduplicatedEntries.compactMap { $0.uniqueHash() }
            
            let entriesWithoutHash = deduplicatedEntries.count - entryHashes.count
            if entriesWithoutHash > 0 {
                self.logger.warning("⚠️ \(entriesWithoutHash) entries could not generate unique hashes")
            }
            
            // Fetch existing entries that match these hashes
            let request: NSFetchRequest<UsageEntryEntity> = UsageEntryEntity.fetchRequest()
            request.predicate = NSPredicate(format: "uniqueHash IN %@", entryHashes)
            
            do {
                let existingEntities = try self.context.fetch(request)
                
                // Use Dictionary(_, uniquingKeysWith:) to handle potential duplicates
                let existingEntitiesByHash = Dictionary(existingEntities.compactMap { entity -> (String, UsageEntryEntity)? in
                    guard let hash = entity.uniqueHash else { return nil }
                    return (hash, entity)
                }, uniquingKeysWith: { existing, _ in
                    return existing
                })
                
                for entry in deduplicatedEntries {
                    guard let hash = entry.uniqueHash() else { 
                        self.logger.warning("Skipping entry without uniqueHash: requestId=\(entry.requestId ?? "nil"), originalMessageId=\(entry.originalMessageId ?? "nil")")
                        continue 
                    }
                    
                    // Find an existing entity or create a new one
                    let entity = existingEntitiesByHash[hash] ?? UsageEntryEntity(context: self.context)
                    
                    // Populate entity data from the entry
                    entity.uniqueHash = hash
                    entity.timestamp = entry.timestamp
                    entity.model = entry.model
                    entity.inputTokens = Int64(entry.tokenCounts.input)
                    entity.outputTokens = Int64(entry.tokenCounts.output)
                    
                    // Ensure cost is never nil since Core Data model requires it
                    let calculatedCost = entry.cost ?? PricingManager.shared.calculateCost(for: entry)
                    entity.cost = calculatedCost
                    
                    // Handle cache tokens as Int64 with default value 0 for nil cases
                    entity.cacheCreationTokens = Int64(entry.tokenCounts.cacheCreation ?? 0)
                    entity.cacheReadTokens = Int64(entry.tokenCounts.cacheRead ?? 0)
                    
                    entity.sessionId = entry.sessionId ?? "" // Provide empty string default for nil values
                    entity.projectPath = entry.projectPath ?? "" // Provide empty string default for nil values
                    entity.requestId = entry.requestId ?? "" // Provide empty string default for nil values
                    entity.messageId = entry.originalMessageId ?? "" // Provide empty string default for nil values
                }
                
                // Save if there are any changes
                if self.context.hasChanges {
                    let insertedObjects = self.context.insertedObjects.count
                    let updatedObjects = self.context.updatedObjects.count
                    
                    try self.context.save()
                    self.logger.info("✅ Successfully upserted entries: \(insertedObjects) new, \(updatedObjects) updated")
                }
            } catch {
                self.logger.error("Failed to upsert entries: \(error.localizedDescription)")
                
                // Log detailed validation errors
                let validationError = error as NSError
                self.logger.error("Error code: \(validationError.code)")
                self.logger.error("Error domain: \(validationError.domain)")
                
                if let detailedErrors = validationError.userInfo[NSDetailedErrorsKey] as? [NSError] {
                    for detailError in detailedErrors {
                        self.logger.error("Validation error: \(detailError.localizedDescription)")
                        if let object = detailError.userInfo[NSValidationObjectErrorKey] as? NSManagedObject {
                            self.logger.error("Failed object: \(object)")
                        }
                        if let key = detailError.userInfo[NSValidationKeyErrorKey] as? String {
                            self.logger.error("Failed property: \(key)")
                        }
                    }
                }
                
                // Rollback in case of error to maintain data integrity
                self.context.rollback()
            }
        }
    }
    
    /// Fetch all usage entries from the database
    func fetchAllEntries() -> [UsageEntry] {
        var results: [UsageEntry] = []
        context.performAndWait {
            let request: NSFetchRequest<UsageEntryEntity> = UsageEntryEntity.fetchRequest()

            do {
                let entities = try context.fetch(request)
                results = entities.map { entity in
                    UsageEntry(
                        id: entity.uniqueHash ?? UUID().uuidString,
                        timestamp: entity.timestamp,
                        model: entity.model,
                        tokenCounts: TokenCounts(
                            input: Int(entity.inputTokens),
                            output: Int(entity.outputTokens),
                            cacheCreation: entity.cacheCreationTokens > 0 ? Int(entity.cacheCreationTokens) : nil,
                            cacheRead: entity.cacheReadTokens > 0 ? Int(entity.cacheReadTokens) : nil
                        ),
                        cost: entity.cost,
                        sessionId: entity.sessionId?.isEmpty == true ? nil : entity.sessionId,
                        projectPath: entity.projectPath?.isEmpty == true ? nil : entity.projectPath,
                        requestId: entity.requestId?.isEmpty == true ? nil : entity.requestId,
                        originalMessageId: entity.messageId?.isEmpty == true ? nil : entity.messageId
                    )
                }
            } catch {
                self.logger.error("Failed to fetch all entries: \(error.localizedDescription)")
            }
        }
        return results
    }


    /// Clear all usage entries from the database
    func clearAllEntries() {
        logger.info("🗑️ Starting to clear all usage entries from database")
        
        context.perform {
            let request = NSFetchRequest<NSFetchRequestResult>(entityName: "UsageEntryEntity")
            let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
            
            do {
                let result = try self.context.execute(deleteRequest) as? NSBatchDeleteResult
                let deletedCount = result?.result as? Int ?? 0
                self.logger.info("✅ Successfully deleted \(deletedCount) entries from database")
                
                // Reset the managed object context to reflect the changes
                self.context.reset()
                
            } catch {
                self.logger.error("❌ Failed to clear database: \(error.localizedDescription)")
            }
        }
    }

    /// Calculate spend summary directly in the database using SQL aggregates
    func fetchSpendSummary() -> SpendSummary {
        var summary = SpendSummary()
        context.performAndWait {
            let now = Date()
            let calendar = Calendar.current
            let todayStart = calendar.startOfDay(for: now)
            let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? todayStart
            let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? todayStart
            let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? now

            let todaySpend = sumCost(start: todayStart, end: now)
            let weekSpend = sumCost(start: weekStart, end: now)
            let monthSpend = sumCost(start: monthStart, end: monthEnd)
            let breakdown = modelBreakdown(start: monthStart, end: monthEnd)

            summary = SpendSummary(
                todaySpend: todaySpend,
                weekSpend: weekSpend,
                monthSpend: monthSpend,
                lastUpdated: now,
                modelBreakdown: breakdown
            )
        }
        return summary
    }

    // MARK: - Private query helpers
    private func sumCost(start: Date, end: Date) -> Double {
        let request = NSFetchRequest<NSDictionary>(entityName: "UsageEntryEntity")
        request.resultType = .dictionaryResultType
        request.predicate = NSPredicate(format: "timestamp >= %@ AND timestamp < %@", start as NSDate, end as NSDate)

        let sumExpression = NSExpressionDescription()
        sumExpression.name = "totalCost"
        sumExpression.expression = NSExpression(forFunction: "sum:", arguments: [NSExpression(forKeyPath: "cost")])
        sumExpression.expressionResultType = .doubleAttributeType
        request.propertiesToFetch = [sumExpression]

        let result = try? context.fetch(request).first
        let totalCost = result?["totalCost"] as? Double ?? 0.0
        
        return totalCost
    }

    private func modelBreakdown(start: Date, end: Date) -> [String: Double] {
        let request = NSFetchRequest<NSDictionary>(entityName: "UsageEntryEntity")
        request.resultType = .dictionaryResultType
        request.predicate = NSPredicate(format: "timestamp >= %@ AND timestamp < %@", start as NSDate, end as NSDate)
        request.propertiesToGroupBy = ["model"]

        let sumExpression = NSExpressionDescription()
        sumExpression.name = "totalCost"
        sumExpression.expression = NSExpression(forFunction: "sum:", arguments: [NSExpression(forKeyPath: "cost")])
        sumExpression.expressionResultType = .doubleAttributeType
        request.propertiesToFetch = ["model", sumExpression]

        let results = try? context.fetch(request)
        var breakdown: [String: Double] = [:]
        results?.forEach { row in
            if let model = row["model"] as? String {
                breakdown[model] = row["totalCost"] as? Double ?? 0
            }
        }
        return breakdown
    }

    // MARK: - Historical Spend Aggregation

    /// Hourly spend for a given day (24 values)
    func hourlySpend(for date: Date) -> [Double] {
        var values = Array(repeating: 0.0, count: 24)
        context.performAndWait {
            let cal = Calendar.current
            let startOfDay = cal.startOfDay(for: date)
            for hour in 0..<24 {
                guard let start = cal.date(byAdding: .hour, value: hour, to: startOfDay),
                      let end = cal.date(byAdding: .hour, value: 1, to: start) else { continue }
                values[hour] = sumCost(start: start, end: end)
            }
        }
        return values
    }

    /// Daily spend for the given month
    func dailySpend(for month: Date) -> [Double] {
        var values: [Double] = []
        context.performAndWait {
            let cal = Calendar.current
            guard let range = cal.range(of: .day, in: .month, for: month),
                  let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: month)) else { return }
            values = Array(repeating: 0.0, count: range.count)
            for day in range {
                guard let start = cal.date(byAdding: .day, value: day - 1, to: monthStart),
                      let end = cal.date(byAdding: .day, value: 1, to: start) else { continue }
                values[day - 1] = sumCost(start: start, end: end)
            }
        }
        return values
    }

    /// Monthly spend for the given year
    func monthlySpend(for year: Date) -> [Double] {
        var values = Array(repeating: 0.0, count: 12)
        context.performAndWait {
            let cal = Calendar.current
            guard let yearStart = cal.date(from: cal.dateComponents([.year], from: year)) else { return }
            for monthIndex in 0..<12 {
                guard let start = cal.date(byAdding: .month, value: monthIndex, to: yearStart),
                      let end = cal.date(byAdding: .month, value: 1, to: start) else { continue }
                values[monthIndex] = sumCost(start: start, end: end)
            }
        }
        return values
    }

    // MARK: - Available Date Ranges
    
    /// Get the earliest date with data in the database
    func getEarliestDataDate() -> Date? {
        var earliestDate: Date?
        context.performAndWait {
            let request: NSFetchRequest<UsageEntryEntity> = UsageEntryEntity.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]
            request.fetchLimit = 1
            
            do {
                earliestDate = try context.fetch(request).first?.timestamp
            } catch {
                logger.error("Failed to fetch earliest data date: \(error.localizedDescription)")
            }
        }
        return earliestDate
    }

    // MARK: - Pricing Storage

    /// Save fetched pricing data to Core Data
    func saveModelPricing(_ pricing: ModelPricing) {
        context.perform {
            let fetch = NSFetchRequest<NSFetchRequestResult>(entityName: "ModelPriceEntity")
            let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetch)
            _ = try? self.context.execute(deleteRequest)

            for (name, price) in pricing.models {
                let entity = ModelPriceEntity(context: self.context)
                entity.modelName = name
                entity.inputPrice = price.inputPrice
                entity.outputPrice = price.outputPrice
                entity.cacheCreationPrice = price.cacheCreationPrice ?? 0
                entity.cacheReadPrice = price.cacheReadPrice ?? 0
            }

            if self.context.hasChanges {
                do {
                    try self.context.save()
                    self.logger.info("💾 Saved pricing for \(pricing.models.count) models")
                } catch {
                    self.logger.error("Failed to save pricing: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Load pricing data from Core Data
    func loadModelPricing() -> ModelPricing? {
        var result: ModelPricing?
        context.performAndWait {
            let request: NSFetchRequest<ModelPriceEntity> = ModelPriceEntity.fetchRequest()
            if let entities = try? self.context.fetch(request), !entities.isEmpty {
                var models: [String: ModelPrice] = [:]
                for entity in entities {
                    let price = ModelPrice(
                        inputPrice: entity.inputPrice,
                        outputPrice: entity.outputPrice,
                        cacheCreationPrice: entity.cacheCreationPrice > 0 ? entity.cacheCreationPrice : nil,
                        cacheReadPrice: entity.cacheReadPrice > 0 ? entity.cacheReadPrice : nil
                    )
                    models[entity.modelName] = price
                }
                result = ModelPricing(models: models)
            }
        }
        return result
    }
}

@objc(UsageEntryEntity)
class UsageEntryEntity: NSManagedObject {
    @NSManaged var uniqueHash: String? // New field for deduplication
    @NSManaged var timestamp: Date
    @NSManaged var model: String
    @NSManaged var inputTokens: Int64
    @NSManaged var outputTokens: Int64
    @NSManaged var cacheCreationTokens: Int64
    @NSManaged var cacheReadTokens: Int64
    @NSManaged var cost: Double
    @NSManaged var sessionId: String?
    @NSManaged var projectPath: String?
    @NSManaged var requestId: String?
    @NSManaged var messageId: String?
}

extension UsageEntryEntity {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<UsageEntryEntity> {
        return NSFetchRequest<UsageEntryEntity>(entityName: "UsageEntryEntity")
    }
}

@objc(ModelPriceEntity)
class ModelPriceEntity: NSManagedObject {
    @NSManaged var modelName: String
    @NSManaged var inputPrice: Double
    @NSManaged var outputPrice: Double
    @NSManaged var cacheCreationPrice: Double
    @NSManaged var cacheReadPrice: Double
}

extension ModelPriceEntity {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<ModelPriceEntity> {
        return NSFetchRequest<ModelPriceEntity>(entityName: "ModelPriceEntity")
    }
}
