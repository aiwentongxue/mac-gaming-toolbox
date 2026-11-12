@preconcurrency import GameController
import Foundation
import IOKit

/// Retains physical device identities before creating our feed. Devices appearing
/// during that feed cannot become input sources, even if they use the same Xbox name.
final class ControllerDeviceRegistry: @unchecked Sendable {
    static let shared = ControllerDeviceRegistry()
    private let lock = NSRecursiveLock()
    private let controllers: @Sendable () -> [GCController]
    private let virtualDeviceIDs: @Sendable () -> Set<UInt64>
    private var virtualBaseline: Set<UInt64> = []

    init(
        controllers: @escaping @Sendable () -> [GCController] = { GCController.controllers() },
        virtualDeviceIDs: @escaping @Sendable () -> Set<UInt64> = { ControllerDeviceRegistry.ojdVirtualDeviceIDs() }
    ) {
        self.controllers = controllers
        self.virtualDeviceIDs = virtualDeviceIDs
    }

    private static func ojdVirtualDeviceIDs() -> Set<UInt64> {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOHIDDevice"), &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var result: Set<UInt64> = []
        while true {
            let device = IOIteratorNext(iterator)
            guard device != 0 else { break }
            defer { IOObjectRelease(device) }
            let serial = IORegistryEntryCreateCFProperty(device, "SerialNumber" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String
            if serial?.hasPrefix("OpenJoystickDriver-UserSpace:") == true {
                var id: UInt64 = 0
                if IORegistryEntryGetRegistryEntryID(device, &id) == KERN_SUCCESS { result.insert(id) }
            }
        }
        return result
    }
    private var feedBaseline: Set<ObjectIdentifier>?
    private var excluded: [GCController] = []
    private var feedOutput: GCController?
    private var selected: GCController?
    private var explicitlyDisconnected = false

    func physicalControllers() -> [GCController] {
        lock.withLock {
            let all = controllers().filter { $0.extendedGamepad != nil }
            return all.filter { candidate in
                let knownPhysical = feedBaseline.map { $0.contains(ObjectIdentifier(candidate)) } ?? true
                return knownPhysical && !excluded.contains { $0 === candidate }
            }
        }
    }

    func beginFeed() {
        lock.withLock {
            let devices = physicalControllers()
            if selected == nil, !explicitlyDisconnected { selected = devices.first }
            feedOutput = nil
            virtualBaseline = virtualDeviceIDs()
            feedBaseline = Set(devices.map(ObjectIdentifier.init))
        }
    }

    func hasFeedDevice() -> Bool {
        lock.withLock {
            let all = controllers().filter { $0.extendedGamepad != nil }
            if let feedOutput { return all.contains { $0 === feedOutput } }
            guard let feedBaseline, virtualDeviceIDs().subtracting(virtualBaseline).count == 1 else { return false }
            let added = all.filter { candidate in
                !feedBaseline.contains(ObjectIdentifier(candidate)) && !excluded.contains { $0 === candidate }
            }
            // Ambiguous concurrent attachment is not accepted as our output.
            guard added.count == 1, let output = added.first else { return false }
            feedOutput = output
            excluded.append(output)
            return true
        }
    }

    func endFeed() {
        lock.withLock {
            feedBaseline = nil
            feedOutput = nil
        }
    }

    func select(id: String?) {
        lock.withLock {
            selected = physicalControllers().first { identifier($0) == id }
            explicitlyDisconnected = selected == nil
        }
    }

    func identifier(_ controller: GCController) -> String {
        String(describing: ObjectIdentifier(controller))
    }

    func selectedController(preferredName: String?) -> GCController? {
        lock.withLock {
            let devices = physicalControllers()
            if let selected { return devices.first { $0 === selected } }
            guard !explicitlyDisconnected, feedBaseline == nil else { return nil }
            let named = devices.enumerated().first {
                "\($0.element.vendorName ?? "Controller") #\($0.offset + 1)" == preferredName
            }?.element
            selected = named ?? devices.first
            return selected
        }
    }
}
