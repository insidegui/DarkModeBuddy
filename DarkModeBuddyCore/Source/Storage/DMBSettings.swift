//
//  DMBSettings.swift
//  DarkModeBuddyCore
//
//  Created by Guilherme Rambo on 23/02/21.
//

import Foundation
import SwiftUI

/// Mode for time-based scheduling of the brightness threshold.
public enum TimeScheduleMode: Int, CaseIterable, Identifiable {
    case disabled = 0
    case fixedTime = 1
    case solarRelative = 2

    public var id: Int { rawValue }

    public var label: String {
        switch self {
        case .disabled: return "Always Active"
        case .fixedTime: return "Fixed Time Window"
        case .solarRelative: return "Relative to Sunset/Sunrise"
        }
    }
}

/// Predefined offset options (in minutes) for solar-relative scheduling.
public enum SolarOffset: Int, CaseIterable, Identifiable {
    case minusFourHours = -240
    case minusThreeHours = -180
    case minusTwoHours = -120
    case minusOneHour = -60
    case minusFortyFive = -45
    case minusThirty = -30
    case minusFifteen = -15
    case atEvent = 0
    case plusFifteen = 15
    case plusThirty = 30
    case plusFortyFive = 45
    case plusOneHour = 60
    case plusTwoHours = 120
    case plusThreeHours = 180
    case plusFourHours = 240

    public var id: Int { rawValue }

    public var label: String {
        let hours = abs(rawValue) / 60
        let mins = abs(rawValue) % 60
        if rawValue < 0 {
            if mins == 0 {
                return "-\(hours):00"
            } else {
                return "-\(hours):\(String(format: "%02d", mins))"
            }
        } else if rawValue == 0 {
            return "At event"
        } else {
            if mins == 0 {
                return "+\(hours):00"
            } else {
                return "+\(hours):\(String(format: "%02d", mins))"
            }
        }
    }
}

public final class DMBSettings: ObservableObject {

    private struct Keys {
        static let darknessThreshold = "darknessThreshold"
        static let isChangeSystemAppearanceBasedOnAmbientLightEnabled = "isChangeSystemAppearanceBasedOnAmbientLightEnabled"
        static let darknessThresholdIntervalInSeconds = "darknessThresholdIntervalInSeconds"
        static let ambientLightSmoothingConstant = "ambientLightSmoothingConstant"
        static let hasLaunchedAppBefore = "hasLaunchedAppBefore"
        static let disableAppearanceChangeInClamshellMode = "disableAppearanceChangeInClamshellMode"
        static let enableImmediateChangeOnComputerWake = "enableImmediateChangeOnComputerWake"
        static let extraThresholdBeforeRevertingToLightMode = "extraThresholdBeforeRevertingToLightMode"

        // Time scheduling keys
        static let timeScheduleMode = "timeScheduleMode"
        static let fixedStartHour = "fixedStartHour"
        static let fixedStartMinute = "fixedStartMinute"
        static let fixedEndHour = "fixedEndHour"
        static let fixedEndMinute = "fixedEndMinute"
        static let sunsetOffsetMinutes = "sunsetOffsetMinutes"
        static let sunriseOffsetMinutes = "sunriseOffsetMinutes"
        
        static let defaultDarknessThreshold: Double = {
            DMBAmbientLightSensor.hardwareUsesLegacySensor() ? 20.0 : 52.0
        }()

        static let defaultAmbientLightSmoothingConstant: Double = {
            DMBAmbientLightSensor.hardwareUsesLegacySensor() ? 5.0 : 3.0
        }()
        
        static let defaultExtraThresholdBeforeRevertingToLightMode: Double = {
            DMBAmbientLightSensor.hardwareUsesLegacySensor() ? 30.0 : 10.0
        }()

        static let defaultDarknessThresholdIntervalInSeconds = 60.0
    }
    
    private let defaults: UserDefaults

    let isPreviewing: Bool
    
