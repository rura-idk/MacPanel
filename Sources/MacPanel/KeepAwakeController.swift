import Combine
import Foundation
import IOKit.pwr_mgt

/// Keeps the Mac awake while MacPanel runs. No privileged pmset changes.
/// A user-idle assertion is reliable for idle sleep; a stronger assertion is
/// additionally requested for AC-powered Macs, but cannot guarantee operation
/// with a MacBook lid closed on all hardware/OS versions.
final class KeepAwakeController: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var errorMessage: String?

    private var idleAssertion: IOPMAssertionID?
    private var systemAssertion: IOPMAssertionID?

    func setEnabled(_ enabled: Bool) {
        if !enabled {
            releaseAssertions()
            isEnabled = false
            errorMessage = nil
            return
        }
        guard !isEnabled else { return }
        var idleID = IOPMAssertionID()
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "MacPanel: prevent idle sleep" as CFString,
            &idleID
        )
        guard result == kIOReturnSuccess else {
            errorMessage = "Не удалось предотвратить сон от бездействия (IOKit: \(result))."
            return
        }
        idleAssertion = idleID

        // Stronger assertion: honored only under appropriate system conditions,
        // typically AC power; closing the lid can still force sleep.
        var systemID = IOPMAssertionID()
        let systemResult = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "MacPanel: request continued operation on AC power" as CFString,
            &systemID
        )
        if systemResult == kIOReturnSuccess {
            systemAssertion = systemID
        }
        isEnabled = true
        errorMessage = nil
    }

    private func releaseAssertions() {
        if let id = systemAssertion {
            IOPMAssertionRelease(id)
            systemAssertion = nil
        }
        if let id = idleAssertion {
            IOPMAssertionRelease(id)
            idleAssertion = nil
        }
    }

    deinit {
        releaseAssertions()
    }
}
