//
//  TimeScheduleManager.swift
//  DarkModeBuddyCore
//
//  Determines whether the current time falls within the configured
//  schedule window for ambient-light-based dark mode switching.
//

import Foundation
import Combine
import os.log

public final class TimeScheduleManager: ObservableObject {

    private let log = OSLog(subsystem: kDarkModeBuddyCoreSubsystemName, category: String(describing: TimeScheduleManager.self))

    let settings: DMBSettings
    let locationManager: LocationManager

    @Published public var isWithinSchedule: Bool = true
    @Published public var computedSunrise: Date?
    @Published public var computedSunset: Date?

    private var cancellables = Set<AnyCancellable>()
    private var timer: Timer?

    public init(settings: DMBSettings, locationManager: LocationManager) {
        self.settings = settings
        self.locationManager = locationManager
    }

    public func activate() {
        // Re-evaluate whenever relevant settings or location change.
        // .receive(on:) ensures evaluate() runs after @Published values
        // are fully stored (willSet fires subscribers before storage).
        Publishers.CombineLatest4(
            settings.$timeScheduleMode,
            settings.$fixedStartHour.combineLatest(settings.$fixedStartMinute),
            settings.$fixedEndHour.combineLatest(settings.$fixedEndMinute),
            settings.$sunsetOffsetMinutes.combineLatest(settings.$sunriseOffsetMinutes)
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in self?.evaluate() }
        .store(in: &cancellables)

        locationManager.$latitude.combineLatest(locationManager.$longitude)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.evaluate() }
            .store(in: &cancellables)

        // Re-evaluate every 60 seconds so we catch boundary transitions
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.evaluate()
        }

        evaluate()
    }

    private func evaluate() {
        let now = Date()

        switch settings.timeScheduleMode {
        case .disabled:
            isWithinSchedule = true
            computedSunrise = nil
            computedSunset = nil

        case .fixedTime:
            isWithinSchedule = isWithinFixedWindow(now: now)
            computedSunrise = nil
            computedSunset = nil

        case .solarRelative:
            evaluateSolarRelative(now: now)
        }
    }

    // MARK: - Fixed Time

    private func isWithinFixedWindow(now: Date) -> Bool {
        let cal = Calendar.current
        let currentMinutes = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)
        let startMinutes = settings.fixedStartHour * 60 + settings.fixedStartMinute
        let endMinutes = settings.fixedEndHour * 60 + settings.fixedEndMinute

        if startMinutes <= endMinutes {
            // Window within same day (e.g. 09:00 - 17:00)
            return currentMinutes >= startMinutes && currentMinutes < endMinutes
        } else {
            // Window spans midnight (e.g. 18:00 - 07:00)
            return currentMinutes >= startMinutes || currentMinutes < endMinutes
        }
    }

    // MARK: - Solar Relative

    private func evaluateSolarRelative(now: Date) {
        guard let lat = locationManager.latitude, let lon = locationManager.longitude else {
            os_log("No location available for solar calculation, falling back to always active", log: log, type: .debug)
            isWithinSchedule = true
            computedSunrise = nil
            computedSunset = nil
            return
        }

        // Compute for today
        guard let solar = SolarCalculator.sunriseSunset(for: now, latitude: lat, longitude: lon) else {
            os_log("Sun does not rise/set at this location today, falling back to always active", log: log, type: .debug)
            isWithinSchedule = true
            return
        }

        let adjustedSunset = solar.sunset.addingTimeInterval(Double(settings.sunsetOffsetMinutes) * 60.0)
        let adjustedSunrise = solar.sunrise.addingTimeInterval(Double(settings.sunriseOffsetMinutes) * 60.0)

        computedSunset = adjustedSunset
        computedSunrise = adjustedSunrise

        // The schedule window goes from adjustedSunset to adjustedSunrise (next day if needed)
        if adjustedSunset <= adjustedSunrise {
            // Unusual case: both on same day
            isWithinSchedule = now >= adjustedSunset && now < adjustedSunrise
        } else {
            // Normal case: sunset today to sunrise tomorrow
            // Also check yesterday's sunset to today's sunrise
            let yesterdaySunrise = adjustedSunrise
            let todaySunset = adjustedSunset

            if now < yesterdaySunrise {
                // Before today's sunrise - check if we're after yesterday's sunset
                if let yesterdaySolar = SolarCalculator.sunriseSunset(
                    for: now.addingTimeInterval(-86400), latitude: lat, longitude: lon
                ) {
                    let yesterdayAdjustedSunset = yesterdaySolar.sunset.addingTimeInterval(Double(settings.sunsetOffsetMinutes) * 60.0)
                    isWithinSchedule = now >= yesterdayAdjustedSunset
                } else {
                    isWithinSchedule = true
                }
            } else if now >= todaySunset {
                isWithinSchedule = true
            } else {
                isWithinSchedule = false
            }
        }

        os_log(
            "Solar schedule: sunset=%{public}@ sunrise=%{public}@ inWindow=%{public}@",
            log: log, type: .debug,
            adjustedSunset.description, adjustedSunrise.description, isWithinSchedule ? "YES" : "NO"
        )
    }

    deinit {
        timer?.invalidate()
    }
}