    public init(forPreview isPreviewing: Bool = false, defaults: UserDefaults = .standard) {
        self.isPreviewing = isPreviewing
        self.defaults = defaults
        
        defaults.register(defaults: [
            Keys.darknessThreshold: Keys.defaultDarknessThreshold,
            Keys.isChangeSystemAppearanceBasedOnAmbientLightEnabled: true,
            Keys.darknessThresholdIntervalInSeconds: Keys.defaultDarknessThresholdIntervalInSeconds,
            Keys.ambientLightSmoothingConstant: Keys.defaultAmbientLightSmoothingConstant,
            Keys.disableAppearanceChangeInClamshellMode: true,
            Keys.enableImmediateChangeOnComputerWake: true,
            Keys.extraThresholdBeforeRevertingToLightMode: Keys.defaultExtraThresholdBeforeRevertingToLightMode,
            Keys.timeScheduleMode: TimeScheduleMode.disabled.rawValue,
            Keys.fixedStartHour: 18,
            Keys.fixedStartMinute: 0,
            Keys.fixedEndHour: 7,
            Keys.fixedEndMinute: 0,
            Keys.sunsetOffsetMinutes: SolarOffset.atEvent.rawValue,
            Keys.sunriseOffsetMinutes: SolarOffset.atEvent.rawValue
        ])

        self.isChangeSystemAppearanceBasedOnAmbientLightEnabled = defaults.bool(forKey: Keys.isChangeSystemAppearanceBasedOnAmbientLightEnabled)
        self.hasLaunchedAppBefore = defaults.bool(forKey: Keys.hasLaunchedAppBefore)
        self.darknessThreshold = defaults.optionalDoubleValue(forKey: Keys.darknessThreshold) ?? Keys.defaultDarknessThreshold
        self.darknessThresholdIntervalInSeconds = defaults.optionalDoubleValue(forKey: Keys.darknessThresholdIntervalInSeconds) ?? Keys.defaultDarknessThresholdIntervalInSeconds
        self.ambientLightSmoothingConstant = defaults.optionalDoubleValue(forKey: Keys.ambientLightSmoothingConstant) ?? Keys.defaultAmbientLightSmoothingConstant
        self.extraThresholdBeforeRevertingToLightMode = defaults.optionalDoubleValue(forKey: Keys.extraThresholdBeforeRevertingToLightMode) ?? Keys.defaultExtraThresholdBeforeRevertingToLightMode
        self.timeScheduleMode = TimeScheduleMode(rawValue: defaults.integer(forKey: Keys.timeScheduleMode)) ?? .disabled
        self.fixedStartHour = defaults.integer(forKey: Keys.fixedStartHour)
        self.fixedStartMinute = defaults.integer(forKey: Keys.fixedStartMinute)
        self.fixedEndHour = defaults.integer(forKey: Keys.fixedEndHour)
        self.fixedEndMinute = defaults.integer(forKey: Keys.fixedEndMinute)
        self.sunsetOffsetMinutes = defaults.integer(forKey: Keys.sunsetOffsetMinutes)
        self.sunriseOffsetMinutes = defaults.integer(forKey: Keys.sunriseOffsetMinutes)
        
        if isPreviewing {
            self.isLaunchAtLoginEnabled = false
        } else {
            self.isLaunchAtLoginEnabled = Self.isAppInLoginItems
            
            SharedFileList.sessionLoginItems().changeHandler = { [weak self] _ in
                self?.updateLaunchAtLoginEnabled()
            }
        }
    }
    
    var isDisableAppearanceChangeInClamshellModeEnabled: Bool {
        defaults.bool(forKey: Keys.disableAppearanceChangeInClamshellMode)
    }
    
    var isImmediateChangeOnComputerWakeEnabled: Bool {
        defaults.bool(forKey: Keys.enableImmediateChangeOnComputerWake)
    }
    
    @Published public var hasLaunchedAppBefore: Bool {
        didSet {
            defaults.set(
                hasLaunchedAppBefore,
                forKey: Keys.hasLaunchedAppBefore
            )
        }
    }
    
    /// Whether to change system appearance automatically based on ambient light.
    @Published public var isChangeSystemAppearanceBasedOnAmbientLightEnabled: Bool {
        didSet {
            defaults.set(
                isChangeSystemAppearanceBasedOnAmbientLightEnabled,
                forKey: Keys.isChangeSystemAppearanceBasedOnAmbientLightEnabled
            )
        }
    }
    
