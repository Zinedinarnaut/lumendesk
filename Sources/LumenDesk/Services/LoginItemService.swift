import Foundation
import ServiceManagement

@MainActor
enum LoginItemService {
    private static var hasLoggedPermissionDenial = false

    static func sync(enabled: Bool) {
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            // SMAppService only works for bundled app executions.
            return
        }

        if #available(macOS 13.0, *) {
            let service = SMAppService.mainApp
            let status = service.status
            do {
                if enabled {
                    switch status {
                    case .enabled, .requiresApproval:
                        return
                    case .notRegistered, .notFound:
                        try service.register()
                    @unknown default:
                        try service.register()
                    }
                } else {
                    switch status {
                    case .enabled, .requiresApproval:
                        try service.unregister()
                    case .notRegistered, .notFound:
                        return
                    @unknown default:
                        return
                    }
                }
            } catch {
                if suppressExpectedPermissionError(error) {
                    return
                }
                fputs("[LumenDesk] Login item update failed: \(error)\n", stderr)
            }
        }
    }

    private static func suppressExpectedPermissionError(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == "SMAppServiceErrorDomain", nsError.code == 1 else {
            return false
        }

        if !hasLoggedPermissionDenial {
            hasLoggedPermissionDenial = true
            fputs(
                "[LumenDesk] Launch at login is unavailable for the current build/signing configuration.\n",
                stderr
            )
        }
        return true
    }
}
