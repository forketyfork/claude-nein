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
- [ ] Create app icon and menu bar icon assets
- [ ] Set up project structure with organized folders

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

### Phase 3: Cost Calculation Engine
- [x] Create `PricingManager` class:
  - [x] Fetch LiteLLM pricing data from API
  - [x] Implement offline fallback with bundled pricing data
  - [x] Cache pricing data locally with expiration
- [x] Implement cost calculation logic:
  - [x] Calculate costs from token counts using model pricing
  - [x] Handle different token types (input, output, cache)
  - [x] Support pre-calculated costs from JSONL when available
- [x] Create spend aggregation functions:
  - [x] Daily spend calculation
  - [x] Weekly spend calculation (last 7 days)
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
  - [x] "Grant/Revoke Access" menu items for home directory permissions
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
- [ ] Add keyboard shortcuts:
  - [ ] Global hotkey to toggle menu (optional)
  - [ ] Standard menu shortcuts

### Phase 8: Error Handling & Edge Cases
- [ ] Implement comprehensive error handling:
  - [ ] Handle missing Claude config directories
  - [ ] Deal with corrupted JSONL files
  - [ ] Network errors when fetching pricing data
  - [ ] File permission issues
- [ ] Add user feedback mechanisms:
  - [ ] Show error states in menu bar icon
  - [ ] Display helpful error messages in dropdown
  - [ ] Log errors for debugging
- [ ] Handle edge cases:
  - [ ] No usage data available
  - [ ] Clock changes (daylight saving, etc.)
  - [ ] App launch during active Claude session

### Phase 9: Performance Optimization
- [ ] Profile and optimize data loading:
  - [ ] Lazy loading of historical data
  - [ ] Efficient memory usage for large datasets
  - [ ] Background processing for heavy operations
- [ ] Optimize UI updates:
  - [ ] Debounce rapid data changes
  - [ ] Smart UI refresh (only when data actually changes)
  - [ ] Minimize menu bar icon redraws
- [ ] Add data caching:
  - [ ] Cache processed usage data
  - [ ] Persist cache between app launches
  - [ ] Intelligent cache invalidation

### Phase 10: Testing & Polishing
- [ ] Write unit tests:
  - [ ] Test JSONL parsing logic
  - [ ] Test cost calculation accuracy
  - [ ] Test file monitoring functionality
- [ ] Create mock data for testing:
  - [ ] Sample JSONL files with various scenarios
  - [ ] Test data with different models and time periods
- [ ] Perform integration testing:
  - [ ] Test with real Claude Code usage data
  - [ ] Verify cost calculation accuracy
  - [ ] Test app behavior during active Claude sessions
- [ ] Polish user experience:
  - [ ] Smooth animations and transitions
  - [ ] Intuitive menu interactions
  - [ ] Proper accessibility support

### Phase 11: Build & Distribution
- [ ] Configure build settings:
  - [ ] Code signing and notarization
  - [ ] Minimum macOS version support
  - [ ] Universal binary (Intel + Apple Silicon)
- [ ] Create build scripts:
  - [ ] Archive and export workflow
  - [ ] Automated testing in CI
- [ ] Prepare for distribution:
  - [ ] App store preparation (if applicable)
  - [ ] Direct distribution DMG creation
  - [ ] Documentation and README

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
- [ ] App launches and appears in menu bar
- [ ] Displays accurate today's spend in menu bar icon
- [ ] Dropdown shows correct breakdowns for today/week/month
- [ ] Updates in real-time as Claude Code is used
- [ ] Handles edge cases gracefully without crashing
- [ ] Minimal performance impact on system
- [ ] Native macOS look and feel

## Optional Enhancements (Future)
- [ ] Notifications for spending thresholds
- [ ] Historical spending graphs and trends
- [ ] Export spending data to CSV/JSON
- [ ] Integration with expense tracking apps
- [ ] Customizable spending alerts and limits
- [ ] Support for multiple Claude Code profiles
