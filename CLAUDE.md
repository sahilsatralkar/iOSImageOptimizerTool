# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

### Build
```bash
cd iOSImageOptimizer
swift build
```

### Run Tests
```bash
cd iOSImageOptimizer
swift test

# Run with code coverage
swift test --enable-code-coverage

# Run a specific test
swift test --filter TestClassName
```

### Run the Tool
```bash
cd iOSImageOptimizer
swift run iOSImageOptimizer /path/to/ios/project

# With verbose output
swift run iOSImageOptimizer /path/to/ios/project --verbose

# Export to JSON
swift run iOSImageOptimizer /path/to/ios/project --json
```

### Clean Build
```bash
cd iOSImageOptimizer
swift package clean
swift build
```

## Architecture

### Core Components
- **ProjectAnalyzer**: Main orchestrator that coordinates the analysis process
- **ImageScanner**: Finds and analyzes image files in the project directory
- **ProjectParser**: Parses Swift, Objective-C, and Storyboard files to find image references
- **UsageDetector**: Detects dynamic image loading patterns including string interpolation
- **AppleComplianceValidator**: Validates images against Apple's Human Interface Guidelines
- **SemanticAnalyzer**: Analyzes relationships between images (scale variants, asset organization)

### Key Features
- Detects unused images with enhanced pattern matching for dynamic loading
- Validates PNG interlacing, color profiles, and asset catalog organization
- Provides Apple compliance scoring (0-100)
- Supports both static and dynamic image reference detection
- Works with standard iOS project structures including .xcodeproj directories

### Testing
- 154 comprehensive unit tests covering all major components
- Test fixtures include mock projects, images, and JSON files
- CI/CD pipeline runs tests automatically on pull requests
- Code coverage reporting integrated with GitHub Actions