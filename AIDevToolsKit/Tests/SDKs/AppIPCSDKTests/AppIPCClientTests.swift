import AppIPCSDK
import Foundation
import Testing

@Suite("AppIPCClient")
struct AppIPCClientTests {

    // MARK: - IPCRequest Codable

    @Test("IPCRequest encodes and decodes query field")
    func ipcRequestRoundtrip() throws {
        let request = IPCRequest(query: "getUIState")
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(IPCRequest.self, from: data)
        #expect(decoded.query == "getUIState")
    }

    @Test("IPCRequest encodes to expected JSON keys")
    func ipcRequestJSONKeys() throws {
        let request = IPCRequest(query: "getUIState")
        let data = try JSONEncoder().encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: String]
        #expect(json?["query"] == "getUIState")
    }

    // MARK: - IPCUIState Codable

    @Test("IPCUIState decodes plan name and tab from JSON")
    func ipcUIStateWithValues() throws {
        let json = #"{"selectedPlanName":"MyPlan","currentTab":"plans"}"#.data(using: .utf8)!
        let state = try JSONDecoder().decode(IPCUIState.self, from: json)
        #expect(state.selectedPlanName == "MyPlan")
        #expect(state.currentTab == "plans")
    }

    @Test("IPCUIState decodes null fields as nil")
    func ipcUIStateNilFields() throws {
        let json = #"{"selectedPlanName":null,"currentTab":null}"#.data(using: .utf8)!
        let state = try JSONDecoder().decode(IPCUIState.self, from: json)
        #expect(state.selectedPlanName == nil)
        #expect(state.currentTab == nil)
    }

    @Test("IPCUIState encodes optional fields correctly")
    func ipcUIStateRoundtrip() throws {
        let state = IPCUIState(selectedPlanName: "TestPlan", currentTab: "evals")
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(IPCUIState.self, from: data)
        #expect(decoded.selectedPlanName == "TestPlan")
        #expect(decoded.currentTab == "evals")
    }

    // MARK: - AppIPCClient behavior

    @Test("getUIState throws appNotRunning when socket file is absent")
    func getUIStateThrowsWhenSocketAbsent() async throws {
        let socketPath = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AIDevTools/app.sock")
            .path
        guard !FileManager.default.fileExists(atPath: socketPath) else {
            return  // App is running — skip this case
        }
        let client = AppIPCClient()
        await #expect {
            _ = try await client.getUIState()
        } throws: { error in
            guard let ipcError = error as? IPCError else { return false }
            if case .appNotRunning = ipcError { return true }
            return false
        }
    }

    // MARK: - IPCError descriptions

    @Test("appNotRunning error description mentions AIDevTools app")
    func appNotRunningErrorDescription() {
        #expect(IPCError.appNotRunning.errorDescription?.contains("AIDevTools") == true)
    }

    @Test("connectionFailed error description includes the message")
    func connectionFailedErrorDescription() {
        let message = "socket closed"
        let error = IPCError.connectionFailed(message)
        #expect(error.errorDescription?.contains(message) == true)
    }

    @Test("noResponse error has non-nil description")
    func noResponseErrorDescription() {
        #expect(IPCError.noResponse.errorDescription != nil)
    }
}
