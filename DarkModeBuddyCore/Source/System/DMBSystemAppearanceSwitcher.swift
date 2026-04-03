//
//  DMBSystemAppearanceSwitcher.swift
//  DarkModeBuddyCore
//
//  Created by Guilherme Rambo on 23/02/21.
//

import Cocoa
import Combine
import os.log

public final class DMBSystemAppearanceSwitcher: ObservableObject {
    
    enum Appearance: Int32, CustomStringConvertible {
        case light
        case dark
        
        var description: String {
            switch self {
            case .dark:
                return "Dark"
            case .light:
                return "Light"
            }
        }
        
        static var current: Appearance { Appearance(rawValue: SLSGetAppearanceThemeLegacy()) ?? .light }
    }
    
    private let log = OSLog(subsystem: kDarkModeBuddyCoreSubsystemName, category: String(describing: DMBSystemAppearanceSwitcher.self))

    let settings: DMBSettings
    let reader: DMBAmbientLightSensorReader
    public var timeScheduleManager: TimeScheduleManager?

    private var cancellables = Set<AnyCancellable>()

    /// Tracks whether macOS Auto dark mode was enabled before we disabled it.
    private static let savedAutoSwitchKey = "DMBSavedAppleInterfaceStyleSwitchesAutomatically"
    private static let didOverrideAutoKey = "DMBDidOverrideAutoSwitch"

    private var globalDefaults: UserDefaults? {
        UserDefaults(suiteName: UserDefaults.globalDomain)
    }

    private var macOSAutoSwitchEnabled: Bool {
        get {
            globalDefaults?.bool(forKey: "AppleInterfaceStyleSwitchesAutomatically") ?? false
        }
        set {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
            process.arguments = ["write", "-g", "AppleInterfaceStyleSwitchesAutomatically", "-bool", newValue ? "true" : "false"]
            try? process.run()
            process.waitUntilExit()
        }
    }

    public init(settings: DMBSettings,
                reader: DMBAmbientLightSensorReader = DMBAmbientLightSensorReader(frequency: .fast))
    {
        self.settings = settings
        self.reader = reader
    }

    public func activate() {
        reader.$ambientLightValue.sink { [weak self] newValue in
            self?.ambientLightChanged(to: newValue)
        }.store(in: &cancellables)

        settings.$darknessThresholdIntervalInSeconds.removeDuplicates().sink { [weak self] _ in
            self?.reset()
        }.store(in: &cancellables)

        settings.$darknessThreshold.removeDuplicates().sink { [weak self] _ in
            self?.reset()
        }.store(in: &cancellables)

        // Re-evaluate when the time schedule window changes
        timeScheduleManager?.$isWithinSchedule.removeDuplicates().sink { [weak self] _ in
            self?.reset()
        }.store(in: &cancellables)

        // Disable/restore macOS Auto when the toggle changes
        settings.$isChangeSystemAppearanceBasedOnAmbientLightEnabled.sink { [weak self] enabled in
            if enabled {
                self?.disableMacOSAutoDarkMode()
            } else {
                self?.restoreMacOSAutoDarkMode()
            }
        }.store(in: &cancellables)

        setupUpdateAppearanceOnWake()

        reader.activate()
    }

    // MARK: - macOS Auto Dark Mode Management

    /// Disables macOS built-in Auto dark mode and saves its previous state.
    private func disableMacOSAutoDarkMode() {
        let wasAuto = macOSAutoSwitchEnabled
        if wasAuto {
            UserDefaults.standard.set(true, forKey: Self.savedAutoSwitchKey)
            UserDefaults.standard.set(true, forKey: Self.didOverrideAutoKey)
            macOSAutoSwitchEnabled = false
            os_log("Disabled macOS Auto dark mode (was enabled)", log: log, type: .debug)
        }
    }

    /// Restores macOS Auto dark mode to its previous state if we disabled it.
    public func restoreMacOSAutoDarkMode() {
        guard UserDefaults.standard.bool(forKey: Self.didOverrideAutoKey) else { return }
        let savedValue = UserDefaults.standard.bool(forKey: Self.savedAutoSwitchKey)
        if savedValue {
            macOSAutoSwitchEnabled = true
            os_log("Restored macOS Auto dark mode", log: log, type: .debug)
        }
        UserDefaults.standard.removeObject(forKey: Self.didOverrideAutoKey)
        UserDefaults.standard.removeObject(forKey: Self.savedAutoSwitchKey)
    }
    
