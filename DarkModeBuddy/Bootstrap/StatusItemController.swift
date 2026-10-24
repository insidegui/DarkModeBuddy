//
//  StatusItemController.swift
//  DarkModeBuddy
//
//  Created by Michel Storms on 22/10/2026.
//

import Cocoa
import Combine
import DarkModeBuddyCore
import Sparkle

/// The menu bar icon, with quick access to the main settings.
final class StatusItemController: NSObject, NSMenuDelegate {

    private let settings: DMBSettings
    private let reader: DMBAmbientLightSensorReader
    private let showSettings: () -> Void

    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()

    init(settings: DMBSettings, reader: DMBAmbientLightSensorReader, showSettings: @escaping () -> Void) {
        self.settings = settings
        self.reader = reader
        self.showSettings = showSettings

        super.init()

        settings.$isMenuBarIconEnabled.sink { [weak self] isEnabled in
            self?.setStatusItemVisible(isEnabled)
        }.store(in: &cancellables)
    }

    private func setStatusItemVisible(_ isVisible: Bool) {
        guard isVisible else {
            if let statusItem = statusItem {
                NSStatusBar.system.removeStatusItem(statusItem)
            }
            statusItem = nil
            return
        }

        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "circle.lefthalf.filled", accessibilityDescription: "DarkModeBuddy")

        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu

        statusItem = item
    }

    // MARK: - Menu

    /// Rebuilt on every open so it always reflects the current state.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        // The reader reports -1 until it has a reading.
        let lightValue = reader.ambientLightValue < 0 ? "—" : reader.ambientLightValue.formattedNoFractionDigits
        let lightItem = NSMenuItem(title: "Ambient Light: \(lightValue)", action: nil, keyEquivalent: "")
        lightItem.isEnabled = false
        menu.addItem(lightItem)

        menu.addItem(.separator())

        let autoItem = item("Change Theme Automatically", action: #selector(toggleAutomaticChange))
        autoItem.state = settings.isChangeSystemAppearanceBasedOnAmbientLightEnabled ? .on : .off
        menu.addItem(autoItem)

        let clamshellMenu = NSMenu()
        for appearance in DMBSettings.ClamshellAppearance.allCases {
            let appearanceItem = item(appearance.title, action: #selector(selectClamshellAppearance(_:)))
            appearanceItem.tag = appearance.rawValue
            appearanceItem.state = settings.clamshellAppearance == appearance ? .on : .off
            clamshellMenu.addItem(appearanceItem)
        }
        let clamshellItem = NSMenuItem(title: "With Lid Closed", action: nil, keyEquivalent: "")
        clamshellItem.submenu = clamshellMenu
        menu.addItem(clamshellItem)

        menu.addItem(.separator())

        menu.addItem(item("Settings…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(item("Check for Updates…", action: #selector(checkForUpdates)))

        menu.addItem(.separator())

        // Same path as the app menu's Quit, which skips the confirmation on unsupported Macs.
        let quitItem = NSMenuItem(title: "Quit DarkModeBuddy", action: #selector(AppDelegate.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp.delegate
        menu.addItem(quitItem)
    }

    private func item(_ title: String, action: Selector, keyEquivalent: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    @objc private func toggleAutomaticChange() {
        settings.isChangeSystemAppearanceBasedOnAmbientLightEnabled.toggle()
    }

    @objc private func selectClamshellAppearance(_ sender: NSMenuItem) {
        guard let appearance = DMBSettings.ClamshellAppearance(rawValue: sender.tag) else { return }
        settings.clamshellAppearance = appearance
    }

    @objc private func openSettings() {
        showSettings()
    }

    @objc private func checkForUpdates() {
        SUUpdater.shared()?.checkForUpdates(nil)
    }

}
