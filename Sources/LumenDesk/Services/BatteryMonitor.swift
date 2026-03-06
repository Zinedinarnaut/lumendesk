import Foundation
import IOKit.ps

struct BatteryMonitor {
    func isOnBatteryPower() -> Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            return false
        }

        guard let sourceTypeRef = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue() else {
            return false
        }

        let sourceType = sourceTypeRef as String
        return sourceType == kIOPSBatteryPowerValue
    }
}
