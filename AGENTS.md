# iOSImageOptimizer Agent Instructions

- Keep responses concise and preserve unrelated work in the working tree.
- Read the relevant source and tests before changing behavior. `README.md` describes usage; `iOSImageOptimizer/implementation-plan.md` is an initial plan, not an authoritative description of the current implementation.

## Project layout and requirements

- This repository builds a macOS command-line analyzer for iOS projects. The Swift package root is `iOSImageOptimizer/`, not the repository root.
- `iOSImageOptimizer/Package.swift` declares Swift tools 5.9 and macOS 13 as the minimum platform. Source uses CoreGraphics and ImageIO; verify on macOS.
- The executable target is `iOSImageOptimizer`; its ArgumentParser command name is `ios-image-optimizer`.
- Sources live in `iOSImageOptimizer/Sources/iOSImageOptimizer/`; XCTest tests and fixtures live in `iOSImageOptimizer/Tests/iOSImageOptimizerTests/`.
- Dependencies are ArgumentParser, Files, and Rainbow. The manifest uses version ranges, not exact pins. Keep dependency or platform changes scoped to the request.

## Component responsibilities

- `main.swift`: positional project path, verbose/JSON flags, and command execution.
- `ProjectAnalyzer.swift`: analysis orchestration, unused-image cross-validation, report models, console output, and JSON encoding.
- `ImageScanner.swift`: standalone and asset-catalog image discovery, dimensions, scale, PNG interlacing, and color-profile metadata.
- `ProjectParser.swift`: project-file and asset-catalog parsing, plus references from property lists, strings files, and Settings bundles.
- `UsageDetector.swift`: source/interface references, constants, dynamic loading patterns, and interpolation detection.
- `SemanticAnalyzer.swift`: variable assignments and string-interpolation reference inference. It does not own scale-variant or asset-organization validation.
- `AppleComplianceValidator.swift`: image checks, issue classification, and compliance scoring.
- `FileIteratorHelper.swift`: filtered recursive traversal shared by analysis components.

## Behavior guardrails

- Preserve analysis-only behavior: scanning a user's project must not modify, recompress, move, or delete its files.
- Treat unused-image findings as heuristic candidates for review, not proof that deletion is safe. Preserve dynamic-reference handling, name/scale variants, cross-validation, and system-managed asset exemptions when changing detection.
- Preserve early pruning of build, dependency, and version-control directories. `ImageScanner` has its own traversal/exclusion logic in addition to `FileIteratorHelper`; check both when changing scan behavior. Avoid introducing unfiltered recursive walks that revisit huge excluded trees.
- Keep malformed files, missing metadata, and invalid paths in mind when changing parsing or scanning. Use fixtures and temporary directories for regression cases.
- Keep console output and encoded report changes deliberate. Check the complete CLI output when changing JSON mode: the current command prints an analysis banner before the JSON payload.
- Compliance scores and dimensional checks are implemented heuristics. Do not describe them as guarantees of App Store approval. Verify current official Apple documentation before adding or changing claims about Apple requirements.

## Build and verification

Run these commands from `iOSImageOptimizer/`:

```sh
swift build
swift test
```

Useful targeted checks and CLI commands:

```sh
swift test --filter UsageDetectorTests
swift test --enable-code-coverage
swift run iOSImageOptimizer /path/to/project
swift run iOSImageOptimizer /path/to/project --verbose
swift run iOSImageOptimizer /path/to/project --json
```

- For source, manifest, or resource changes, build and run relevant tests; run the full test suite before handing off a behavioral change. Add focused regression coverage for detection and parsing fixes.
- Fixtures are copied as test resources by `Package.swift`. Reuse existing test utilities and mock-image helpers; keep intentional corrupted fixtures intact.
- Documentation-only changes need a diff/whitespace check, not a build.
- Report actual verification results and any blockers. Do not repeat the historical test count or coverage percentage in README/CLAUDE guidance as a current measured result.
- CI is defined in `.github/workflows/ci.yml`. It builds and tests from the package directory and currently selects a hardcoded Xcode 15.0 path; inspect runner availability if CI setup fails.
- Do not commit build output, coverage output, `.DS_Store`, editor/user data, secrets, or machine-specific paths. `Package.resolved` is currently ignored by repository policy.
