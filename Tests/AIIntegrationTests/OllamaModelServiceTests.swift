import XCTest
@testable import AIIntegration

final class OllamaModelServiceTests: XCTestCase {
    
    func testServiceInitialization() {
        let service = OllamaModelService()
        XCTAssertNotNil(service, "Service should initialize properly")
        
        let customService = OllamaModelService(baseURLString: "http://custom-host:11434")
        XCTAssertNotNil(customService, "Service should initialize with custom URL")
    }
    
    func testPullProgressCalculation() {
        let progress = PullProgress(completed: 500, total: 1000, status: "downloading")
        XCTAssertEqual(progress.progress, 0.5, "Progress calculation should be correct")
        
        let zeroTotalProgress = PullProgress(completed: 100, total: 0, status: "downloading")
        XCTAssertEqual(zeroTotalProgress.progress, 0.0, "Progress should be 0 when total is 0")
        
        let completedProgress = PullProgress(completed: 1000, total: 1000, status: "success")
        XCTAssertEqual(completedProgress.progress, 1.0, "Progress should be 1.0 when completed")
    }
    
    func testOllamaErrorMessages() {
        let modelNotFoundError = OllamaError.modelNotFound
        XCTAssertNotNil(modelNotFoundError.errorDescription, "Error should have a description")
        XCTAssertTrue(modelNotFoundError.errorDescription!.contains("not found"), "Description should mention not found")
        
        let connectionError = OllamaError.connectionFailed
        XCTAssertNotNil(connectionError.errorDescription, "Error should have a description")
        XCTAssertTrue(connectionError.errorDescription!.contains("connect"), "Description should mention connection")
        
        let apiError = OllamaError.apiError("test error")
        XCTAssertNotNil(apiError.errorDescription, "Error should have a description")
        XCTAssertTrue(apiError.errorDescription!.contains("test error"), "Description should include the error message")
        
        let decodingError = OllamaError.decodingError
        XCTAssertNotNil(decodingError.errorDescription, "Error should have a description")
        XCTAssertTrue(decodingError.errorDescription!.contains("decode"), "Description should mention decoding")
    }
    
    static var allTests = [
        ("testServiceInitialization", testServiceInitialization),
        ("testPullProgressCalculation", testPullProgressCalculation),
        ("testOllamaErrorMessages", testOllamaErrorMessages),
    ]
}

