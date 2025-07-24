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
    private var rollingNumberView: RollingNumberNSView?
    
    private var cancellables = Set<AnyCancellable>()
    
    @Published private var currentSummary = SpendSummary.empty
    
    private let fileMonitor: FileMonitor
    private let homeDirectoryAccessManager: HomeDirectoryAccessManager
    private let dataStore = DataStore.shared
    
    init() {
        Logger.app.info("🚀 Initializing ClaudeNein MenuBarManager")
        self.homeDirectoryAccessManager = HomeDirectoryAccessManager()
        self.fileMonitor = FileMonitor(accessManager: homeDirectoryAccessManager)
        
        setupMenuBar()
        setupStateSubscriptions()
        
        // Start the main asynchronous initialization
        Task {
            await initializeSystem()
        }
        
        Logger.app.info("✅ ClaudeNein MenuBarManager initialized successfully")
    }
    
    private func initializeSystem() async {
        // 1. Load initial data from the database for immediate UI display
        await MainActor.run {
            self.currentSummary = dataStore.fetchSpendSummary()
            Logger.app.info("📊 Initial spend summary loaded from database.")
        }
        
        // 2. Initialize pricing data
        await PricingManager.shared.initializePricingData()
        Logger.app.info("💰 Pricing data initialization completed.")
        
        // 3. Request access and perform initial full scan of JSONL files
        let accessGranted = await homeDirectoryAccessManager.requestHomeDirectoryAccess()
        if accessGranted {
            Logger.app.info("✅ Access granted. Starting initial data processing.")
            await processAllJsonlFiles()
        } else {
            Logger.app.warning("⚠️ Access to home directory not granted. Functionality will be limited.")
        }
        
        // 4. Start monitoring for file changes
        await fileMonitor.startMonitoring()
        Logger.fileMonitor.info("🔍 File monitoring started.")
    }
    
    deinit {
        Logger.app.info("🛑 Deinitializing MenuBarManager")
        statusItem = nil
        Logger.app.info("✅ MenuBarManager deinitialized")
    }
    
    private func setupMenuBar() {
        Logger.menuBar.debug("🔧 Setting up menu bar")
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        guard let statusButton = statusItem?.button else {
            Logger.menuBar.error("❌ Failed to get status button from status item")
            return
        }
        
        setupRollingNumberView()
        statusButton.action = #selector(menuBarButtonClicked)
        statusButton.target = self
        
        setupMenu()
        Logger.menuBar.info("✅ Menu bar setup completed")
    }
    
    private func setupStateSubscriptions() {
        Logger.fileMonitor.debug("🔧 Setting up state subscriptions")
        
        // Subscribe to file changes from the monitor
        fileMonitor.fileChanges
            .receive(on: DispatchQueue.global(qos: .background))
            .sink { [weak self] changedFiles in
                guard let self = self else { return }
                Logger.fileMonitor.info("🔄 File changes detected for: \(changedFiles.map { $0.lastPathComponent })")
                Task {
                    await self.processChangedFiles(changedFiles)
                }
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
        
        // Add pricing data source information
        let dataSource = PricingManager.shared.getCurrentDataSource()
        let dataSourceItem = NSMenuItem(title: "Pricing: \(dataSource.description)", action: nil, keyEquivalent: "")
        dataSourceItem.isEnabled = false
        menu.addItem(dataSourceItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let refreshItem = NSMenuItem(title: "Refresh Data", action: #selector(refreshData), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)
        
        let reloadDatabaseItem = NSMenuItem(title: "Reload Database", action: #selector(reloadDatabase), keyEquivalent: "")
        reloadDatabaseItem.target = self
        menu.addItem(reloadDatabaseItem)
        
        let accessItemTitle = homeDirectoryAccessManager.hasValidAccess ? "Revoke Home Directory Access" : "Grant Home Directory Access"
        let accessAction = homeDirectoryAccessManager.hasValidAccess ? #selector(revokeAccess) : #selector(requestAccess)
        let accessItem = NSMenuItem(title: accessItemTitle, action: accessAction, keyEquivalent: "")
        accessItem.target = self
        menu.addItem(accessItem)
        
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
        Task {
            await processAllJsonlFiles()
        }
    }
    
    @objc private func reloadDatabase() {
        Logger.app.info("🗑️ Database reload requested")
        
        // Show confirmation dialog
        let alert = NSAlert()
        alert.messageText = "Reload Database"
        alert.informativeText = "The database will be cleaned and reloaded from scratch. Proceed?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Proceed")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            Logger.app.info("✅ User confirmed database reload")
            Task {
                await performDatabaseReload()
            }
        } else {
            Logger.app.info("❌ User cancelled database reload")
        }
    }
    
    @objc private func requestAccess() {
        Logger.security.info("🔒 User requested home directory access")
        Task {
            let granted = await homeDirectoryAccessManager.requestHomeDirectoryAccess()
            if granted {
                await processAllJsonlFiles()
            }
            Logger.security.info("🔒 Home directory access request result: \(granted)")
        }
    }
    
    @objc private func revokeAccess() {
        Logger.security.info("🚫 User requested to revoke home directory access")
        homeDirectoryAccessManager.revokeAccess()
    }
    
    @objc private func quitApp() {
        Logger.app.info("👋 User requested app termination")
        NSApplication.shared.terminate(nil)
    }
    
    // MARK: - Data Processing Methods
    
    private func performDatabaseReload() async {
        Logger.app.info("🗑️ Starting database reload process")
        
        // 1. Clear all entries from the database
        dataStore.clearAllEntries()
        
        // 2. Reset UI to show empty data immediately
        await MainActor.run {
            self.currentSummary = SpendSummary.empty
        }
        
        // 3. Reload all JSONL files from scratch
        await processAllJsonlFiles()
        
        Logger.app.info("✅ Database reload completed")
    }
    
    private func processAllJsonlFiles() async {
        guard let claudeDir = homeDirectoryAccessManager.claudeDirectoryURL else {
            Logger.app.error("❌ Cannot access Claude directory.")
            return
        }
        
        Logger.app.info("🔍 Starting full scan of .jsonl files in \(claudeDir.path)")
        
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(at: claudeDir, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else {
            Logger.app.error("❌ Failed to create directory enumerator.")
            return
        }
        
        let jsonlFiles = enumerator.allObjects.compactMap { $0 as? URL }.filter { $0.pathExtension == "jsonl" }
        
        await processChangedFiles(jsonlFiles)
    }
    
    private func processChangedFiles(_ urls: [URL]) async {
        guard !urls.isEmpty else { return }
        
        Logger.parser.info("Parsing \(urls.count) file(s)...")
        
        var allEntries: [UsageEntry] = []
        let parser = JSONLParser()
        
        for url in urls {
            do {
                let entries = try await parser.parse(fileURL: url)
                allEntries.append(contentsOf: entries)
            } catch {
                Logger.parser.error("❌ Failed to parse file \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        
        guard !allEntries.isEmpty else {
            Logger.parser.warning("⚠️ No new valid entries found in the provided files.")
            return
        }
        
        Logger.dataStore.info("Upserting \(allEntries.count) entries into the database.")
        await dataStore.upsertEntries(allEntries)
        
        // After upserting, refresh the summary from the database
        refreshSpendingSummary()
    }
    
    private func refreshSpendingSummary() {
        Logger.calculator.logTiming("Spending summary calculation") {
            let newSummary = dataStore.fetchSpendSummary()
            DispatchQueue.main.async { [weak self] in
                self?.currentSummary = newSummary
                Logger.calculator.info("💰 Updated spend summary - Today: $\(String(format: "%.2f", newSummary.todaySpend))")
            }
        }
    }
    
    // MARK: - Private Helper Methods
    
    private func setupRollingNumberView() {
        guard let statusButton = statusItem?.button else {
            Logger.menuBar.error("❌ Cannot setup rolling number view - no status button")
            return
        }
        
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "en_US")
        
        rollingNumberView = RollingNumberNSView(formatter: formatter)
        
        guard let rollingView = rollingNumberView else { return }
        
        statusButton.title = ""
        statusButton.addSubview(rollingView)
        
        rollingView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            rollingView.centerXAnchor.constraint(equalTo: statusButton.centerXAnchor),
            rollingView.centerYAnchor.constraint(equalTo: statusButton.centerYAnchor)
        ])
        
        rollingView.updateValue(currentSummary.todaySpend)
        Logger.menuBar.debug("🎬 Rolling number view setup completed")
    }
    
    private func updateStatusBarTitle() {
        guard let rollingView = rollingNumberView else {
            Logger.menuBar.error("❌ Cannot update status bar - no rolling number view")
            return
        }
        
        rollingView.updateValue(currentSummary.todaySpend)
        Logger.menuBar.debug("📱 Updated rolling number display: $\(String(format: "%.2f", self.currentSummary.todaySpend))")
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