import XCTest
import Alamofire
@testable import AIIntegration

class OllamaModelServiceTests: XCTestCase {
    
    // MARK: - Mock Setup
    
    /// Mock Session implementation for testing with controlled responses
    class MockSession: Session {
        var mockResponse: Data?
        var mockError: Error?
        var requestsReceived: [(url: URL, method: HTTPMethod, parameters: [String: Any]?)] = []
        
        /// Captures requests and returns mock responses for RequestInterceptor
        class MockInterceptor: RequestInterceptor {
            var session: MockSession
            
            init(session: MockSession) {
                self.session = session
            }
            
            func adapt(_ urlRequest: URLRequest, for session: Session, completion: @escaping (Result<URLRequest, Error>) -> Void) {
                // Capture the request details
                if let url = urlRequest.url, 
                   let method = urlRequest.method {
                    var parameters: [String: Any]?
                    if let httpBody = urlRequest.httpBody {
                        parameters = try? JSONSerialization.jsonObject(with: httpBody) as? [String: Any]
                    }
                    session.requestsReceived.append((url: url, method: method, parameters: parameters))
                }
                
                completion(.success(urlRequest))
            }
        }
        
        override func request(_ convertible: URLConvertible,
                              method: HTTPMethod = .get,
                              parameters: Parameters? = nil,
                              encoding: ParameterEncoding = URLEncoding.default,
                              headers: HTTPHeaders? = nil,
                              interceptor: RequestInterceptor? = nil,
                              requestModifier: RequestModifier? = nil) -> DataRequest {
            
            // Create a custom URLRequest
            guard let url = try? convertible.asURL() else {
                return super.request(convertible, method: method, parameters: parameters)
            }
            
            // Store the request
            requestsReceived.append((url: url, method: method, parameters: parameters))
            
            return MockDataRequest(session: self, url: url, method: method)
        }
        
        /// Mock DataRequest for testing
        class MockDataRequest: DataRequest {
            var session: MockSession
            var requestURL: URL
            var requestMethod: HTTPMethod
            
            init(session: MockSession, url: URL, method: HTTPMethod) {
                self.session = session
                self.requestURL = url
                self.requestMethod = method
                super.init(convertible: url, underlyingQueue: .main)
            }
            
            override func validate() -> Self {
                return self
            }
            
            override func serializingDecodable<T: Decodable>(_ type: T.Type = T.self, decoder: DataDecoder = JSONDecoder()) -> DataTask<T> {
                // If there's an error, send that instead
                if let error = session.mockError {
                    let task = DataTask<T>(request: self, rootQueue: .main, serializationQueue: .main, eventMonitor: nil)
                    task.didCreateTask()
                    task.finish(error: error)
                    return task
                }
                
                // Otherwise, try to create a response from the mock data
                guard let data = session.mockResponse else {
                    let task = DataTask<T>(request: self, rootQueue: .main, serializationQueue: .main, eventMonitor: nil)
                    task.didCreateTask()
                    task.finish(error: AFError.responseSerializationFailed(reason: .inputDataNilOrZeroLength))
                    return task
                }
                
                let task = DataTask<T>(request: self, rootQueue: .main, serializationQueue: .main, eventMonitor: nil)
                task.didCreateTask()
                
                do {
                    let decoded = try decoder.decode(T.self, from: data)
                    task.finish(value: decoded)
                } catch {
                    task.finish(error: AFError.responseSerializationFailed(reason: .decodingFailed(error: error)))
                }
                
                return task
            }
        }
    }
    
    // MARK: - Test Data
    
    /// Sample model data for testing
    private func createSampleModels() -> [OllamaModel] {
        return [
            OllamaModel(name: "llama3:8b", digest: "sha256:abc123", modifiedAt: "2023-04-24T12:00:00Z", size: 8000000000),
            OllamaModel(name: "dolphin-llama:latest", digest: "sha256:def456", modifiedAt: "2023-04-23T12:00:00Z", size: 6000000000),
            OllamaModel(name: "codellama:13b", digest: "sha256:ghi789", modifiedAt: "2023-04-22T12:00:00Z", size: 13000000000),
            OllamaModel(name: "mistral:7b-instruct", digest: "sha256:jkl012", modifiedAt: "2023-04-21T12:00:00Z", size: 7000000000),
            OllamaModel(name: "phi3:mini", digest: "sha256:mno345", modifiedAt: "2023-04-20T12:00:00Z", size: 3000000000)
        ]
    }
    
