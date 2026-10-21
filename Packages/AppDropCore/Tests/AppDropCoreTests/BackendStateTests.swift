import ServiceManagement
import Testing
@testable import AppDropCore

@Suite struct BackendStateTests {
    @Test func mapsEveryServiceManagementStatus() {
        #expect(BackendState(SMAppService.Status.notRegistered) == .notRegistered)
        #expect(BackendState(SMAppService.Status.enabled) == .enabled)
        #expect(BackendState(SMAppService.Status.requiresApproval) == .requiresApproval)
        #expect(BackendState(SMAppService.Status.notFound) == .notFound)
    }
}
