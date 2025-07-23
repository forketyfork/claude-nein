# Claude Nein - Claude Code Spend Monitor

A native macOS menu bar application that monitors your Claude Code spending in real-time, providing intuitive visual feedback and detailed breakdowns.

![Claude Nein Screenshot](...)

## Overview

Claude Nein lives in your macOS menu bar, keeping you constantly updated on your Claude Code API usage costs. It automatically discovers your Claude project log files, parses them efficiently, and presents a clear summary of your spending.

## Features

- **Real-Time Menu Bar Display**: See your total spend for the current day directly in the menu bar. The icon updates automatically.
- **Detailed Spend Summaries**: A dropdown menu provides breakdowns of your spending for today, the current week, and the current month.
- **Model-Specific Costs**: See a breakdown of costs per model, so you know which ones are contributing most to your bill.
- **Automatic & Efficient Monitoring**: The app uses modern file system watching APIs to detect changes in your Claude log files with minimal performance impact.
- **Secure & Private**: All processing happens locally on your machine. The app only reads log files and makes no other network requests, except to fetch updated pricing information.
- **Home Directory Access Control**: The app guides you to grant access to the home directory if needed and allows you to revoke it at any time.
- **Up-to-Date Pricing**: Automatically fetches the latest pricing data from the LiteLLM project, with bundled data as a reliable fallback.

## How It Works

1.  **Permissions**: The app first ensures it has the necessary read-only access to your home directory to find the Claude log files.
2.  **File Monitoring**: It identifies Claude project directories (e.g., `~/.claude/`) and starts monitoring the `.jsonl` log files within them for any changes.
3.  **Parsing**: When a file is changed (i.e., new API calls are logged), the app parses the new entries to extract usage data like model, token counts, and timestamps.
4.  **Cost Calculation**: Using the latest pricing data, it calculates the cost for each new entry.
5.  **UI Update**: It aggregates the costs and updates the menu bar display and the detailed dropdown menu.

## Installation

TBD

## Technical Details

-   **Language**: Swift
-   **Framework**: SwiftUI for the core logic, AppKit for menu bar integration
-   **Platform**: macOS
-   **Architecture**: The app runs as a background agent (`NSStatusItem`) managed by a central `MenuBarManager`. It uses a `FileMonitor` for observing the file system and a `SpendCalculator` for business logic.

### Data Source

The app monitors Claude Code `.jsonl` files located in standard Claude config directories, such as:

-   `~/.claude/`

### Project Structure

The project is organized as follows:

```
ClaudeNein/
├── ClaudeNeinApp.swift         # Main app entry point
├── MenuBarManager.swift        # Core class managing the status item and menu
├── Models.swift                # Data models (UsageEntry, SpendSummary, etc.)
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
-   **No Data Transmission**: No usage data or personal information is ever sent to any external server.
-   **Limited Permissions**: The app only requests the read-only permissions necessary to access Claude's log files.
-   **Transparent Pricing Updates**: The only network request made is to the public LiteLLM GitHub repository to fetch `model_prices_and_context_window.json`.

## Contributing

Contributions are welcome! Please feel free to open an issue or submit a pull request.

## Disclaimer

This is an unofficial, third-party application and is not affiliated with, authorized, or endorsed by Anthropic. Use at your own risk.