    /// Creates a model list response for testing
    private func createModelListResponse() -> Data {
        let response = OllamaListResponse(models: createSampleModels())
        return try! JSONEncoder().encode(response)
    }
    
    /// Creates a completion response for testing
    private func createCompletionResponse(content: String) -> Data {
        let response = ["response": content, "done": true] as [String: Any]
        return try! JSONSerialization.data(withJSONObject: response)
    }
    
    // MARK: - Tests for Model Capability Detection
    
    func testEnhancedModelCapabilityDetection() async throws {
        // Set up the mock session
        let mockSession = MockSession()
        
        // Provide mock responses for model list and capability testing
        mockSession.mockResponse = createModelListResponse()
        
        // Create the service with the mock session
        let service = OllamaModelService(baseURLString: "http://localhost:11434", session: mockSession)
        
        // Prepare mock responses for capability testing
        let codeTestPrompt = "Write a simple function that calculates the factorial of a number in Swift."
        let codeResponse = """
        ```swift
        func factorial(_ n: Int) -> Int {
            if n <= 1 {
                return 1
            }
            return n * factorial(n - 1)
        }
        ```
        """
        
        let commandTestPrompt = "How do I list all files in a directory, including hidden ones, with detailed information?"
        let commandResponse = "To list all files including hidden ones with detailed information, use `ls -la`."
        
        // Set the next mock response for capability tests
        mockSession.mockResponse = createCompletionResponse(content: codeResponse)
        
        // Get the models and verify the enhanced capabilities are detected
        let models = try await service.listModels(forceRefresh: true)
        
        // Update mock for the next capability test
        mockSession.mockResponse = createCompletionResponse(content: commandResponse)
        
        // Verify we got the expected number of models
        XCTAssertEqual(models.count, createSampleModels().count)
        
        // Check that model capabilities were detected according to model names
        let codellama = models.first { $0.name == "codellama:13b" }
        XCTAssertNotNil(codellama, "Code model should be found")
        XCTAssertTrue(codellama?.capabilities.isCodeCapable ?? false, "Code model should be detected as code-capable")
        
        // Check detection of llama3 capabilities
        let llama3 = models.first { $0.name == "llama3:8b" }
        XCTAssertNotNil(llama3, "Llama3 model should be found")
        
        // Check detection of mistral capabilities 
        let mistral = models.first { $0.name == "mistral:7b-instruct" }
        XCTAssertNotNil(mistral, "Mistral model should be found")
    }
    
    // MARK: - Tests for Parameter Tuning
    
    func testParameterTuningAndOptimization() async throws {
        // Set up the mock session
        let mockSession = MockSession()
        mockSession.mockResponse = createModelListResponse()
        
        // Create the service with the mock session
        let service = OllamaModelService(baseURLString: "http://localhost:11434", session: mockSession)
        
        // Get the models to initialize the cache
        _ = try await service.listModels(forceRefresh: true)
        
        // Now test parameter tuning for different task types
        let codeParameters = await service.getOptimalParameters(for: "codellama:13b", taskType: .code)
        let commandParameters = await service.getOptimalParameters(for: "mistral:7b-instruct", taskType: .command)
        let generalParameters = await service.getOptimalParameters(for: "llama3:8b", taskType: .general)
        
        // Verify we get task-specific parameters
        XCTAssertLessThan(codeParameters.temperature, 0.5, "Code tasks should have lower temperature")
        XCTAssertLessThan(commandParameters.temperature, 0.5, "Command tasks should have moderate temperature")
        XCTAssertGreaterThanOrEqual(generalParameters.temperature, 0.5, "General tasks should have higher temperature")
        
        // Verify token limits are appropriate
        XCTAssertGreaterThan(codeParameters.maxTokens, 2000, "Code tasks should allow for longer outputs")
        XCTAssertLessThan(commandParameters.maxTokens, 2000, "Command tasks should be more concise")
    }
    
