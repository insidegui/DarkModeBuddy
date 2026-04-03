//
//  SettingsView.swift
//  DarkModeBuddy
//
//  Created by Guilherme Rambo on 23/02/21.
//

import SwiftUI
import DarkModeBuddyCore

private extension View {
    @ViewBuilder
    func disabledAppearance(_ isDisabled: Bool) -> some View {
        if isDisabled {
            self.foregroundColor(Color(NSColor.disabledControlTextColor))
        } else {
            self
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var reader: DMBAmbientLightSensorReader
    @EnvironmentObject var settings: DMBSettings
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var timeScheduleManager: TimeScheduleManager

    private let darknessInterval: ClosedRange<Double> = 0...400

    @State private var isShowingDarknessValueOutOfBoundsAlert = false
    @State private var isEditingAmbientLightLevelManually = false
    @State private var editingAmbientLightManuallyTextFieldStore = ""
    @State private var selectedTimeMode: TimeScheduleMode = .fixedTime

    private static let hourOptions = Array(0...23)
    private static let minuteOptions = [0, 15, 30, 45]

    // Non-linear duration steps: 5s increments to 60s, 15s to 3min, 1min to 10min
    private static let durationSteps: [Double] = {
        var steps = [Double]()
        for s in stride(from: 5.0, through: 60.0, by: 5.0) { steps.append(s) }
        for s in stride(from: 75.0, through: 180.0, by: 15.0) { steps.append(s) }
        for s in stride(from: 240.0, through: 600.0, by: 60.0) { steps.append(s) }
        return steps
    }()

    var body: some View {

        Group {
            if reader.isSensorReady {
                settingsControls
            } else {
                UnsupportedMacView()
            }
        }
        .fixedSize(horizontal: true, vertical: true)
        .padding([.top, .bottom], 22)
        .padding([.leading, .trailing], 22)
        .onAppear {
            reader.activate()
            if settings.timeScheduleMode != .disabled {
                selectedTimeMode = settings.timeScheduleMode
            }
        }
    }

    private var settingsControls: some View {
        VStack(alignment: .leading, spacing: 32) {
            Toggle(
                "Launch at login",
                isOn: $settings.isLaunchAtLoginEnabled
            )

            Toggle(
                "Change theme automatically",
                isOn: $settings.isChangeSystemAppearanceBasedOnAmbientLightEnabled
            )

            Group {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Go dark when ambient light falls below:")

                    HStack(alignment: .firstTextBaseline) {
                        Slider(value: $settings.darknessThreshold, in: darknessInterval)
                            .frame(maxWidth: 330)
                        if isEditingAmbientLightLevelManually {
                            TextField("", text: $editingAmbientLightManuallyTextFieldStore, onCommit: {
                                guard let newValue = Double(editingAmbientLightManuallyTextFieldStore),
                                      newValue >= darknessInterval.lowerBound,
                                      newValue <= darknessInterval.upperBound else {
                                    isShowingDarknessValueOutOfBoundsAlert = true
                                    return
                                }
                                settings.darknessThreshold = newValue
                                isEditingAmbientLightLevelManually = false
                            })
                            .frame(maxWidth: 35)
                        } else {
                            Text("\(settings.darknessThreshold.formattedNoFractionDigits)")
                                .font(.system(size: 12, weight: .medium).monospacedDigit())
                                .frame(width: 35).onTapGesture(count: 2)
                                {
                                    self.editingAmbientLightManuallyTextFieldStore = "\(settings.darknessThreshold.formattedNoFractionDigits)"
                                    isEditingAmbientLightLevelManually = true
                                }
                        }
                    }
                    .alert(isPresented: $isShowingDarknessValueOutOfBoundsAlert) {
                        Alert(title: Text("Error"),
                              message: Text("The threshold value must be in the interval [\(darknessInterval.lowerBound.formattedNoFractionDigits), \(darknessInterval.upperBound.formattedNoFractionDigits)]"),
                              dismissButton: .default(Text("OK")))
                    }

                    currentLightIndicator
                        .frame(height: 5, alignment: .leading)
                        .frame(maxHeight: 5)
                        .frame(maxWidth: 330)
                        .padding(.bottom, 5)

                    HStack(alignment: .firstTextBaseline) {
                        Text("Current ambient light level:")
                        Text("\(reader.ambientLightValue.formattedNoFractionDigits)")
                            .font(.system(size: 12).monospacedDigit())
                    }
                    .font(.system(size: 12))
                    .foregroundColor(Color(NSColor.secondaryLabelColor))


                    Text("Duration threshold:")
                        .padding(.top, 22)

                    HStack(alignment: .firstTextBaseline) {
                        Slider(value: durationSliderBinding, in: 0...Double(Self.durationSteps.count - 1), step: 1)
                            .frame(maxWidth: 330)
                        Text(settings.darknessThresholdIntervalInSeconds.formattedTime)
                            .font(.system(size: 12, weight: .medium).monospacedDigit())
                            .frame(width: 35)
                    }
                }

                // MARK: - Time Constraints Section

                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Time constraints", isOn: timeConstraintsBinding)
                        .padding(.top, 16)

                    if settings.timeScheduleMode != .disabled {
                        Picker("Only change theme within:", selection: timeModePickerBinding) {
                            Text("Fixed time window").tag(TimeScheduleMode.fixedTime)
                            Text("Relative to sunset/sunrise").tag(TimeScheduleMode.solarRelative)
                        }
                        .pickerStyle(RadioGroupPickerStyle())
                        .padding(.leading, 8)

                        if selectedTimeMode == .fixedTime {
                            fixedTimeControls
                        }

                        if selectedTimeMode == .solarRelative {
                            solarRelativeControls
                        }
                    }
                }
            }
            .disabled(!settings.isChangeSystemAppearanceBasedOnAmbientLightEnabled)
            .disabledAppearance(!settings.isChangeSystemAppearanceBasedOnAmbientLightEnabled)

            statusLineView
        }
    }

