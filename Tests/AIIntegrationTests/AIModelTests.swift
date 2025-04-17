import XCTest
@testable import AIIntegration

final class AIModelTests: XCTestCase {
    
    func testAIModelInitialization() {
        let date = Date()
        let model = AIModel(
            id: "test-model-id",
            name: "Test Model",
            size: 1_000_000_000,
            modified: date
        )
        
        XCTAssertEqual(model.id, "test-model-id")
        XCTAssertEqual(model.name, "Test Model")
        XCTAssertEqual(model.size, 1_000_000_000)
        XCTAssertEqual(model.modified, date)
        XCTAssertFalse(model.capabilities.isCodeCapable)
        XCTAssertFalse(model.capabilities.isMultimodal)
        XCTAssertFalse(model.capabilities.isCommandOptimized)
    }
    
    func testFormattedSize() {
        let model = AIModel(
            id: "test-id",
            name: "Test Model",
            size: 1_500_000_000,
            modified: Date()
        )
        
        XCTAssertTrue(model.formattedSize.contains("GB"), "Large size should be formatted as GB")
        
        let smallModel = AIModel(
            id: "small-id",
            name: "Small Model",
            size: 50_000_000,
            modified: Date()
        )
        
        XCTAssertTrue(smallModel.formattedSize.contains("MB"), "Small size should be formatted as MB")
    }
    
    func testModelTypeDetection() {
        // Test code model detection
        XCTAssertEqual(ModelType.determine(from: "codellama:7b"), .code)
        XCTAssertEqual(ModelType.determine(from: "DeepSeek-coder"), .code)
        XCTAssertEqual(ModelType.determine(from: "llama:13b"), .code)
        
        // Test multimodal model detection
        XCTAssertEqual(ModelType.determine(from: "llama3.2-vision"), .multimodal)
        XCTAssertEqual(ModelType.determine(from: "llava"), .multimodal)
        
        // Test command model detection
        XCTAssertEqual(ModelType.determine(from: "command-llama"), .command)
        XCTAssertEqual(ModelType.determine(from: "terminal-assistant"), .command)
        
        // Test general model detection
        XCTAssertEqual(ModelType.determine(from: "llama3"), .general)
        XCTAssertEqual(ModelType.determine(from: "mistral-small"), .general)
        XCTAssertEqual(ModelType.determine(from: "gemma"), .general)
        
        // Test unknown model detection
        XCTAssertEqual(ModelType.determine(from: "unknown-model"), .unknown)
    }
    
    func testModelEquality() {
        let model1 = AIModel(id: "test-id", name: "Test", size: 1000, modified: Date())
        let model2 = AIModel(id: "test-id", name: "Different Name", size: 2000, modified: Date())
        let model3 = AIModel(id: "different-id", name: "Test", size: 1000, modified: Date())
        
        XCTAssertEqual(model1, model2, "Models with same ID should be equal")
        XCTAssertNotEqual(model1, model3, "Models with different IDs should not be equal")
    }
    
    static var allTests = [
        ("testAIModelInitialization", testAIModelInitialization),
        ("testFormattedSize", testFormattedSize),
        ("testModelTypeDetection", testModelTypeDetection),
        ("testModelEquality", testModelEquality),
    ]
}