    // MARK: - Tests for Token Limit Detection
    
    func testTokenLimitDetection() async throws {
        // Create a service with a mock session
        let mockSession = MockSession()
        let service = OllamaModelService(baseURLString: "http://localhost:11434", session: mockSession)
        
        // Use reflection to access private method for testing
        let mirror = Mirror(reflecting: service)
        
        // Make sure we can access the private method
        guard let detectTokenLimitMethod = mirror.children.first(where: { $0.label == "detectTokenLimit" }) else {
            XCTFail("Could not find detectTokenLimit method")
            return
        }
        
        // Test token limit detection for different model names
        let llama3_32k = try await (service.detectTokenLimit(modelName: "llama3:32k") as Any) as? Int
        XCTAssertEqual(llama3_32k, 32000, "Should detect 32k context")
        
        let llama3_70b = try await (service.detectTokenLimit(modelName: "llama3:70b") as Any) as? Int
        XCTAssertEqual(llama3_70b, 8192, "Should detect llama3:70b context")
        
        let mistral = try await (service.detectTokenLimit(modelName: "mistral:7b") as Any) as? Int
        XCTAssertEqual(mistral, 8192, "Should detect mistral context")
        
        let phi3 = try await (service.detectTokenLimit(modelName: "phi:3") as Any) as? Int
        XCTAssertEqual(phi3, 2048, "Should detect phi context")
        
        let unknown = try await (service.detectTokenLimit(modelName: "unknown-model") as Any) as? Int
        XCTAssertEqual(unknown, 4096, "Should use default context for unknown models")
    }
    
    // MARK: - Tests for Error Handling
    
    func testErrorHandlingAndRecovery() async throws {
        // Set up the mock session with an error
        let mockSession = MockSession()
        mockSession.mockError = NSError(domain: "test", code: -1009, userInfo: [NSLocalizedDescriptionKey: "The Internet connection appears to be offline."])
        
        // Create the service with the mock session
        let service = OllamaModelService(baseURLString: "http://localhost:11434", session: mockSession)
        
        // Attempt to list models and expect failure
        do {
            _ = try await service.listModels(forceRefresh: true)
            XCTFail("Should have thrown an error")
        } catch let error as OllamaError {
            // Verify the error is properly translated
            XCTAssertEqual(error, OllamaError.connectionFailed, "Should translate to connection failed error")
        }
        
        // Now simulate recovery by providing a valid response
        mockSession.mockError = nil
        mockSession.mockResponse = createModelListResponse()
        
        // Now we should be able to get models
        let models = try await service.listModels(forceRefresh: true)
        XCTAssertEqual(models.count, createSampleModels().count, "Should recover and get models")
    }
    
    // MARK: - Tests for Caching Behavior
    
    func testCachingBehavior() async throws {
        // Set up the mock session
        let mockSession = MockSession()
        mockSession.mockResponse = createModelListResponse()
        
        // Create the service with the mock session
        let service = OllamaModelService(baseURLString: "http://localhost:11434", session: mockSession)
        
        // First request should hit the network
        let initialModels = try await service.listModels()
        XCTAssertEqual(initialModels.count, createSampleModels().count)
        XCTAssertEqual(mockSession.requestsReceived.count, 1, "Should make one network request")
        
        // Reset the request count
        mockSession.requestsReceived = []
        
        // Second request should use cache
        let cachedModels = try await service.listModels()
        XCTAssertEqual(cachedModels.count, createSampleModels().count)
        
        // When using cache, we still make a request to get updated info but use cached capabilities
        XCTAssertEqual(mockSession.requestsReceived.count, 1, "Should make one network request to refresh metadata")
        
        // Force refresh should always hit the network
        mockSession.requestsReceived = []
        let forcedModels = try await service.listModels(forceRefresh: true)
        XCTAssertEqual(forcedModels.count, createSampleModels().count)
        XCTAssertEqual(mockSession.requestsReceived.count, 1, "Should make one network request for forced refresh")
    }
    
    // MARK: - Tests for Model Suggestion
    
    func testModelSuggestionByTaskType() async throws {
        // Set up the mock session
        let mockSession = MockSession()
        mockSession.mockResponse = createModel

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

