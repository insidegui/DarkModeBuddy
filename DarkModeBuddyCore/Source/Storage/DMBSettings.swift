//
//  DMBSettings.swift
//  DarkModeBuddyCore
//
//  Created by Guilherme Rambo on 23/02/21.
//

import Foundation
import SwiftUI

public final class DMBSettings: ObservableObject {
    
    /// The appearance to force while the Mac runs with its lid closed on an external display.
    public enum ClamshellAppearance: Int, CaseIterable, Identifiable {
        /// Keep the current appearance, but don't change it automatically.
        case unchanged
        case light
        case dark
        
        public var id: Int { rawValue }
    }
    
    /// What the system looked like before clamshell mode forced an appearance, so it can be restored.
    struct ClamshellRestoreState {
        let appearance: Int32
        let switchesAutomatically: Bool
    }
    
    private struct Keys {
        static let darknessThreshold = "darknessThreshold"
        static let isChangeSystemAppearanceBasedOnAmbientLightEnabled = "isChangeSystemAppearanceBasedOnAmbientLightEnabled"
        static let darknessThresholdIntervalInSeconds = "darknessThresholdIntervalInSeconds"
        static let ambientLightSmoothingConstant = "ambientLightSmoothingConstant"
        static let hasLaunchedAppBefore = "hasLaunchedAppBefore"
        static let disableAppearanceChangeInClamshellMode = "disableAppearanceChangeInClamshellMode"
        static let enableImmediateChangeOnComputerWake = "enableImmediateChangeOnComputerWake"
        static let extraThresholdBeforeRevertingToLightMode = "extraThresholdBeforeRevertingToLightMode"
        static let clamshellAppearance = "clamshellAppearance"
        static let clamshellRestoreAppearance = "clamshellRestoreAppearance"
        static let clamshellRestoreSwitchesAutomatically = "clamshellRestoreSwitchesAutomatically"
        static let isMenuBarIconEnabled = "isMenuBarIconEnabled"
        
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
            Keys.clamshellAppearance: ClamshellAppearance.unchanged.rawValue,
            Keys.isMenuBarIconEnabled: true
        ])
        
        self.isChangeSystemAppearanceBasedOnAmbientLightEnabled = defaults.bool(forKey: Keys.isChangeSystemAppearanceBasedOnAmbientLightEnabled)
        self.hasLaunchedAppBefore = defaults.bool(forKey: Keys.hasLaunchedAppBefore)
        self.darknessThreshold = defaults.optionalDoubleValue(forKey: Keys.darknessThreshold) ?? Keys.defaultDarknessThreshold
        self.darknessThresholdIntervalInSeconds = defaults.optionalDoubleValue(forKey: Keys.darknessThresholdIntervalInSeconds) ?? Keys.defaultDarknessThresholdIntervalInSeconds
        self.ambientLightSmoothingConstant = defaults.optionalDoubleValue(forKey: Keys.ambientLightSmoothingConstant) ?? Keys.defaultAmbientLightSmoothingConstant
        self.extraThresholdBeforeRevertingToLightMode = defaults.optionalDoubleValue(forKey: Keys.extraThresholdBeforeRevertingToLightMode) ?? Keys.defaultExtraThresholdBeforeRevertingToLightMode
        self.clamshellAppearance = ClamshellAppearance(rawValue: defaults.integer(forKey: Keys.clamshellAppearance)) ?? .unchanged
        self.isMenuBarIconEnabled = defaults.bool(forKey: Keys.isMenuBarIconEnabled)
        
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
    
    /// Persisted so the system can still be restored if the app quits while the lid is closed.
    var clamshellRestoreState: ClamshellRestoreState? {
        get {
            guard let appearance = defaults.optionalDoubleValue(forKey: Keys.clamshellRestoreAppearance) else { return nil }
            
            return ClamshellRestoreState(
                appearance: Int32(appearance),
                switchesAutomatically: defaults.bool(forKey: Keys.clamshellRestoreSwitchesAutomatically)
            )
        }
        set {
            if let newValue = newValue {
                defaults.set(newValue.appearance, forKey: Keys.clamshellRestoreAppearance)
                defaults.set(newValue.switchesAutomatically, forKey: Keys.clamshellRestoreSwitchesAutomatically)
            } else {
                defaults.removeObject(forKey: Keys.clamshellRestoreAppearance)
                defaults.removeObject(forKey: Keys.clamshellRestoreSwitchesAutomatically)
            }
        }
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
    
    /// The appearance to use while the Mac runs with its lid closed on an external display.
    /// Automatic switching (both ours and macOS') is suspended in that state, and restored when the lid opens.
    @Published public var clamshellAppearance: ClamshellAppearance {
        didSet {
            defaults.set(
                clamshellAppearance.rawValue,
                forKey: Keys.clamshellAppearance
            )
        }
    }
    
    /// Whether to show the menu bar icon.
    @Published public var isMenuBarIconEnabled: Bool {
        didSet {
            defaults.set(
                isMenuBarIconEnabled,
                forKey: Keys.isMenuBarIconEnabled
            )
        }
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
