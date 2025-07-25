# Claude Code Spend Monitor - macOS Menu Bar App Implementation Plan

## Project Overview
Build a macOS menu bar application that displays real-time Claude Code spending with a simple menu bar icon showing today's spend and a dropdown with detailed breakdowns for today/week/month periods.

## Technical Architecture
- **Framework**: Swift + SwiftUI for native macOS experience
- **Menu Bar**: NSStatusItem with custom icon and menu
- **Data Source**: Monitor Claude Code JSONL files in config directories
- **Real-time Updates**: File system monitoring + periodic refresh
- **Cost Calculation**: Implement pricing logic with LiteLLM API integration

## Implementation Steps

### Phase 1: Project Setup & Foundation
- [x] Create new macOS app project in Xcode
- [x] Configure Info.plist for menu bar app (LSUIElement = true)
- [x] Set up basic SwiftUI app structure with MenuBarApp lifecycle
- [x] Create app icon and menu bar icon assets
- [x] Set up project structure with organized folders

### Phase 2: Data Models & Core Logic
- [x] Create Swift data models for Claude Code usage data:
  - [x] `UsageEntry` struct for individual JSONL entries
  - [x] `TokenCounts` struct for aggregated usage
  - [x] `SessionBlock` struct for 5-hour billing periods
  - [x] `SpendSummary` struct for UI display data
- [x] Implement JSONL file parsing:
  - [x] Create `JSONLParser` class to read and parse JSONL files
  - [x] Handle malformed JSON lines gracefully
  - [x] Implement timestamp parsing and validation
- [x] Implement Claude config file discovery:
  - [x] Find Claude config directories (`~/.claude/projects/`, `~/.config/claude/projects/`)
  - [x] Implement recursive JSONL file discovery
  - [x] Support custom config directory via environment variable
  - [x] Persist parsed usage entries to Core Data database
  - [x] Fix database schema and upsert logic for proper deduplication
  - [x] Add database reload functionality with confirmation dialog
  - [x] Implement database clearing using NSBatchDeleteRequest
  - [x] Fix async timing issues in database operations

### Phase 3: Cost Calculation Engine
- [x] Create `PricingManager` class:
  - [x] Fetch LiteLLM pricing data from API
  - [x] Implement offline fallback with bundled pricing data
- [x] Cache pricing data locally with expiration
- [x] Persist pricing data to Core Data with 4h refresh schedule
- [x] Implement cost calculation logic:
  - [x] Calculate costs from token counts using model pricing
  - [x] Handle different token types (input, output, cache)
  - [x] Support pre-calculated costs from JSONL when available
- [x] Create spend aggregation functions:
  - [x] Daily spend calculation
  - [x] Weekly spend calculation (current calendar week)
  - [x] Monthly spend calculation (current calendar month)

### Phase 4: File Monitoring System
- [x] Implement `FileMonitor` class using DispatchSource:
  - [x] Monitor Claude config directories for file changes
  - [x] Track file modification timestamps
  - [x] Debounce rapid file changes
- [x] Create incremental data loading:
  - [x] Only parse new/modified files since last check
  - [x] Maintain cache of processed entries
  - [x] Implement duplicate entry detection and filtering
- [x] Add periodic refresh mechanism:
  - [x] Timer-based refresh every 10-30 seconds
  - [x] Immediate refresh on file system events
  - [x] Background processing to avoid UI blocking

### Phase 5: Menu Bar Interface
- [x] Create `MenuBarManager` class:
  - [x] Initialize NSStatusItem with custom icon
  - [x] Handle menu bar icon clicks
  - [x] Manage menu show/hide behavior
- [x] Design menu bar icon:
  - [x] Create icon showing today's spend amount
  - [x] Use appropriate font size and styling
  - [x] Handle long spend amounts gracefully
  - [x] Support dark/light mode theming
- [x] Implement icon update logic:
  - [x] Update icon text when spend changes
  - [x] Animate icon changes smoothly
  - [x] Handle edge cases (no data, errors)

### Phase 6: Dropdown Menu UI
- [x] Create SwiftUI views for menu content:
  - [x] `SpendSummaryView` - main menu content (implemented in NSMenu)
  - [x] `PeriodSpendRow` - individual period display (implemented in NSMenu)
  - [x] `ModelBreakdownView` - spending by model (implemented in NSMenu)
- [x] Implement menu layout:
  - [x] Today's spend (prominent display)
  - [x] This week's spend
  - [x] This month's spend
  - [x] Separator and additional options
- [x] Add interactive elements:
- [x] "Refresh" menu item for manual updates
  - [x] "Refresh Pricing" menu item
  - [x] Display pricing last fetched time in menu
  - [x] "Grant/Revoke Access" menu items for home directory permissions
  - [x] Permission status icon in menu (improved UX with per-directory bookmarks)
  - [x] "Reload Database" menu item with confirmation dialog for clearing all cached data
  - [x] "Quit" menu item