    private func setupUpdateAppearanceOnWake() {
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self?.attemptAppearanceChangeOnWake()
            }
        }
    }
    
    private func attemptAppearanceChangeOnWake() {
        guard settings.isImmediateChangeOnComputerWakeEnabled else { return }
        
        reader.update()
        
        os_log("%{public}@ %.2f", log: log, type: .debug, #function, reader.ambientLightValue)
        
        if reader.ambientLightValue < settings.darknessThreshold {
            changeSystemAppearance(to: .dark)
        } else {
            changeSystemAppearance(to: .light)
        }
    }
    
    private func reset() {
        candidateAppearance = nil
        cancelScheduledApperanceChange()
        
        evaluateAmbientLight(with: reader.ambientLightValue)
    }
    
    /// The current appearance that we'll change to, assuming the conditions stay favorable.
    private var candidateAppearance: Appearance?
    
    /// Scheduled appearance change, might be cancelled if conditions change.
    private var changeAppearanceWorkItem: DispatchWorkItem?
    
    private func ambientLightChanged(to value: Double) {
        guard abs(value - reader.ambientLightValue) > settings.ambientLightSmoothingConstant else { return }
        
        os_log("%{public}@ %.2f", log: log, type: .debug, #function, value)

        evaluateAmbientLight(with: value)
    }
    
    private func cancelScheduledApperanceChange() {
        guard changeAppearanceWorkItem != nil else { return }
        
        changeAppearanceWorkItem?.cancel()
        changeAppearanceWorkItem = nil
        
        os_log("Cancelled scheduled appearance change", log: self.log, type: .debug)
    }
    
    private func evaluateAmbientLight(with value: Double) {
        #if DEBUG
        os_log("%{public}@ %{public}.2f", log: log, type: .debug, #function, value)
        os_log("Candidate appearance is %@", log: self.log, type: .debug, candidateAppearance?.description ?? "")
        #endif

        guard value != -1 else { return }

        let newAppearance: Appearance

        // If a time constraint is set and we're outside the window, force light mode.
        // Otherwise, apply the normal brightness-based logic.
        if let scheduleManager = timeScheduleManager, !scheduleManager.isWithinSchedule {
            os_log("Outside time schedule, forcing light mode", log: self.log, type: .debug)
            newAppearance = .light
        } else if value < settings.darknessThreshold {
            os_log("Below threshold %{public}.2f", log: self.log, type: .debug, settings.darknessThreshold)
            newAppearance = .dark
        } else {
            if Appearance.current == .dark {
                guard value > (settings.darknessThreshold + settings.extraThresholdBeforeRevertingToLightMode) else {
                    return
                }
            }
            os_log("Above threshold %{public}.2f", log: self.log, type: .debug, settings.darknessThreshold)
            newAppearance = .light
        }
        
        guard newAppearance != candidateAppearance else { return }
        candidateAppearance = newAppearance
        
        cancelScheduledApperanceChange()
        
        guard newAppearance != .current else { return }

        os_log("New candidate appearance is %@", log: self.log, type: .debug, newAppearance.description)
        
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.changeSystemAppearance(to: newAppearance)
        }
        changeAppearanceWorkItem = workItem
        
        DispatchQueue.main.asyncAfter(deadline: .now() + settings.darknessThresholdIntervalInSeconds, execute: workItem)
        
        os_log("Scheduled appearance change to %{public}@ for %{public}@, if conditions remain favorable (interval = %{public}.2f)", log: self.log, type: .debug, newAppearance.description, Date().addingTimeInterval(settings.darknessThresholdIntervalInSeconds).description, settings.darknessThresholdIntervalInSeconds)
    }
    
    private func changeSystemAppearance(to newAppearance: Appearance) {
        guard newAppearance != .current else { return }

        if settings.isDisableAppearanceChangeInClamshellModeEnabled {
            guard !ClamshellStateChecker.isClamshellClosed() else {
                os_log("Skipping appearance change because the Mac is in clamshell mode", log: self.log, type: .debug)
                return
            }
        }

        os_log("%{public}@ %{public}@", log: log, type: .debug, #function, newAppearance.description)

        guard settings.isChangeSystemAppearanceBasedOnAmbientLightEnabled else {
            os_log("Automatic appearance change disabled in settings", log: self.log, type: .debug)
            return
        }

        SLSSetAppearanceThemeLegacy(newAppearance.rawValue)
    }
    
}