    // MARK: - Duration Slider Binding

    private var durationSliderBinding: Binding<Double> {
        Binding(
            get: {
                let steps = Self.durationSteps
                let value = settings.darknessThresholdIntervalInSeconds
                // Find the closest step index
                let idx = steps.enumerated().min(by: { abs($0.element - value) < abs($1.element - value) })?.offset ?? 0
                return Double(idx)
            },
            set: { newIndex in
                let idx = Int(newIndex.rounded())
                let steps = Self.durationSteps
                guard idx >= 0 && idx < steps.count else { return }
                settings.darknessThresholdIntervalInSeconds = steps[idx]
            }
        )
    }

    // MARK: - Time Constraints Bindings

    private var timeConstraintsBinding: Binding<Bool> {
        Binding(
            get: { settings.timeScheduleMode != .disabled },
            set: { enabled in
                if enabled {
                    settings.timeScheduleMode = selectedTimeMode
                } else {
                    settings.timeScheduleMode = .disabled
                }
            }
        )
    }

    private var timeModePickerBinding: Binding<TimeScheduleMode> {
        Binding(
            get: { selectedTimeMode },
            set: { newMode in
                selectedTimeMode = newMode
                if settings.timeScheduleMode != .disabled {
                    settings.timeScheduleMode = newMode
                }
            }
        )
    }

    // MARK: - Fixed Time Controls

    private var fixedTimeControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack() {
                Text("Start:")
                    .frame(width: 35, alignment: .leading)
                Picker("", selection: $settings.fixedStartHour) {
                    ForEach(Self.hourOptions, id: \.self) { h in
                        Text(String(format: "%02d", h)).tag(h)
                    }
                }
                .frame(width: 60)
                Text(":")
                Picker("", selection: $settings.fixedStartMinute) {
                    ForEach(Self.minuteOptions, id: \.self) { m in
                        Text(String(format: "%02d", m)).tag(m)
                    }
                }
                .frame(width: 60)
            }

