//
//  DMBAmbientLightSensorReader.swift
//  DarkModeBuddyCore
//
//  Created by Guilherme Rambo on 23/02/21.
//

import Foundation
import Combine
import os.log

public final class DMBAmbientLightSensorReader: ObservableObject {
    
    private let log = OSLog(subsystem: kDarkModeBuddyCoreSubsystemName, category: String(describing: DMBAmbientLightSensorReader.self))
    
    public enum UpdateFrequency: TimeInterval {
        case realtime = 0.1
        case fast = 5
        case slow = 10
    }
    
    let sensor: DMBAmbientLightSensor
    
    public var isSensorReady: Bool { sensor.isPresent }
    
    @Published public var ambientLightValue: Double = 0
    
    private var sensorObservation: NSKeyValueObservation?
    
    public init(frequency: UpdateFrequency = .fast, sensor: DMBAmbientLightSensor = DMBAmbientLightSensor()) {
        self.sensor = sensor
        self.sensor.updateInterval = frequency.rawValue
        
        sensorObservation = sensor.observe(\.value, options: [.initial, .new, .old]) { [weak self] sensor, change in
            guard let self = self else { return }
            
            guard change.oldValue != change.newValue else { return }
            
            self.ambientLightValue = sensor.value
        }
    }
    
    public func activate() {
        os_log("%{public}@", log: log, type: .debug, #function)
        
        sensor.activate()
    }
    
    public func invalidate() {
        os_log("%{public}@", log: log, type: .debug, #function)
        
        sensor.invalidate()
    }
    
    public func update() {
        sensor.update()
    }
    
    deinit { invalidate() }
    
}
