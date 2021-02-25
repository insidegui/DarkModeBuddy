//
//  DMBSystemAppearanceSwitcher.swift
//  DarkModeBuddyCore
//
//  Created by Guilherme Rambo on 23/02/21.
//

import Foundation
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
    
    private var cancellables = Set<AnyCancellable>()
    
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
        
        reader.activate()
    }
    
    /// The current appearance that we'll change to, assuming the conditions stay favorable.
    private var candidateAppearance: Appearance?
    
    /// Scheduled appearance change, might be cancelled if conditions change.
    private var changeAppearanceWorkItem: DispatchWorkItem?
    
    private func ambientLightChanged(to value: Double) {
        guard abs(value - reader.ambientLightValue) > settings.ambientLightSmoothingConstant else { return }
        
        os_log("%{public}@ %.2f", log: log, type: .debug, #function, value)

        let newAppearance: Appearance
        
        if value < settings.darknessThreshold {
            newAppearance = .dark
        } else {
            newAppearance = .light
        }
        
        guard newAppearance != candidateAppearance else { return }
        candidateAppearance = newAppearance
        
        if changeAppearanceWorkItem != nil {
            changeAppearanceWorkItem?.cancel()
            changeAppearanceWorkItem = nil
            
            os_log("Cancelled scheduled appearance change", log: self.log, type: .debug)
        }
        
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
