import XCTest
@testable import ClaudeNein

final class LiteLLMParserTests: XCTestCase {
    
    var parser: LiteLLMParser!
    
    override func setUp() {
        super.setUp()
        parser = LiteLLMParser()
    }
    
    override func tearDown() {
        parser = nil
        super.tearDown()
    }
    
    func testParseModelPricing() throws {
        // Test data from the user
        let testJSON = """
        {
            "gpt-4.1-mini": {
                "max_tokens": 32768,
                "max_input_tokens": 1047576,
                "max_output_tokens": 32768,
                "input_cost_per_token": 4e-07,
                "output_cost_per_token": 1.6e-06,
                "input_cost_per_token_batches": 2e-07,
                "output_cost_per_token_batches": 8e-07,
                "cache_read_input_token_cost": 1e-07,
                "litellm_provider": "openai",
                "mode": "chat",
                "supported_endpoints": [
                    "/v1/chat/completions",
                    "/v1/batch",
                    "/v1/responses"
                ],
                "supported_modalities": [
                    "text",
                    "image"
                ],
                "supported_output_modalities": [
                    "text"
                ],
                "supports_pdf_input": true,
                "supports_function_calling": true,
                "supports_parallel_function_calling": true,
                "supports_response_schema": true,
                "supports_vision": true,
                "supports_prompt_caching": true,
                "supports_system_messages": true,
                "supports_tool_choice": true,
                "supports_native_streaming": true
            }
        }
        """
        
        let data = testJSON.data(using: .utf8)!
        
        // Parse the JSON
        let result = try parser.parseModelPricing(from: data)
        
        // Verify the result
        XCTAssertEqual(result.models.count, 1)
        
        let modelPrice = result.models["gpt-4.1-mini"]
        XCTAssertNotNil(modelPrice)
        
        // Verify pricing (converted to per-million tokens)
        XCTAssertEqual(modelPrice!.inputPrice, 0.4, accuracy: 0.001) // 4e-07 * 1,000,000
        XCTAssertEqual(modelPrice!.outputPrice, 1.6, accuracy: 0.001) // 1.6e-06 * 1,000,000
        XCTAssertEqual(modelPrice!.cachedPrice!, 0.1, accuracy: 0.001) // 1e-07 * 1,000,000
    }
    
    func testParseModelPricingWithoutCachedPrice() throws {
        let testJSON = """
        {
            "test-model": {
                "input_cost_per_token": 2e-06,
                "output_cost_per_token": 4e-06
            }
        }
        """
        
        let data = testJSON.data(using: .utf8)!
        let result = try parser.parseModelPricing(from: data)
        
        XCTAssertEqual(result.models.count, 1)
        
        let modelPrice = result.models["test-model"]
        XCTAssertNotNil(modelPrice)
        XCTAssertEqual(modelPrice!.inputPrice, 2.0, accuracy: 0.001)
        XCTAssertEqual(modelPrice!.outputPrice, 4.0, accuracy: 0.001)
        XCTAssertNil(modelPrice!.cachedPrice)
    }
    
    func testParseEmptyJSON() throws {
        let testJSON = "{}"
        let data = testJSON.data(using: .utf8)!
        
        let result = try parser.parseModelPricing(from: data)
        
        XCTAssertEqual(result.models.count, 0)
    }
    
    func testParseInvalidJSON() {
        let invalidData = "invalid json".data(using: .utf8)!
        
        XCTAssertThrowsError(try parser.parseModelPricing(from: invalidData))
    }
    
    func testParseModelWithMissingPricing() throws {
        let testJSON = """
        {
            "incomplete-model": {
                "max_tokens": 1000
            },
            "valid-model": {
                "input_cost_per_token": 1e-06,
                "output_cost_per_token": 2e-06
            }
        }
        """
        
        let data = testJSON.data(using: .utf8)!
        let result = try parser.parseModelPricing(from: data)
        
        // Should only parse the valid model
        XCTAssertEqual(result.models.count, 1)
        XCTAssertNotNil(result.models["valid-model"])
        XCTAssertNil(result.models["incomplete-model"])
    }
}