//
//  LocationManager.swift
//  DarkModeBuddyCore
//
//  Manages location access for solar calculations.
//

import Foundation
import CoreLocation
import Combine

public final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {

    private let manager = CLLocationManager()

    @Published public var latitude: Double?
    @Published public var longitude: Double?
    @Published public var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published public var locationError: String?

    public var hasLocation: Bool { latitude != nil && longitude != nil }

    public override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        // authorizationStatus will be updated via the delegate callback
        // which fires when the delegate is first assigned
    }

    public func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    public func requestLocation() {
        guard isAuthorized else {
            requestPermission()
            return
        }
        fetchLocation()
    }

    private var isAuthorized: Bool {
        let status: CLAuthorizationStatus
        if #available(macOS 11.0, *) {
            status = manager.authorizationStatus
        } else {
            status = CLLocationManager.authorizationStatus()
        }
        return status != .notDetermined && status != .denied && status != .restricted
    }

    private func fetchLocation() {
        // Use cached location for immediate display
        if let cached = manager.location {
            latitude = cached.coordinate.latitude
            longitude = cached.coordinate.longitude
            locationError = nil
        }
        // Also request a fresh location update
        manager.startUpdatingLocation()
    }

    // MARK: - CLLocationManagerDelegate

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        latitude = location.coordinate.latitude
        longitude = location.coordinate.longitude
        locationError = nil
        manager.stopUpdatingLocation()
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Ignore transient "location unknown" errors — Core Location will keep trying
        if let clError = error as? CLError, clError.code == .locationUnknown {
            return
        }
        locationError = error.localizedDescription
    }

    // Modern delegate method (macOS 11+) — called when delegate is first set and on auth changes
    @available(macOS 11.0, *)
    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if isAuthorized {
            fetchLocation()
        }
    }

    // Legacy delegate method for macOS 10.15
    public func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        authorizationStatus = status
        if isAuthorized {
            fetchLocation()
        }
    }
}
