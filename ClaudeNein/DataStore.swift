import Foundation
import CoreData
import OSLog

/// Singleton managing Core Data persistence for usage entries
class DataStore {
    static let shared = DataStore()

    let container: NSPersistentContainer
    private let logger = Logger(subsystem: "ClaudeNein", category: "DataStore")

    private init(inMemory: Bool = false) {
        let model = DataStore.managedObjectModel()
        container = NSPersistentContainer(name: "UsageData", managedObjectModel: model)

        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }

        container.loadPersistentStores { _, error in
            if let error = error {
                self.logger.error("Failed to load store: \(error.localizedDescription)")
            }
        }
    }

    /// Create the programmatic managed object model
    private static func managedObjectModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()
        let entity = NSEntityDescription()
        entity.name = "UsageEntryEntity"
        entity.managedObjectClassName = NSStringFromClass(UsageEntryEntity.self)

        var properties: [NSAttributeDescription] = []

        let idAttr = NSAttributeDescription()
        idAttr.name = "id"
        idAttr.attributeType = .stringAttributeType
        idAttr.isOptional = false
        properties.append(idAttr)

        let timestampAttr = NSAttributeDescription()
        timestampAttr.name = "timestamp"
        timestampAttr.attributeType = .dateAttributeType
        timestampAttr.isOptional = false
        properties.append(timestampAttr)

        let modelAttr = NSAttributeDescription()
        modelAttr.name = "model"
        modelAttr.attributeType = .stringAttributeType
        modelAttr.isOptional = false
        properties.append(modelAttr)

        let inputTokensAttr = NSAttributeDescription()
        inputTokensAttr.name = "inputTokens"
        inputTokensAttr.attributeType = .integer64AttributeType
        inputTokensAttr.isOptional = false
        properties.append(inputTokensAttr)

        let outputTokensAttr = NSAttributeDescription()
        outputTokensAttr.name = "outputTokens"
        outputTokensAttr.attributeType = .integer64AttributeType
        outputTokensAttr.isOptional = false
        properties.append(outputTokensAttr)

        let cacheCreationAttr = NSAttributeDescription()
        cacheCreationAttr.name = "cacheCreationTokens"
        cacheCreationAttr.attributeType = .integer64AttributeType
        cacheCreationAttr.isOptional = true
        properties.append(cacheCreationAttr)

        let cacheReadAttr = NSAttributeDescription()
        cacheReadAttr.name = "cacheReadTokens"
        cacheReadAttr.attributeType = .integer64AttributeType
        cacheReadAttr.isOptional = true
        properties.append(cacheReadAttr)

        let costAttr = NSAttributeDescription()
        costAttr.name = "cost"
        costAttr.attributeType = .doubleAttributeType
        costAttr.isOptional = true
        properties.append(costAttr)

        let sessionIdAttr = NSAttributeDescription()
        sessionIdAttr.name = "sessionId"
        sessionIdAttr.attributeType = .stringAttributeType
        sessionIdAttr.isOptional = true
        properties.append(sessionIdAttr)

        let projectPathAttr = NSAttributeDescription()
        projectPathAttr.name = "projectPath"
        projectPathAttr.attributeType = .stringAttributeType
        projectPathAttr.isOptional = true
        properties.append(projectPathAttr)

        let requestIdAttr = NSAttributeDescription()
        requestIdAttr.name = "requestId"
        requestIdAttr.attributeType = .stringAttributeType
        requestIdAttr.isOptional = true
        properties.append(requestIdAttr)

        let messageIdAttr = NSAttributeDescription()
        messageIdAttr.name = "messageId"
        messageIdAttr.attributeType = .stringAttributeType
        messageIdAttr.isOptional = true
        properties.append(messageIdAttr)

        entity.properties = properties
        model.entities = [entity]
        return model
    }

    private var context: NSManagedObjectContext {
        container.viewContext
    }

    /// Insert or update usage entries
    func upsertEntries(_ entries: [UsageEntry]) {
        context.perform {
            for entry in entries {
                let request: NSFetchRequest<UsageEntryEntity> = UsageEntryEntity.fetchRequest()
                request.predicate = NSPredicate(format: "id == %@", entry.id)
                request.fetchLimit = 1
                let existing = (try? self.context.fetch(request))?.first
                let obj = existing ?? UsageEntryEntity(context: self.context)

                obj.id = entry.id
                obj.timestamp = entry.timestamp
                obj.model = entry.model
                obj.inputTokens = Int64(entry.tokenCounts.input)
                obj.outputTokens = Int64(entry.tokenCounts.output)
                if let create = entry.tokenCounts.cacheCreation {
                    obj.cacheCreationTokens = NSNumber(value: create)
                } else {
                    obj.cacheCreationTokens = nil
                }
                if let read = entry.tokenCounts.cacheRead {
                    obj.cacheReadTokens = NSNumber(value: read)
                } else {
                    obj.cacheReadTokens = nil
                }
                obj.cost = entry.cost ?? PricingManager.shared.calculateCost(for: entry)
                obj.sessionId = entry.sessionId
                obj.projectPath = entry.projectPath
                obj.requestId = entry.requestId
                obj.messageId = entry.messageId
            }
            if self.context.hasChanges {
                do {
                    try self.context.save()
                } catch {
                    self.logger.error("Failed to save context: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Calculate spend summary directly in the database using SQL aggregates
    func fetchSpendSummary() -> SpendSummary {
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

        return SpendSummary(
            todaySpend: todaySpend,
            weekSpend: weekSpend,
            monthSpend: monthSpend,
            lastUpdated: now,
            modelBreakdown: breakdown
        )
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
        return result?["totalCost"] as? Double ?? 0.0
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
}

@objc(UsageEntryEntity)
class UsageEntryEntity: NSManagedObject {
    @NSManaged var id: String
    @NSManaged var timestamp: Date
    @NSManaged var model: String
    @NSManaged var inputTokens: Int64
    @NSManaged var outputTokens: Int64
    @NSManaged var cacheCreationTokens: NSNumber?
    @NSManaged var cacheReadTokens: NSNumber?
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
