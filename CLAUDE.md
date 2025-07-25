# Claude Development Rules

## Project Context
This is a macOS menu bar application that monitors Claude Code spending in real-time. The app displays current spending in the menu bar and provides detailed breakdowns via a dropdown menu.

## Tech Stack
- **Language**: Swift
- **Framework**: SwiftUI
- **Platform**: macOS (menu bar app)
- **Architecture**: Native macOS app with NSStatusItem

## Code Style Guidelines
- Use Swift naming conventions (camelCase for variables/functions, PascalCase for types)
- Prefer SwiftUI over UIKit where possible
- Use proper Swift error handling with Result types and do-catch blocks
- Follow Swift API design guidelines
- Use meaningful variable and function names
- Add documentation comments for public APIs
- **When removing problematic code, delete it completely - do NOT replace with comments**

## File Organization
- Group related functionality into separate Swift files
- Use MARK comments to organize code sections
- Keep view models separate from views
- Create dedicated managers for different concerns (FileMonitor, PricingManager, etc.)
- Follow the established project structure:
  - `ClaudeNeinApp.swift` - Main app entry point with integrated MenuBarManager
  - `Models.swift` - All data models and structures
  - `DataStore.swift` - Core Data persistence layer
  - `*Manager.swift` - Dedicated manager classes for specific functionality
  - `*View.swift` - SwiftUI view components

## Development Practices
- Always handle errors gracefully with proper Swift error handling
- Use background queues for file system operations and data processing
- Never block the main thread - use `@MainActor` and `DispatchQueue.main.async` appropriately
- Implement proper memory management with weak references where needed
- Use dependency injection for testability (see `FileMonitor` with `DirectoryAccessManager`)
- Write unit tests for core business logic
- Use the centralized `Logger` system for all logging needs
- Follow Core Data best practices with proper context management
- **ALWAYS update PLAN.md to check off completed steps after implementing features**
- **ALWAYS build the project using `xcodebuild` before completing any task to ensure no compilation errors**
- **ALWAYS run the tests before completing any task**: `xcodebuild test -scheme ClaudeNein -destination 'platform=macOS'`

## Architecture Patterns
- Use MVVM pattern with SwiftUI where applicable
- Implement observer pattern for real-time updates using Combine publishers
- Use Swift's Combine framework for reactive programming (see `FileMonitor.fileChanges`)
- Separate data models from UI models
- Use the single responsibility principle - each manager handles one concern
- Follow the centralized architecture with `MenuBarManager` as the main coordinator

## Performance Considerations
- Monitor file system efficiently with FSEvents (implemented in `FileMonitor`)
- Cache processed data appropriately using Core Data persistence
- Use lazy loading for large datasets and incremental parsing
- Debounce rapid updates to prevent UI thrashing (see file change debouncing)
- Optimize menu bar icon updates with smooth animations
- Process data on background queues to maintain UI responsiveness
- Use efficient database queries with proper indexing

## Testing Requirements
- Write unit tests for data processing logic
- Test file monitoring functionality
- Verify cost calculation accuracy
- Create mock data for testing edge cases

## Security & Privacy
- Request file system permissions appropriately
- Handle user data securely
- No network requests except for pricing updates
- Respect user privacy preferences