            HStack {
                Text("End:")
                    .frame(width: 35, alignment: .leading)
                Picker("", selection: $settings.fixedEndHour) {
                    ForEach(Self.hourOptions, id: \.self) { h in
                        Text(String(format: "%02d", h)).tag(h)
                    }
                }
                .frame(width: 60)
                Text(":")
                Picker("", selection: $settings.fixedEndMinute) {
                    ForEach(Self.minuteOptions, id: \.self) { m in
                        Text(String(format: "%02d", m)).tag(m)
                    }
                }
                .frame(width: 60)
            }
        }
        .padding(.leading, 8)
    }

    // MARK: - Solar Relative Controls

    private var solarRelativeControls: some View {
        VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 6){
                        let startDropdown = Picker("", selection: $settings.sunsetOffsetMinutes) {
                            ForEach(SolarOffset.allCases) { offset in
                                Text(sunsetLabel(for: offset)).tag(offset.rawValue)
                            }
                        }
                        .frame(width: 180, alignment: .leading)
                        
                        HStack {
                            Text("Start:").frame(width: 35, alignment: .leading)
                            if #available(macOS 26.0, *) {
                                startDropdown.buttonSizing(.flexible)
                            } else {
                                startDropdown
                            }
                        }
                        let endDropdown = Picker("", selection: $settings.sunriseOffsetMinutes) {
                            ForEach(SolarOffset.allCases) { offset in
                                Text(sunriseLabel(for: offset)).tag(offset.rawValue)
                            }
                        }
                        .frame(width: 180, alignment: .leading)
                        
                        HStack {
                            Text("End:")
                                .frame(width: 35, alignment: .leading)
                            if #available(macOS 26.0, *) {
                                endDropdown.buttonSizing(.flexible)
                            } else {
                                endDropdown
                            }
                        }
                    }
                    if locationManager.hasLocation {
                        solarTimesDisplay
                    }
                
            }

            if !locationManager.hasLocation {
                HStack(spacing: 10) {
                    Text("\u{26A0} Location required for sunrise/sunset calculation.")
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                    Button("Grant permission") {
                        locationManager.requestPermission()
                    }
                    .font(.system(size: 11))
                }.frame(height: 30, alignment: .trailing)
            }

            if let error = locationManager.locationError {
                Text("Location error: \(error)")
                    .font(.system(size: 11))
                    .foregroundColor(.red)
            }
        }
        .padding(.leading, 8)
    }

    private var solarTimesDisplay: some View {
        VStack(alignment: .center, spacing: 13) {
            if let sunset = timeScheduleManager.computedSunset {
                HStack(spacing: 4) {
                    Text("Adjusted time:")
                    Text(sunset.formattedTime)
                        .fontWeight(.medium)
                }
                .font(.system(size: 11))
                .foregroundColor(Color(NSColor.secondaryLabelColor))
            }
            if let sunrise = timeScheduleManager.computedSunrise {
                HStack(spacing: 4) {
                    Text("Adjusted time:")
                    Text(sunrise.formattedTime)
                        .fontWeight(.medium)
                }
                .font(.system(size: 11))
                .foregroundColor(Color(NSColor.secondaryLabelColor))
            }
        }
    }

    // MARK: - Status Line

    private var statusLineView: some View {
        HStack(alignment: .top, spacing: 6) {
            Circle()
                .fill(statusBulletColor)
                .frame(width: 8, height: 8)
                .padding(.top, 3)
            Text(statusText)
                .font(.system(size: 11))
                .foregroundColor(Color(NSColor.tertiaryLabelColor))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 350, minHeight: 40, alignment: .topLeading)
        }
    }

    private var statusBulletColor: Color {
        if !settings.isChangeSystemAppearanceBasedOnAmbientLightEnabled {
            return .gray
        }
        if settings.timeScheduleMode != .disabled && !timeScheduleManager.isWithinSchedule {
            return .gray
        }
        return .green
    }

    private var statusText: String {
        guard settings.isChangeSystemAppearanceBasedOnAmbientLightEnabled else {
            let isAuto = UserDefaults.standard.bool(forKey: "AppleInterfaceStyleSwitchesAutomatically")
            if isAuto {
                return "DarkModeBuddy is off, switching is managed by macOS."
            }
            let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            if isDark {
                return "DarkModeBuddy is off, dark mode is set by macOS."
            }
            return "DarkModeBuddy is off, light mode is set by macOS."
        }

        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let threshold = settings.darknessThreshold.formattedNoFractionDigits
        let duration = settings.darknessThresholdIntervalInSeconds.formattedLongTime
        let timeConstraintsOn = settings.timeScheduleMode != .disabled

        if timeConstraintsOn {
            if !timeScheduleManager.isWithinSchedule {
                let startTime = scheduleStartTimeString
                return "Automatic switching is temporarily disabled until \(startTime). After that, dark mode will be enabled when ambient light stays below \(threshold) for over \(duration)."
            } else {
                let endTime = scheduleEndTimeString
                if isDark {
                    return "Automatic switching is active until \(endTime). Light mode will be enabled when ambient light stays above \(threshold) for over \(duration), or at \(endTime)."
                } else {
                    return "Automatic switching is active until \(endTime). Dark mode will be enabled when ambient light stays below \(threshold) for over \(duration)."
                }
            }
        } else {
            if isDark {
                return "Automatic switching is active. Light mode will be enabled when ambient light stays above \(threshold) for over \(duration)."
            } else {
                return "Automatic switching is active. Dark mode will be enabled when ambient light stays below \(threshold) for over \(duration)."
            }
        }
    }

    private var scheduleStartTimeString: String {
        switch settings.timeScheduleMode {
        case .fixedTime:
            return String(format: "%02d:%02d", settings.fixedStartHour, settings.fixedStartMinute)
        case .solarRelative:
            if let sunset = timeScheduleManager.computedSunset {
                return sunset.formattedTime
            }
            return "\u{2014}"
        case .disabled:
            return "\u{2014}"
        }
    }

    private var scheduleEndTimeString: String {
        switch settings.timeScheduleMode {
        case .fixedTime:
            return String(format: "%02d:%02d", settings.fixedEndHour, settings.fixedEndMinute)
        case .solarRelative:
            if let sunrise = timeScheduleManager.computedSunrise {
                return sunrise.formattedTime
            }
            return "\u{2014}"
        case .disabled:
            return "\u{2014}"
        }
    }

    // MARK: - Current Light Indicator

    private var currentLightIndicator: some View {
        GeometryReader { geometry in
            let range = darknessInterval.upperBound - darknessInterval.lowerBound
            let clampedValue = min(max(reader.ambientLightValue, darknessInterval.lowerBound), darknessInterval.upperBound)
            let fraction = CGFloat((clampedValue - darknessInterval.lowerBound) / range)
            let trackInset: CGFloat = 8
            let trackWidth = geometry.size.width - trackInset * 2
            let xPosition = trackInset + trackWidth * fraction

            Text("\u{25B2}")
                .font(.system(size: 6))
                .foregroundColor(Color(NSColor.secondaryLabelColor))
                .position(x: xPosition, y: geometry.size.height / 2)
        }
    }

    // MARK: - Helpers

    private func sunsetLabel(for offset: SolarOffset) -> String {
        switch offset.rawValue {
        case let v where v < 0: return "\(offset.label) before sunset"
        case 0: return "At sunset"
        default: return "\(offset.label) after sunset"
        }
    }

    private func sunriseLabel(for offset: SolarOffset) -> String {
        switch offset.rawValue {
        case let v where v < 0: return "\(offset.label) before sunrise"
        case 0: return "At sunrise"
        default: return "\(offset.label) after sunrise"
        }
    }
}

extension NumberFormatter {
    static let noFractionDigits: NumberFormatter = {
        let f = NumberFormatter()
        
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        
        return f
    }()
}

extension Double {
    var formattedNoFractionDigits: String {
        NumberFormatter.noFractionDigits.string(from: NSNumber(value: self)) ?? "!!!"
    }
    var formattedTime: String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .positional
        let str = formatter.string(from: self) ?? "!!!"
        return self < 60 ? str + "s" : str
    }
    var formattedLongTime: String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        return formatter.string(from: self) ?? "!!!"
    }
}

extension Date {
    var formattedTime: String {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f.string(from: self)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        let settings = DMBSettings(forPreview: true)
        let locMgr = LocationManager()
        let schedMgr = TimeScheduleManager(settings: settings, locationManager: locMgr)
        SettingsView()
            .frame(maxWidth: 385)
            .environmentObject(DMBAmbientLightSensorReader(frequency: .realtime))
            .environmentObject(settings)
            .environmentObject(locMgr)
            .environmentObject(schedMgr)
            .previewLayout(.sizeThatFits)
    }
}
