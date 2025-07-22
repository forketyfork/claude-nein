//
//  ClaudeNeinApp.swift
//  ClaudeNein
//
//  Created by Forketyfork on 21.07.25.
//

import SwiftUI
import AppKit
import Combine
import OSLog

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
    private let fileMonitor = FileMonitor()
    private let spendCalculator = SpendCalculator()
    private var cancellables = Set<AnyCancellable>()
    
    @Published private var currentSummary = SpendSummary.empty
    
    init() {
        Logger.app.info("🚀 Initializing ClaudeNein MenuBarManager")
        setupMenuBar()
        setupFileMonitoring()
        Logger.app.info("✅ ClaudeNein MenuBarManager initialized successfully")
    }
    
    deinit {
        Logger.app.info("🛑 Deinitializing MenuBarManager")
        statusItem = nil
        fileMonitor.stopMonitoring()
        Logger.app.info("✅ MenuBarManager deinitialized")
    }
    
    private func setupMenuBar() {
        Logger.menuBar.debug("🔧 Setting up menu bar")
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        guard let statusButton = statusItem?.button else { 
            Logger.menuBar.error("❌ Failed to get status button from status item")
            return 
        }
        
        updateStatusBarTitle()
        statusButton.action = #selector(menuBarButtonClicked)
        statusButton.target = self
        
        setupMenu()
        Logger.menuBar.info("✅ Menu bar setup completed")
    }
    
    private func setupFileMonitoring() {
        Logger.fileMonitor.debug("🔧 Setting up file monitoring")
        
        // Subscribe to file changes
        fileMonitor.fileChanges
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                Logger.fileMonitor.info("📁 File changes detected: \(notification.changedFiles.count) files")
                self?.refreshSpendingSummary()
            }
            .store(in: &cancellables)
        
        // Subscribe to summary changes to update UI
        $currentSummary
            .receive(on: DispatchQueue.main)
            .sink { [weak self] summary in
                Logger.menuBar.debug("📊 Updating UI with new spend summary")
                self?.updateStatusBarTitle()
                self?.updateMenu()
            }
            .store(in: &cancellables)
        
        // Subscribe to home directory access changes
        fileMonitor.homeDirectoryAccessManager.$hasAccess
            .receive(on: DispatchQueue.main)
            .sink { [weak self] hasAccess in
                Logger.security.info("🔒 Home directory access changed: \(hasAccess)")
                self?.updateMenu()
                if hasAccess {
                    Task {
                        await self?.fileMonitor.startMonitoring()
                    }
                }
            }
            .store(in: &cancellables)
        
        // Start monitoring asynchronously
        Task {
            await fileMonitor.startMonitoring()
            await MainActor.run {
                refreshSpendingSummary()
                Logger.fileMonitor.info("✅ File monitoring setup completed")
            }
        }
    }
    
    private func setupMenu() {
        updateMenu()
    }
    
    private func updateMenu() {
        let menu = NSMenu()
        
        let todayItem = NSMenuItem(title: formatCurrency(currentSummary.todaySpend, label: "Today"), action: nil, keyEquivalent: "")
        todayItem.isEnabled = false
        menu.addItem(todayItem)
        
        let weekItem = NSMenuItem(title: formatCurrency(currentSummary.weekSpend, label: "This Week"), action: nil, keyEquivalent: "")
        weekItem.isEnabled = false
        menu.addItem(weekItem)
        
        let monthItem = NSMenuItem(title: formatCurrency(currentSummary.monthSpend, label: "This Month"), action: nil, keyEquivalent: "")
        monthItem.isEnabled = false
        menu.addItem(monthItem)
        
        // Add model breakdown if available
        if !currentSummary.modelBreakdown.isEmpty {
            menu.addItem(NSMenuItem.separator())
            
            let breakdownHeader = NSMenuItem(title: "Model Breakdown:", action: nil, keyEquivalent: "")
            breakdownHeader.isEnabled = false
            menu.addItem(breakdownHeader)
            
            for (model, cost) in currentSummary.modelBreakdown.sorted(by: { $0.value > $1.value }) {
                let modelItem = NSMenuItem(title: "  \(model): \(formatCurrency(cost))", action: nil, keyEquivalent: "")
                modelItem.isEnabled = false
                menu.addItem(modelItem)
            }
        }
        
        menu.addItem(NSMenuItem.separator())
        
        let lastUpdated = NSMenuItem(title: "Updated: \(formatTime(currentSummary.lastUpdated))", action: nil, keyEquivalent: "")
        lastUpdated.isEnabled = false
        menu.addItem(lastUpdated)
        
        menu.addItem(NSMenuItem.separator())
        
        // Home directory access status
        let accessManager = fileMonitor.homeDirectoryAccessManager
        if accessManager.hasValidAccess {
            let accessItem = NSMenuItem(title: "✅ Home Directory Access: Granted", action: nil, keyEquivalent: "")
            accessItem.isEnabled = false
            menu.addItem(accessItem)
            
            let revokeItem = NSMenuItem(title: "Revoke Access", action: #selector(revokeAccess), keyEquivalent: "")
            revokeItem.target = self
            menu.addItem(revokeItem)
        } else {
            let accessItem = NSMenuItem(title: "❌ Home Directory Access: Required", action: nil, keyEquivalent: "")
            accessItem.isEnabled = false
            menu.addItem(accessItem)
            
            let grantItem = NSMenuItem(title: "Grant Access...", action: #selector(requestAccess), keyEquivalent: "")
            grantItem.target = self
            menu.addItem(grantItem)
        }
        
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
        Logger.app.info("🔄 Manual refresh requested")
        fileMonitor.forceRefresh()
        refreshSpendingSummary()
    }
    
    @objc private func requestAccess() {
        Logger.security.info("🔒 User requested home directory access")
        Task {
            let granted = await fileMonitor.homeDirectoryAccessManager.requestHomeDirectoryAccess()
            Logger.security.info("🔒 Home directory access request result: \(granted)")
        }
    }
    
    @objc private func revokeAccess() {
        Logger.security.info("🚫 User requested to revoke home directory access")
        fileMonitor.homeDirectoryAccessManager.revokeAccess()
        fileMonitor.stopMonitoring()
    }
    
    @objc private func quitApp() {
        Logger.app.info("👋 User requested app termination")
        NSApplication.shared.terminate(nil)
    }
    
    // MARK: - Private Helper Methods
    
    private func refreshSpendingSummary() {
        Logger.calculator.logTiming("Spending summary calculation") {
            fileMonitor.getCachedEntriesAsync { [weak self] entries in
                guard let self = self else { return }
                Logger.calculator.logDataProcessing("Spending calculation", count: entries.count)
                let newSummary = self.spendCalculator.calculateSpendSummary(from: entries)
                
                DispatchQueue.main.async {
                    self.currentSummary = newSummary
                    Logger.calculator.info("💰 Updated spend summary - Today: $\(String(format: "%.2f", newSummary.todaySpend))")
                }
            }
        }
    }
    
    private func updateStatusBarTitle() {
        guard let statusButton = statusItem?.button else { 
            Logger.menuBar.error("❌ Cannot update status bar title - no status button")
            return 
        }
        let title = formatCurrency(currentSummary.todaySpend)
        statusButton.title = title
        Logger.menuBar.debug("📱 Updated status bar title: \(title)")
    }
    
    private func formatCurrency(_ amount: Double, label: String? = nil) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "en_US")
        let formattedAmount = formatter.string(from: NSNumber(value: amount)) ?? "$0.00"
        
        if let label = label {
            return "\(label): \(formattedAmount)"
        }
        return formattedAmount
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
