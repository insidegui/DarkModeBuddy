//
//  AppDelegate.swift
//  DarkModeBuddy
//
//  Created by Guilherme Rambo on 23/02/21.
//

import Cocoa
import SwiftUI
import DarkModeBuddyCore
import Sparkle

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    var window: NSWindow!

    lazy var settings = DMBSettings()
    lazy var locationManager = LocationManager()

    lazy var timeScheduleManager: TimeScheduleManager = {
        TimeScheduleManager(settings: settings, locationManager: locationManager)
    }()

    lazy var switcher: DMBSystemAppearanceSwitcher = {
        let s = DMBSystemAppearanceSwitcher(settings: settings)
        s.timeScheduleManager = timeScheduleManager
        return s
    }()
    
    private var shouldShowUI: Bool {
        !settings.hasLaunchedAppBefore
        || shouldShowSettingsOnNextLaunch
        || UserDefaults.standard.bool(forKey: "ShowSettings")
    }
    
    func applicationWillFinishLaunching(_ notification: Notification) {
        guard !isRunningInPreview else { return }
        SUUpdater.shared()?.delegate = self
    }

    private var isRunningInPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PLAYGROUNDS"] != nil
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        guard !isRunningInPreview else { return }

        if shouldShowUI {
            settings.hasLaunchedAppBefore = true
            showSettingsWindow(nil)
        }
        
        timeScheduleManager.activate()
        switcher.activate()

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(receivedShutdownNotification),
            name: NSWorkspace.willPowerOffNotification,
            object: nil
        )
    }
    
    private lazy var sensorReader = DMBAmbientLightSensorReader(frequency: .realtime)

    @IBAction func showSettingsWindow(_ sender: Any?) {
        NSApp.setActivationPolicy(.regular)
        
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 580),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.center()
        window.setFrameAutosaveName("Settings")
        window.titlebarAppearsTransparent = true
        window.title = "DarkModeBuddy Settings"
        window.isMovableByWindowBackground = true
        window.delegate = self
        window.isReleasedWhenClosed = false
        
        let view = SettingsView()
            .environmentObject(sensorReader)
            .environmentObject(settings)
            .environmentObject(locationManager)
            .environmentObject(timeScheduleManager)
        
        let hostingController = AutoSizingHostingController(rootView: view)
        window.contentViewController = hostingController
        
        window.makeKeyAndOrderFront(nil)
        window.center()
        
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @IBAction func terminate(_ sender: Any?) {
        // No need to confirm on quit if the user's Mac is not supported.
        shouldSkipTerminationConfirmation = !sensorReader.isSensorReady
        
        NSApp.terminate(sender)
    }

    private var isShowingSettingsWindow: Bool {
        guard let window = window else { return false }
        return window.isVisible
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !isShowingSettingsWindow else { return true }
        
        showSettingsWindow(nil)
        
        return true
    }
    
    private var shouldShowSettingsOnNextLaunch: Bool {
        get {
            let value = UserDefaults.standard.bool(forKey: #function)
            
            if value {
                // Reset flag
                UserDefaults.standard.set(false, forKey: #function)
            }
            
            return value
        }
        set {
            UserDefaults.standard.set(newValue, forKey: #function)
            UserDefaults.standard.synchronize()
        }
    }
    
    private var shouldSkipTerminationConfirmation = false
    
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !shouldSkipTerminationConfirmation else {
            switcher.restoreMacOSAutoDarkMode()
            return .terminateNow
        }

        let alert = NSAlert()
        alert.messageText = "Quit DarkModeBuddy?"
        alert.informativeText = "If you quit DarkModeBuddy, it won't be able to monitor your ambient light level and change the system theme automatically. Would you like to hide DarkModeBuddy instead?"
        alert.addButton(withTitle: "Hide DarkModeBuddy")
        alert.addButton(withTitle: "Quit")

        let result = alert.runModal()

        if result == .alertSecondButtonReturn {
            switcher.restoreMacOSAutoDarkMode()
            return .terminateNow
        } else {
            window?.close()
            
            return .terminateCancel
        }
    }
    
    @objc func receivedShutdownNotification(_ note: Notification) {
        shouldSkipTerminationConfirmation = true
    }

}

extension AppDelegate: NSWindowDelegate {

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        
        window = nil
    }
    
}

final class AutoSizingHostingController<Content: View>: NSHostingController<Content> {
    override func viewDidLayout() {
        super.viewDidLayout()
        guard let window = view.window else { return }
        let fittingSize = view.fittingSize
        let targetSize = NSSize(
            width: max(fittingSize.width, 420),
            height: fittingSize.height
        )
        if window.contentView?.frame.size != targetSize {
            window.setContentSize(targetSize)
        }
    }
}

extension AppDelegate: SUUpdaterDelegate {
    
    func updaterWillRelaunchApplication(_ updater: SUUpdater) {
        shouldSkipTerminationConfirmation = true
        shouldShowSettingsOnNextLaunch = true
    }
    
    func updater(_ updater: SUUpdater, didCancelInstallUpdateOnQuit item: SUAppcastItem) {
        shouldSkipTerminationConfirmation = false
    }
    
}
