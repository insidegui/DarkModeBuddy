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
                "Change Theme Automatically",
                isOn: $settings.isChangeSystemAppearanceBasedOnAmbientLightEnabled
            )
            
            Group {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Go Dark When Ambient Light Falls Below:")
                    
                    HStack(alignment: .firstTextBaseline) {
                        Slider(value: $settings.darknessThreshold, in: 0...2000)
                            .frame(maxWidth: 300)
                        Text("\(settings.darknessThreshold.formattedNoFractionDigits)")
                            .font(.system(size: 12, weight: .medium).monospacedDigit())
                    }
                    
                    HStack(alignment: .firstTextBaseline) {
                        Text("Current Ambient Light Level:")
                        Text("\(reader.ambientLightValue.formattedNoFractionDigits)")
                            .font(.system(size: 12).monospacedDigit())
                    }
                    .font(.system(size: 12))
                    .foregroundColor(Color(NSColor.secondaryLabelColor))
                    
                    
                    Text("Delay Time:")
                        .padding(.top, 22)
                    
                    HStack(alignment: .firstTextBaseline) {
                        Slider(value: $settings.darknessThresholdIntervalInSeconds, in: 10...600)
                            .frame(maxWidth: 300)
                        Text("\(settings.darknessThresholdIntervalInSeconds.formattedNoFractionDigits) s")
                            .font(.system(size: 12, weight: .medium).monospacedDigit())
                    }
                }
            }
            .disabled(!settings.isChangeSystemAppearanceBasedOnAmbientLightEnabled)
            
            Text(settings.currentSettingsDescription)
                .font(.callout)
                .foregroundColor(Color(NSColor.tertiaryLabelColor))
//                .multilineTextAlignment(.center)
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
            return "Dark Mode will not be enabled automatically based on ambient light."
        }
        
        return "Dark Mode will be enabled when the ambient light stays below \(darknessThreshold.formattedNoFractionDigits) for over \(darknessThresholdIntervalInSeconds.formattedNoFractionDigits) seconds."
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
