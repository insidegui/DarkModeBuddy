//
//  SettingsView.swift
//  DarkModeBuddy
//
//  Created by Guilherme Rambo on 23/02/21.
//

import SwiftUI
import DarkModeBuddyCore

struct SettingsView: View {
    @EnvironmentObject var reader: DMBAmbientLightSensorReader
    @EnvironmentObject var settings: DMBSettings

    private let darknessInterval: ClosedRange<Double> = 0...30000
    
    /// Finer steps at the low end, where typical indoor readings sit,
    /// with coarse steps up to bright rooms and direct daylight.
    private let darknessStops: [Double] = Array(stride(from: 0.0, to: 20, by: 1))
        + Array(stride(from: 20.0, to: 100, by: 5))
        + Array(stride(from: 100.0, to: 500, by: 25))
        + Array(stride(from: 500.0, to: 3000, by: 250))
        + Array(stride(from: 3000.0, to: 6000, by: 500))
        + Array(stride(from: 6000.0, through: 30000, by: 2000))
    
    private let revertMarginStops: [Double] = Array(stride(from: 1.0, to: 20, by: 1))
        + Array(stride(from: 20.0, to: 100, by: 5))
        + Array(stride(from: 100.0, through: 500, by: 25))
    
    private let delayStops: [Double] = Array(stride(from: 5.0, to: 60, by: 5))
        + Array(stride(from: 60.0, to: 300, by: 15))
        + Array(stride(from: 300.0, through: 600, by: 60))

    @State private var isShowingDarknessValueOutOfBoundsAlert = false
    @State private var isEditingAmbientLightLevelManually = false
    @State private var editingAmbientLightManuallyTextFieldStore = ""
    
    var body: some View {
        Group {
            if reader.isSensorReady {
                settingsControls
            } else {
                UnsupportedMacView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding([.top, .bottom])
        .padding([.leading, .trailing], 22)
        .onAppear { reader.activate() }
    }
    
    private var settingsControls: some View {
        VStack(alignment: .leading, spacing: 32) {
            Toggle(
                "Launch at Login",
                isOn: $settings.isLaunchAtLoginEnabled
            )
            
            Toggle(
                "Show in Menu Bar",
                isOn: $settings.isMenuBarIconEnabled
            )
            
            Toggle(
                "Change Theme Automatically",
                isOn: $settings.isChangeSystemAppearanceBasedOnAmbientLightEnabled
            )
            
            Group {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Go Dark When Ambient Light Falls Below:")
                    
                    HStack(alignment: .firstTextBaseline) {
                        SteppedSlider(value: $settings.darknessThreshold, stops: darknessStops)
                            .frame(maxWidth: 300)
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
                            .frame(maxWidth: 40)
                        } else {
                            Text("\(settings.darknessThreshold.formattedNoFractionDigits)")
                                .font(.system(size: 12, weight: .medium).monospacedDigit())
                                .onTapGesture(count: 2) {
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
                    
                    HStack(alignment: .firstTextBaseline) {
                        Text("Current Ambient Light Level:")
                        Text("\(reader.ambientLightValue.formattedNoFractionDigits)")
                            .font(.system(size: 12).monospacedDigit())
                    }
                    .font(.system(size: 12))
                    .foregroundColor(Color(NSColor.secondaryLabelColor))
                    
                    Text("Go Light Again When Ambient Light Rises Above:")
                        .padding(.top, 22)
                    
                    HStack(alignment: .firstTextBaseline) {
                        SteppedSlider(value: $settings.extraThresholdBeforeRevertingToLightMode, stops: revertMarginStops)
                            .frame(maxWidth: 300)
                        Text("\(settings.lightThreshold.formattedNoFractionDigits)")
                            .font(.system(size: 12, weight: .medium).monospacedDigit())
                    }
                    
                    Text("Dark level + \(settings.extraThresholdBeforeRevertingToLightMode.formattedNoFractionDigits), to avoid flipping back and forth.")
                        .font(.system(size: 12))
                        .foregroundColor(Color(NSColor.secondaryLabelColor))
                    
                    Text("Delay Time:")
                        .padding(.top, 22)
                    
                    HStack(alignment: .firstTextBaseline) {
                        SteppedSlider(value: $settings.darknessThresholdIntervalInSeconds, stops: delayStops)
                        Text(settings.darknessThresholdIntervalInSeconds.formattedTime)
                            .font(.system(size: 12, weight: .medium).monospacedDigit())
                            .frame(width: 50, alignment: .trailing)
                    }
                }
            }
            .disabled(!settings.isChangeSystemAppearanceBasedOnAmbientLightEnabled)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text("With Lid Closed:")
                    
                    Picker("With Lid Closed:", selection: $settings.clamshellAppearance) {
                        ForEach(DMBSettings.ClamshellAppearance.allCases) { appearance in
                            Text(appearance.title).tag(appearance)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 140)
                }
                
                Text("When using an external display with the lid closed, use this theme and pause automatic switching, including macOS’ own.")
                    .font(.system(size: 11))
                    .foregroundColor(Color(NSColor.secondaryLabelColor))
                    // A fixed width lets this wrap without inflating the window's minimum height.
                    .frame(width: 340, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Text(settings.currentSettingsDescription)
                .font(.system(size: 11))
                .foregroundColor(Color(NSColor.tertiaryLabelColor))
//                .multilineTextAlignment(.center)
                .lineLimit(nil)
        }
    }
}

/// A slider that snaps to the given stops, with a haptic tick on each step.
struct SteppedSlider: View {
    @Binding var value: Double
    let stops: [Double]
    
    private var index: Binding<Double> {
        Binding(
            get: {
                let nearest = stops.indices.min { abs(stops[$0] - value) < abs(stops[$1] - value) } ?? 0
                return Double(nearest)
            },
            set: { newIndex in
                let newValue = stops[min(max(Int(newIndex.rounded()), 0), stops.count - 1)]
                guard newValue != value else { return }
                
                value = newValue
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
        )
    }
    
    var body: some View {
        Slider(value: index, in: 0...Double(stops.count - 1), step: 1)
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
        return (formatter.string(from: self) ?? "!!!" ) + "s"
    }
    var formattedLongTime: String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        return formatter.string(from: self) ?? "!!!"
    }
}

extension DMBSettings {
    var currentSettingsDescription: String {
        guard isChangeSystemAppearanceBasedOnAmbientLightEnabled else {
            return "Dark Mode will not be enabled automatically based on ambient light."
        }
        
        return "Dark Mode will be enabled when the ambient light stays below \(darknessThreshold.formattedNoFractionDigits) for over \(darknessThresholdIntervalInSeconds.formattedLongTime), and Light Mode when it stays above \(lightThreshold.formattedNoFractionDigits) for as long."
    }
    
    /// The level ambient light must rise above to switch back from Dark Mode to Light Mode.
    var lightThreshold: Double {
        darknessThreshold + extraThresholdBeforeRevertingToLightMode
    }
}

extension DMBSettings.ClamshellAppearance {
    var title: String {
        switch self {
        case .unchanged:
            return "Don't Change"
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
            .frame(maxWidth: 385)
            .environmentObject(DMBAmbientLightSensorReader(frequency: .realtime))
            .environmentObject(DMBSettings(forPreview: true))
            .previewLayout(.sizeThatFits)
    }
}
