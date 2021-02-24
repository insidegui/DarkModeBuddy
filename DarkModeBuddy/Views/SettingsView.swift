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
    
    var body: some View {
        Group {
            if reader.isSensorReady {
                settingsControls
            } else {
                UnsupportedMacView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .onAppear { reader.activate() }
    }
    
    private var settingsControls: some View {
        VStack(spacing: 32) {
            Toggle(
                "Change Theme Automatically",
                isOn: $settings.isChangeSystemAppearanceBasedOnAmbientLightEnabled
            )
            
            Group {
                VStack(spacing: 2) {
                    HStack {
                        Text("Go Dark When Ambient Light Falls Bellow:")
                        Text("\(settings.darknessThreshold.formattedNoFractionDigits)")
                            .font(.system(size: 13, weight: .medium).monospacedDigit())
                    }
                    
                    Slider(value: $settings.darknessThreshold, in: 0...2000)
                        .frame(maxWidth: 300)
                    
                    HStack {
                        Text("Current Ambient Light Level:")
                        Text("\(reader.ambientLightValue.formattedNoFractionDigits)")
                            .font(.system(size: 12).monospacedDigit())
                    }
                    .font(.system(size: 12))
                    .foregroundColor(Color(NSColor.secondaryLabelColor))
                    
                    HStack {
                        Text("Delay Time:")
                        Text("\(settings.darknessThresholdIntervalInSeconds.formattedNoFractionDigits)s")
                            .font(.system(size: 13, weight: .medium).monospacedDigit())
                    }
                    .padding(.top, 22)
                    
                    Slider(value: $settings.darknessThresholdIntervalInSeconds, in: 10...600)
                        .frame(maxWidth: 300)
                }
            }
            .disabled(!settings.isChangeSystemAppearanceBasedOnAmbientLightEnabled)
            
            Text(settings.currentSettingsDescription)
                .font(.callout)
                .foregroundColor(Color(NSColor.tertiaryLabelColor))
                .multilineTextAlignment(.center)
                .lineLimit(nil)
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
}

extension DMBSettings {
    var currentSettingsDescription: String {
        guard isChangeSystemAppearanceBasedOnAmbientLightEnabled else {
            return "Dark mode will not be enabled automatically based on ambient light."
        }
        
        return "Dark mode will be enabled when the ambient light stays below \(darknessThreshold.formattedNoFractionDigits) for over \(darknessThresholdIntervalInSeconds.formattedNoFractionDigits) seconds."
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
            .environmentObject(DMBAmbientLightSensorReader(frequency: .realtime))
            .environmentObject(DMBSettings())
            .previewLayout(.sizeThatFits)
    }
}
