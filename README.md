# Claude Nein - Claude Code Spend Monitor

A native macOS menu bar application that monitors your Claude Code spending in real-time, providing intuitive visual feedback and detailed breakdowns.

![Claude Nein Screenshot](...)

## Overview

Claude Nein lives in your macOS menu bar, keeping you constantly updated on your Claude Code API usage costs. It automatically discovers your Claude project log files, parses them efficiently, and presents a clear summary of your spending.

## Features

- **Real-Time Menu Bar Display** – today's spend appears in the menu bar and animates smoothly when the value changes.
- **Detailed Spend Summaries** – the dropdown menu shows totals for today, this week and this month.
- **Model‑Specific Costs** – see which models account for the most spend.
- **Automatic & Efficient Monitoring** – uses FSEvents to watch Claude log files with minimal overhead.
- **Persistent Data Storage** – usage is cached locally in Core Data so data survives restarts.
- **Database Management** – built in "Reload Database" command clears and reloads cached usage.
- **Secure & Private** – all processing happens on your Mac; the only network request fetches pricing information.
- **Home Directory Access Control** – you explicitly grant and revoke access to the Claude data directory.
- **Up‑to‑Date Pricing** – pricing data is pulled from LiteLLM with cached and bundled fallbacks, and the current data source is displayed in the menu.

## How It Works

1.  **Permissions** – at first launch you grant read‑only access to your home directory via a security‑scoped bookmark.
2.  **File Monitoring** – the app searches `~/.claude/projects` and `~/.config/claude/projects` for `.jsonl` logs and monitors them with FSEvents.
3.  **Parsing** – changed files are parsed and deduplicated, extracting model names, timestamps and token counts including cache tokens.
4.  **Data Storage**: Parsed usage entries are stored in a local Core Data database with intelligent deduplication to prevent duplicate entries.
5.  **Cost Calculation**: Using the latest pricing data, it calculates the cost for each entry and aggregates spending data from the database.
6.  **UI Update**: It displays the aggregated costs in the menu bar and detailed dropdown menu, with real-time updates as new data arrives.

## Installation

1. Open `ClaudeNein.xcodeproj` in Xcode (15 or later).
2. Select the **ClaudeNein** scheme.
3. Build and run the project to launch the menu bar app.
4. To run the unit tests use `xcodebuild test -scheme ClaudeNein -destination 'platform=macOS'`.

## Technical Details

-   **Language**: Swift
-   **Framework**: SwiftUI for the core logic, AppKit for menu bar integration
-   **Platform**: macOS
-   **Architecture**: The app runs as a background agent (`NSStatusItem`) managed by a central `MenuBarManager`. It uses a `FileMonitor` for observing the file system and a `SpendCalculator` for business logic.

### Data Source

The app monitors Claude Code `.jsonl` files located in your Claude configuration directories, for example:

- `~/.claude/projects/`
- `~/.config/claude/projects/`

### Project Structure

The project is organized as follows:

```
ClaudeNein/
├── ClaudeNeinApp.swift         # Main app entry point
├── MenuBarManager.swift        # Core class managing the status item and menu
├── Models.swift                # Data models (UsageEntry, SpendSummary, etc.)
├── DataStore.swift             # Core Data persistence layer for usage entries
├── Model.xcdatamodeld/         # Core Data model definition
├── FileMonitor.swift           # Monitors the file system for log changes
├── HomeDirectoryAccessManager.swift # Handles permissions for home directory access
├── SpendCalculator.swift       # Calculates spend totals and breakdowns
├── PricingManager.swift        # Fetches and manages model pricing data
├── JSONLParser.swift           # Parses `.jsonl` log files
├── LiteLLMParser.swift         # Parses pricing data from LiteLLM source
└── ... (other supporting files)
```

## Privacy & Security

Claude Nein is designed with privacy as a priority:

-   **Local Processing**: All log file parsing and calculations happen on your Mac.
-   **Local Data Storage**: Usage data is stored locally in a Core Data database on your machine.
-   **No Data Transmission**: No usage data or personal information is ever sent to any external server.
-   **Limited Permissions**: The app only requests the read-only permissions necessary to access Claude's log files.
-   **Transparent Pricing Updates**: The only network request made is to the public LiteLLM GitHub repository to fetch `model_prices_and_context_window.json`.

## Contributing

Contributions are welcome! Please feel free to open an issue or submit a pull request.

## Disclaimer

This is an unofficial, third-party application and is not affiliated with, authorized, or endorsed by Anthropic. Use at your own risk.
