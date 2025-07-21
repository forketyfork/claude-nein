# Claude Nein - Claude Code Spend Monitor

A native macOS menu bar application that displays real-time Claude Code spending with intuitive visual feedback and detailed breakdowns.

## Overview

Claude Nein monitors your Claude Code usage by parsing JSONL files and displays spending information directly in your menu bar. The app provides:

- **Real-time spend tracking** - Shows today's spend in the menu bar icon
- **Detailed breakdowns** - Dropdown menu with today/week/month summaries
- **Native macOS experience** - Built with Swift and SwiftUI
- **Minimal performance impact** - Efficient file monitoring and caching

## Features

### Menu Bar Display
- Current day's spending shown directly in the menu bar
- Updates automatically as you use Claude Code
- Clean, readable format that fits naturally in the menu bar

### Detailed Menu
- Today's spending (prominent display)
- This week's spending (last 7 days)
- This month's spending (current calendar month)
- Quick actions: Refresh, Open Claude Directory, Quit

### Smart Monitoring
- Monitors Claude Code configuration directories automatically
- Efficient file system monitoring with FSEvents
- Incremental parsing - only processes new/changed files
- Background processing to avoid blocking the UI

## Technical Details

### Architecture
- **Language**: Swift
- **Framework**: SwiftUI for UI, AppKit for menu bar integration
- **Platform**: macOS (menu bar application)
- **Minimum Version**: macOS 11.0+

### Data Sources
The app monitors Claude Code JSONL files located in:
- `~/.claude/projects/`
- `~/.config/claude/projects/`
- Custom directories via environment variables

### Cost Calculation
- Fetches up-to-date pricing from LiteLLM API
- Offline fallback with bundled pricing data
- Supports different token types (input, output, cache)
- Handles multiple Claude models and pricing tiers

## Development

### Requirements
- Xcode 13.0+
- macOS 11.0+ deployment target
- Swift 5.5+

### Building
1. Clone the repository
2. Open the project in Xcode
3. Build and run (⌘+R)

### Project Structure
```
Sources/
├── App/                 # App lifecycle and configuration
├── Models/              # Data models and business logic
├── Views/               # SwiftUI views and UI components
├── Managers/            # File monitoring, pricing, data processing
└── Extensions/          # Swift extensions and utilities
```

## Privacy & Security

Claude Nein operates entirely locally on your machine:
- No data is sent to external servers (except for pricing updates)
- Only reads Claude Code JSONL files for usage calculation
- Respects macOS file system permissions
- No user data collection or tracking

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Contributing

Contributions are welcome! Please read the development guidelines in [CLAUDE.md](CLAUDE.md) before submitting pull requests.