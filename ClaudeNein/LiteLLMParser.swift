import Foundation

/// Parses LiteLLM pricing data from JSON format
class LiteLLMParser {
    
    /// Parses LiteLLM JSON data into ModelPricing format
    /// - Parameter jsonData: Raw JSON data containing model pricing information
    /// - Returns: ModelPricing object with parsed pricing data
    /// - Throws: LiteLLMParserError if parsing fails
    func parseModelPricing(from jsonData: Data) throws -> ModelPricing {
        guard let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw LiteLLMParserError.invalidJSONFormat
        }
        
        return parseModelPricing(from: json)
    }
    
    /// Parses LiteLLM JSON dictionary into ModelPricing format
    /// - Parameter jsonDict: Dictionary containing model pricing information
    /// - Returns: ModelPricing object with parsed pricing data
    func parseModelPricing(from jsonDict: [String: Any]) -> ModelPricing {
        var models: [String: ModelPrice] = [:]
        
        for (modelName, modelData) in jsonDict {
            guard let modelConfig = modelData as? [String: Any] else { continue }
            
            if let inputPrice = modelConfig["input_cost_per_token"] as? Double,
               let outputPrice = modelConfig["output_cost_per_token"] as? Double {
                let cacheCreationPrice = modelConfig["cache_creation_input_token_cost"] as? Double
                let cacheReadPrice = modelConfig["cache_read_input_token_cost"] as? Double
                
                models[modelName] = ModelPrice(
                    inputPrice: inputPrice * 1_000_000, // Convert to per-million
                    outputPrice: outputPrice * 1_000_000,
                    cacheCreationPrice: cacheCreationPrice != nil ? cacheCreationPrice! * 1_000_000 : nil,
                    cacheReadPrice: cacheReadPrice != nil ? cacheReadPrice! * 1_000_000 : nil
                )
            }
        }
        
        return ModelPricing(models: models)
    }
}

// MARK: - Errors

enum LiteLLMParserError: Error {
    case invalidJSONFormat
    case missingPricingData
    case invalidModelData
}