- [x] Style menu for native macOS look:
  - [x] Use system fonts and colors
  - [x] Proper spacing and alignment
  - [x] Support dark/light mode

### Phase 7: Settings & Preferences
- [ ] Create preferences window (optional):
  - [ ] Custom Claude config directory path
  - [ ] Refresh interval settings
  - [ ] Cost display format preferences
- [ ] Implement UserDefaults storage:
  - [ ] Save user preferences
  - [ ] Handle preference changes
  - [ ] Provide sensible defaults
- [x] Add launch at login functionality:
  - [x] "Run at Startup" menu item with persistent toggle
  - [x] LaunchAtLoginManager implementation
  - [ ] Global hotkey to toggle menu (optional)
  - [ ] Standard menu shortcuts

### Phase 8: Error Handling & Edge Cases
- [x] Implement comprehensive error handling:
  - [x] Handle missing Claude config directories
  - [x] Deal with corrupted JSONL files (graceful parsing errors)
  - [x] Network errors when fetching pricing data (fallback to bundled data)
  - [x] File permission issues (access request dialogs)
- [x] Add user feedback mechanisms:
  - [x] Show access status in menu (granted/needed indicators)
  - [x] Display helpful status messages in dropdown menu
  - [x] Centralized logging system for debugging (Logger.swift)
- [x] Handle edge cases:
  - [x] No usage data available (empty state handling)
  - [x] Clock changes and date calculations
  - [x] App launch during active Claude session (incremental processing)

### Phase 9: Performance Optimization
- [x] Profile and optimize data loading:
  - [x] Lazy loading of historical data (incremental JSONL parsing)
  - [x] Efficient memory usage for large datasets
  - [x] Background processing for heavy operations (background queues)
- [x] Optimize UI updates:
  - [x] Debounce rapid data changes (file monitoring debouncing)
  - [x] Smart UI refresh (only when data actually changes)
  - [x] Smooth menu bar icon animations and minimal redraws
- [x] Add data caching:
  - [x] Cache processed usage data (Core Data persistence)
  - [x] Persist cache between app launches
  - [x] Intelligent cache invalidation and database reload functionality

### Phase 10: Testing & Polishing
- [x] Write unit tests:
  - [x] Test JSONL parsing logic (JSONLParserIntegrationTests)
  - [x] Test cost calculation accuracy (CostCalculationAccuracyTests)
  - [x] Test file monitoring functionality (FileMonitorTests)
  - [x] Test spend aggregation (SpendAggregationTests)
- [x] Create mock data for testing:
  - [x] Sample JSONL files with various scenarios (TestData directory)
  - [x] Test data with different models and time periods
  - [x] Mock directory access manager for testing
- [x] Perform integration testing:
  - [x] Test with real Claude Code usage data
  - [x] Verify cost calculation accuracy
  - [x] Test app behavior during active Claude sessions
- [x] Polish user experience:
  - [x] Smooth animations and transitions (menu bar icon animations)
  - [x] Intuitive menu interactions
  - [x] Native macOS look and feel

### Phase 11: Build & Distribution
- [ ] Configure build settings:
  - [ ] Code signing and notarization
  - [ ] Minimum macOS version support
  - [ ] Universal binary (Intel + Apple Silicon)
- [x] Create build scripts:
  - [x] Archive and export workflow
  - [x] Automated testing workflow (xcodebuild commands documented)
- [x] Prepare for distribution:
  - [x] GitHub releases with unsigned builds
  - [x] Direct distribution via GitHub releases
  - [x] Comprehensive documentation and README

## Technical Considerations

### File Monitoring Strategy
- Use FSEvents API for efficient file system monitoring
- Implement smart debouncing to handle rapid file changes
- Consider battery impact and optimize monitoring frequency

### Data Processing Efficiency
- Process only changed files to minimize CPU usage
- Implement smart caching with proper invalidation
- Use background queues for heavy data processing

### UI Responsiveness
- Never block the main thread with data processing
- Use SwiftUI's reactive updates for smooth UI changes
- Implement proper loading states and error messaging

### Memory Management
- Avoid keeping all historical data in memory
- Implement sliding window for recent usage data
- Proper cleanup of file monitors and timers

## Success Criteria
- [x] App launches and appears in menu bar
- [x] Displays accurate today's spend in menu bar icon
- [x] Dropdown shows correct breakdowns for today/week/month
- [x] Updates in real-time as Claude Code is used
- [ ] Handles edge cases gracefully without crashing
- [ ] Minimal performance impact on system
- [x] Native macOS look and feel

## Optional Enhancements (Future)
- [ ] Notifications for spending thresholds
- [x] Historical spending graphs and trends (SpendGraphView implemented)
- [ ] Export spending data to CSV/JSON
- [ ] Integration with expense tracking apps
- [ ] Customizable spending alerts and limits
- [ ] Support for multiple Claude Code profiles
- [ ] Preferences window for advanced settings
