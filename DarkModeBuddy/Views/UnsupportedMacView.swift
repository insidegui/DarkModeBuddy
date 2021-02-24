//
//  UnsupportedMacView.swift
//  DarkModeBuddy
//
//  Created by Guilherme Rambo on 24/02/21.
//

import SwiftUI

struct UnsupportedMacView: View {
    var body: some View {
        VStack {
            Text("Sorry, I couldn't find an ambient light sensor on your Mac.")
                .multilineTextAlignment(.center)
                .lineLimit(nil)
                .foregroundColor(Color(NSColor.secondaryLabelColor))
                .font(.system(size: 12, weight: .medium))
            
            Button(action: {
                NSApp.terminate(nil)
            }, label: {
                Text("Quit")
            })
        }
    }
}

struct UnsupportedMacView_Previews: PreviewProvider {
    static var previews: some View {
        UnsupportedMacView()
    }
}
