//
//  SolarCalculator.swift
//  DarkModeBuddyCore
//
//  Calculates sunrise and sunset times using the NOAA solar equations.
//

import Foundation

public struct SolarCalculator {

    /// Returns (sunrise, sunset) as Dates for the given date and location,
    /// or nil if the sun doesn't rise or set at that location on that date.
    public static func sunriseSunset(
        for date: Date = Date(),
        latitude: Double,
        longitude: Double,
        timeZone: TimeZone = .current
    ) -> (sunrise: Date, sunset: Date)? {
        let cal = Calendar.current
        let dayOfYear = Double(cal.ordinality(of: .day, in: .year, for: date) ?? 1)
        let year = cal.component(.year, from: date)

        // Julian century from J2000.0
        let jd = julianDay(year: year, dayOfYear: dayOfYear)
        let jc = (jd - 2451545.0) / 36525.0

        // Solar calculations
        let geomMeanLongSun = fmod(280.46646 + jc * (36000.76983 + 0.0003032 * jc), 360.0)
        let geomMeanAnomSun = 357.52911 + jc * (35999.05029 - 0.0001537 * jc)
        let eccentEarthOrbit = 0.016708634 - jc * (0.000042037 + 0.0000001267 * jc)

        let sunEqOfCtr = sin(radians(geomMeanAnomSun)) * (1.914602 - jc * (0.004817 + 0.000014 * jc))
            + sin(radians(2.0 * geomMeanAnomSun)) * (0.019993 - 0.000101 * jc)
            + sin(radians(3.0 * geomMeanAnomSun)) * 0.000289

        let sunTrueLong = geomMeanLongSun + sunEqOfCtr
        let sunAppLong = sunTrueLong - 0.00569 - 0.00478 * sin(radians(125.04 - 1934.136 * jc))

        let meanObliqEcliptic = 23.0 + (26.0 + (21.448 - jc * (46.815 + jc * (0.00059 - jc * 0.001813))) / 60.0) / 60.0
        let obliqCorr = meanObliqEcliptic + 0.00256 * cos(radians(125.04 - 1934.136 * jc))

        let sinDeclination = sin(radians(obliqCorr)) * sin(radians(sunAppLong))
        let declination = degrees(asin(sinDeclination))

        let varY = tan(radians(obliqCorr / 2.0)) * tan(radians(obliqCorr / 2.0))

        let eqOfTime = 4.0 * degrees(
            varY * sin(2.0 * radians(geomMeanLongSun))
            - 2.0 * eccentEarthOrbit * sin(radians(geomMeanAnomSun))
            + 4.0 * eccentEarthOrbit * varY * sin(radians(geomMeanAnomSun)) * cos(2.0 * radians(geomMeanLongSun))
            - 0.5 * varY * varY * sin(4.0 * radians(geomMeanLongSun))
            - 1.25 * eccentEarthOrbit * eccentEarthOrbit * sin(2.0 * radians(geomMeanAnomSun))
        )

        // Hour angle for sunrise/sunset (solar zenith = 90.833°)
        let zenith = 90.833
        let cosHourAngle = (cos(radians(zenith)) / (cos(radians(latitude)) * cos(radians(declination))))
            - tan(radians(latitude)) * tan(radians(declination))

        // If cosHourAngle is out of [-1, 1], the sun doesn't rise or set
        guard cosHourAngle >= -1.0 && cosHourAngle <= 1.0 else { return nil }

        let hourAngle = degrees(acos(cosHourAngle))

        let tzOffset = Double(timeZone.secondsFromGMT(for: date)) / 3600.0

        // Solar noon in minutes from midnight
        let solarNoon = (720.0 - 4.0 * longitude - eqOfTime + tzOffset * 60.0)

        let sunriseMinutes = solarNoon - hourAngle * 4.0
        let sunsetMinutes = solarNoon + hourAngle * 4.0

        let startOfDay = cal.startOfDay(for: date)
        let sunrise = startOfDay.addingTimeInterval(sunriseMinutes * 60.0)
        let sunset = startOfDay.addingTimeInterval(sunsetMinutes * 60.0)

        return (sunrise, sunset)
    }

    // MARK: - Helpers

    private static func julianDay(year: Int, dayOfYear: Double) -> Double {
        // Approximate Julian Day for Jan 1 of the given year + day offset
        let a = Double(365 * (year + 4716))
        let b = Double(Int(Double(year + 4716) / 4.0))  // not exact but close enough for century calc
        // Use a simplified formula
        let y = Double(year)
        let jd0 = 367.0 * y - Double(Int(7.0 * (y + Double(Int((1.0 + 12.0) / 16.0))) / 4.0))
            + Double(Int(275.0 * 1.0 / 9.0)) + 1721013.5 - 0.5
        return jd0 + dayOfYear - 1.0
    }

    private static func radians(_ degrees: Double) -> Double {
        degrees * .pi / 180.0
    }

    private static func degrees(_ radians: Double) -> Double {
        radians * 180.0 / .pi
    }
}