    /// The threshold below which the ambient light is considered "dark".
    @Published public var darknessThreshold: Double {
        didSet {
            defaults.set(
                darknessThreshold,
                forKey: Keys.darknessThreshold
            )
        }
    }
    
    /// For how long the ambient light must be below `darknessThreshold` or above
    /// it for the system appearance to be changed based on that.
    @Published public var darknessThresholdIntervalInSeconds: TimeInterval {
        didSet {
            defaults.set(
                darknessThresholdIntervalInSeconds,
                forKey: Keys.darknessThresholdIntervalInSeconds
            )
        }
    }
    
    /// Changes in ambient light will be ignored if the change is less than this amount.
    /// Not currently exposed in the UI.
    @Published public var ambientLightSmoothingConstant: Double {
        didSet {
            defaults.set(
                ambientLightSmoothingConstant,
                forKey: Keys.ambientLightSmoothingConstant
            )
        }
    }
    
    /// When reverting from Dark Mode to Light Mode, the ambient light level must be
    /// above the user's `darknessThreshold` plus this additional threshold,
    /// in order to prevent frequent changes when at the edge of the transition.
    @Published public var extraThresholdBeforeRevertingToLightMode: Double {
        didSet {
            defaults.set(
                extraThresholdBeforeRevertingToLightMode,
                forKey: Keys.extraThresholdBeforeRevertingToLightMode
            )
        }
    }

    // MARK: - Time Scheduling

    /// The mode for time-based scheduling of brightness threshold.
    @Published public var timeScheduleMode: TimeScheduleMode {
        didSet {
            defaults.set(timeScheduleMode.rawValue, forKey: Keys.timeScheduleMode)
        }
    }

    /// Fixed schedule start hour (0-23).
    @Published public var fixedStartHour: Int {
        didSet { defaults.set(fixedStartHour, forKey: Keys.fixedStartHour) }
    }

    /// Fixed schedule start minute (0-59).
    @Published public var fixedStartMinute: Int {
        didSet { defaults.set(fixedStartMinute, forKey: Keys.fixedStartMinute) }
    }

    /// Fixed schedule end hour (0-23).
    @Published public var fixedEndHour: Int {
        didSet { defaults.set(fixedEndHour, forKey: Keys.fixedEndHour) }
    }

    /// Fixed schedule end minute (0-59).
    @Published public var fixedEndMinute: Int {
        didSet { defaults.set(fixedEndMinute, forKey: Keys.fixedEndMinute) }
    }

    /// Offset in minutes from sunset for the schedule start.
    @Published public var sunsetOffsetMinutes: Int {
        didSet { defaults.set(sunsetOffsetMinutes, forKey: Keys.sunsetOffsetMinutes) }
    }

    /// Offset in minutes from sunrise for the schedule end.
    @Published public var sunriseOffsetMinutes: Int {
        didSet { defaults.set(sunriseOffsetMinutes, forKey: Keys.sunriseOffsetMinutes) }
    }

    // MARK: - Launch at login
    
    private static var isAppInLoginItems: Bool {
        SharedFileList.sessionLoginItems().containsItem(Self.appURL)
    }
    
    private func updateLaunchAtLoginEnabled() {
        isLaunchAtLoginEnabled = Self.isAppInLoginItems
    }
    
    private static var appURL: URL { Bundle.main.bundleURL }
    
    @Published public var isLaunchAtLoginEnabled: Bool {
        didSet {
            guard !isPreviewing else { return }

            guard isLaunchAtLoginEnabled != oldValue else { return }

            if isLaunchAtLoginEnabled {
                SharedFileList.sessionLoginItems().addItem(Self.appURL)
            } else {
                SharedFileList.sessionLoginItems().removeItem(Self.appURL)
            }
        }
    }
    
}

fileprivate extension UserDefaults {
    func optionalDoubleValue(forKey key: String) -> Double? {
        guard let number = object(forKey: key) as? NSNumber else { return nil }
        return number.doubleValue
    }
}
