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
    public let reader: DMBAmbientLightSensorReader
    
    private var cancellables = Set<AnyCancellable>()
    
    private var clamshellStateChecker: ClamshellStateChecker?
    
    /// The appearance last forced because of clamshell mode, so it's only applied once
    /// and the user can still change it manually while the lid is closed.
    private var forcedClamshellAppearance: Appearance?
    
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
        
        settings.$darknessThresholdIntervalInSeconds.sink { [weak self] _ in
            self?.reset()
        }.store(in: &cancellables)
        
        settings.$darknessThreshold.sink { [weak self] _ in
            self?.reset()
        }.store(in: &cancellables)
        
        settings.$clamshellAppearance.dropFirst().sink { [weak self] newValue in
            self?.updateClamshellOverride(preference: newValue)
        }.store(in: &cancellables)
        
        clamshellStateChecker = ClamshellStateChecker { [weak self] in
            self?.updateClamshellOverride()
        }
        
        setupUpdateAppearanceOnWake()
        
        // Also restores the system appearance if the app quit while the override was active.
        updateClamshellOverride()
        
        reader.activate()
    }
    
    private func setupUpdateAppearanceOnWake() {
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self?.updateClamshellOverride()
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
        #endif
        
        guard value != -1 else { return }
        
        let newAppearance: Appearance
        
        if value < settings.darknessThreshold {
            newAppearance = .dark
        } else {
            if Appearance.current == .dark {
                guard value > (settings.darknessThreshold + settings.extraThresholdBeforeRevertingToLightMode) else {
                    return
                }
            }
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
        
        guard settings.clamshellRestoreState == nil else {
            os_log("Skipping appearance change because the clamshell appearance override is active", log: self.log, type: .debug)
            return
        }
        
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
    
    // MARK: - Clamshell override
    
    /// Forces the preferred appearance while the lid is closed, suspending both our automatic switching and macOS',
    /// and restores the previous state once the lid opens (or the preference is turned off).
    private func updateClamshellOverride(preference: DMBSettings.ClamshellAppearance? = nil) {
        let preference = preference ?? settings.clamshellAppearance
        
        if let forcedAppearance = preference.appearance, ClamshellStateChecker.isClamshellClosed() {
            if settings.clamshellRestoreState == nil {
                settings.clamshellRestoreState = DMBSettings.ClamshellRestoreState(
                    appearance: SLSGetAppearanceThemeLegacy(),
                    switchesAutomatically: SLSGetAppearanceThemeSwitchesAutomatically()
                )
                
                // Only on entry, so the user can still turn it back on while the lid is closed.
                SLSSetAppearanceThemeSwitchesAutomatically(false)
                
                os_log("Entering clamshell appearance override", log: self.log, type: .debug)
            }
            
            candidateAppearance = nil
            cancelScheduledApperanceChange()
            
            guard forcedAppearance != forcedClamshellAppearance else { return }
            forcedClamshellAppearance = forcedAppearance
            
            os_log("Forcing %{public}@ appearance in clamshell mode", log: self.log, type: .debug, forcedAppearance.description)
            
            SLSSetAppearanceThemeLegacy(forcedAppearance.rawValue)
        } else {
            guard endClamshellOverride() else { return }
            
            // Let ambient light take over again from the current reading.
            reset()
        }
    }
    
    /// Restores the theme and macOS' automatic switching saved when the clamshell override began.
    /// Returns whether an override was active.
    @discardableResult
    public func endClamshellOverride() -> Bool {
        forcedClamshellAppearance = nil
        
        guard let restoreState = settings.clamshellRestoreState else { return false }
        settings.clamshellRestoreState = nil
        
        os_log("Leaving clamshell appearance override", log: self.log, type: .debug)
        
        SLSSetAppearanceThemeLegacy(restoreState.appearance)
        
        if restoreState.switchesAutomatically {
            SLSSetAppearanceThemeSwitchesAutomatically(true)
        }
        
        return true
    }
    
}

private extension DMBSettings.ClamshellAppearance {
    var appearance: DMBSystemAppearanceSwitcher.Appearance? {
        switch self {
        case .unchanged:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}
