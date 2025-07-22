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

## Development Practices
- Always handle errors gracefully
- Use background queues for file system operations
- Never block the main thread
- Implement proper memory management
- Use dependency injection for testability
- Write unit tests for core business logic
- **ALWAYS update PLAN.md to check off completed steps after implementing features**
- **ALWAYS build the project before completing any task to ensure no compilation errors**

## Architecture Patterns
- Use MVVM pattern with SwiftUI
- Implement observer pattern for real-time updates
- Use Swift's Combine framework for reactive programming
- Separate data models from UI models

## Performance Considerations
- Monitor file system efficiently with FSEvents
- Cache processed data appropriately
- Use lazy loading for large datasets
- Debounce rapid updates to prevent UI thrashing
- Optimize menu bar icon updates

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