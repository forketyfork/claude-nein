//
//  ClaudeNeinApp.swift
//  ClaudeNein
//
//  Created by Forketyfork on 21.07.25.
//

import SwiftUI
import AppKit
import Combine

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
        setupMenuBar()
        setupFileMonitoring()
    }
    
    deinit {
        statusItem = nil
        fileMonitor.stopMonitoring()
    }
    
    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        guard let statusButton = statusItem?.button else { return }
        
        updateStatusBarTitle()
        statusButton.action = #selector(menuBarButtonClicked)
        statusButton.target = self
        
        setupMenu()
    }
    
    private func setupFileMonitoring() {
        // Subscribe to file changes
        fileMonitor.fileChanges
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshSpendingSummary()
            }
            .store(in: &cancellables)
        
        // Subscribe to summary changes to update UI
        $currentSummary
            .receive(on: DispatchQueue.main)
            .sink { [weak self] summary in
                self?.updateStatusBarTitle()
                self?.updateMenu()
            }
            .store(in: &cancellables)
        
        // Start monitoring
        fileMonitor.startMonitoring()
        
        // Initial data refresh
        refreshSpendingSummary()
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
        fileMonitor.forceRefresh()
        refreshSpendingSummary()
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
    
    // MARK: - Private Helper Methods
    
    private func refreshSpendingSummary() {
        let entries = fileMonitor.getCachedEntries()
        let newSummary = spendCalculator.calculateSpendSummary(from: entries)
        
        DispatchQueue.main.async { [weak self] in
            self?.currentSummary = newSummary
        }
    }
    
    private func updateStatusBarTitle() {
        guard let statusButton = statusItem?.button else { return }
        statusButton.title = formatCurrency(currentSummary.todaySpend)
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
