//
//  ClaudeNeinApp.swift
//  ClaudeNein
//
//  Created by Forketyfork on 21.07.25.
//

import SwiftUI
import AppKit

@main
struct ClaudeNeinApp: App {
    @StateObject private var menuBarManager = MenuBarManager()
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class MenuBarManager: ObservableObject {
    private var statusItem: NSStatusItem?
    
    init() {
        setupMenuBar()
    }
    
    deinit {
        statusItem = nil
    }
    
    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        guard let statusButton = statusItem?.button else { return }
        
        statusButton.title = "$0.00"
        statusButton.action = #selector(menuBarButtonClicked)
        statusButton.target = self
        
        setupMenu()
    }
    
    private func setupMenu() {
        let menu = NSMenu()
        
        let todayItem = NSMenuItem(title: "Today: $0.00", action: nil, keyEquivalent: "")
        todayItem.isEnabled = false
        menu.addItem(todayItem)
        
        let weekItem = NSMenuItem(title: "This Week: $0.00", action: nil, keyEquivalent: "")
        weekItem.isEnabled = false
        menu.addItem(weekItem)
        
        let monthItem = NSMenuItem(title: "This Month: $0.00", action: nil, keyEquivalent: "")
        monthItem.isEnabled = false
        menu.addItem(monthItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let refreshItem = NSMenuItem(title: "Refresh", action: #selector(refreshData), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit ClaudeNein", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem?.menu = menu
    }
    
    @objc private func menuBarButtonClicked() {
        // This will be handled by the menu automatically
    }
    
    @objc private func refreshData() {
        // TODO: Implement data refresh
        print("Refreshing data...")
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
