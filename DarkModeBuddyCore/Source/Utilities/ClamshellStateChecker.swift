//
//  ClamshellStateChecker.swift
//  clamshellstate
//
//  Created by Guilherme Rambo on 25/02/21.
//

import Cocoa
import IOKit

final class ClamshellStateChecker {

    static func isClamshellClosed() -> Bool {
        let rootDomain = IOServiceGetMatchingService(Self.mainPort, IOServiceMatching("IOPMrootDomain"))
        guard rootDomain != IO_OBJECT_NULL else { return false }
        defer { IOObjectRelease(rootDomain) }

        let value = IORegistryEntryCreateCFProperty(rootDomain, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)

        return (value?.takeRetainedValue() as? Bool) ?? false
    }

    /// MACH_PORT_NULL selects the default main port, without the availability dance around `kIOMainPortDefault`.
    private static let mainPort = mach_port_t(MACH_PORT_NULL)
    
    /// iokit_family_msg(sub_iokit_powermanagement, 0x100), not imported into Swift.
    private static let kIOPMMessageClamshellStateChange: natural_t = 0xE0034100

    private let changeHandler: () -> Void

    private var notificationPort: IONotificationPortRef?
    private var notifier: io_object_t = IO_OBJECT_NULL
    private var screenObserver: NSObjectProtocol?

    /// Calls `changeHandler` on the main queue whenever the clamshell state may have changed.
    /// The handler can be called spuriously, so it should re-check `isClamshellClosed()`.
    init(changeHandler: @escaping () -> Void) {
        self.changeHandler = changeHandler

        startObservingRootDomain()

        // Closing or opening the lid with an external display attached also reconfigures the screens,
        // which serves as a fallback in case the power management message isn't delivered.
        // The lid state can lag slightly behind the screen change, so check again shortly after.
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.changeHandler()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self?.changeHandler()
            }
        }
    }

    deinit {
        if let screenObserver = screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        if notifier != IO_OBJECT_NULL {
            IOObjectRelease(notifier)
        }
        if let notificationPort = notificationPort {
            IONotificationPortDestroy(notificationPort)
        }
    }

    private func startObservingRootDomain() {
        let rootDomain = IOServiceGetMatchingService(Self.mainPort, IOServiceMatching("IOPMrootDomain"))
        guard rootDomain != IO_OBJECT_NULL else { return }
        defer { IOObjectRelease(rootDomain) }

        guard let port = IONotificationPortCreate(Self.mainPort) else { return }
        IONotificationPortSetDispatchQueue(port, .main)
        notificationPort = port

        let callback: IOServiceInterestCallback = { refcon, _, messageType, _ in
            guard let refcon = refcon, messageType == ClamshellStateChecker.kIOPMMessageClamshellStateChange else { return }

            let checker = Unmanaged<ClamshellStateChecker>.fromOpaque(refcon).takeUnretainedValue()
            checker.changeHandler()
        }

        IOServiceAddInterestNotification(
            port,
            rootDomain,
            kIOGeneralInterest,
            callback,
            Unmanaged.passUnretained(self).toOpaque(),
            &notifier
        )
    }

}
