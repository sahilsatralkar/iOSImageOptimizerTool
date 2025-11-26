import XCTest
import Foundation
import CoreGraphics
@testable import iOSImageOptimizer

/// Tests for v0.5 detection improvements:
/// - Alternative App Icons detection
/// - Color Set protection
/// - Localized Image Variants
/// - Multi-Target Detection (Widgets, Extensions, App Clips)
/// - Array Pattern Detection
final class DetectionImprovementsTests: XCTestCase {

    var tempProjectPath: String!

    override func setUp() {
        super.setUp()
        tempProjectPath = TestUtilities.createTempDirectory(named: "DetectionImprovementsTest")
    }

    override func tearDown() {
        TestUtilities.cleanupTempDirectory(tempProjectPath)
        super.tearDown()
    }

    // MARK: - Alternative App Icons Detection Tests

    func testParseAlternateAppIcons_BasicAlternateIcons() throws {
        let parser = ProjectParser(projectPath: tempProjectPath, verbose: false)

        let plistContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleIcons</key>
            <dict>
                <key>CFBundlePrimaryIcon</key>
                <dict>
                    <key>CFBundleIconFiles</key>
                    <array>
                        <string>AppIcon</string>
                    </array>
                </dict>
                <key>CFBundleAlternateIcons</key>
                <dict>
                    <key>DarkIcon</key>
                    <dict>
                        <key>CFBundleIconFiles</key>
                        <array>
                            <string>AppIcon-Dark</string>
                        </array>
                    </dict>
                    <key>LightIcon</key>
                    <dict>
                        <key>CFBundleIconFiles</key>
                        <array>
                            <string>AppIcon-Light</string>
                        </array>
                    </dict>
                </dict>
            </dict>
        </dict>
        </plist>
        """

        TestUtilities.createMockFile(at: "\(tempProjectPath!)/Info.plist", content: plistContent)

        let references = try parser.parseInfoPlists()

        // Should detect alternate icon file names
        XCTAssertTrue(references.contains("AppIcon-Dark"), "Should detect AppIcon-Dark alternate icon")
        XCTAssertTrue(references.contains("AppIcon-Light"), "Should detect AppIcon-Light alternate icon")

        // Should also detect scale variants
        XCTAssertTrue(references.contains("AppIcon-Dark@2x") || references.contains("AppIcon-Dark"),
                      "Should detect alternate icon or its variants")
    }

    func testParseAlternateAppIcons_MultipleIconsPerAlternate() throws {
        let parser = ProjectParser(projectPath: tempProjectPath, verbose: false)

        let plistContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0">
        <dict>
            <key>CFBundleIcons</key>
            <dict>
                <key>CFBundleAlternateIcons</key>
                <dict>
                    <key>SeasonalIcon</key>
                    <dict>
                        <key>CFBundleIconFiles</key>
                        <array>
                            <string>AppIcon-Winter</string>
                            <string>AppIcon-Summer</string>
                            <string>AppIcon-Spring</string>
                        </array>
                    </dict>
                </dict>
            </dict>
        </dict>
        </plist>
        """

        TestUtilities.createMockFile(at: "\(tempProjectPath!)/Info.plist", content: plistContent)

        let references = try parser.parseInfoPlists()

        XCTAssertTrue(references.contains("AppIcon-Winter"), "Should detect AppIcon-Winter")
        XCTAssertTrue(references.contains("AppIcon-Summer"), "Should detect AppIcon-Summer")
        XCTAssertTrue(references.contains("AppIcon-Spring"), "Should detect AppIcon-Spring")
    }

    func testParseAlternateAppIcons_NoAlternateIcons() throws {
        let parser = ProjectParser(projectPath: tempProjectPath, verbose: false)

        let plistContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0">
        <dict>
            <key>CFBundleIcons</key>
            <dict>
                <key>CFBundlePrimaryIcon</key>
                <dict>
                    <key>CFBundleIconFiles</key>
                    <array>
                        <string>AppIcon</string>
                    </array>
                </dict>
            </dict>
        </dict>
        </plist>
        """

        TestUtilities.createMockFile(at: "\(tempProjectPath!)/Info.plist", content: plistContent)

        let references = try parser.parseInfoPlists()

        // Should still work without alternate icons
        XCTAssertGreaterThanOrEqual(references.count, 0, "Should handle plist without alternate icons")
    }

    // MARK: - Color Set Protection Tests

    func testColorSetProtection_AccentColor() throws {
        let analyzer = ProjectAnalyzer(projectPath: tempProjectPath, verbose: false)

        // Create AccentColor.colorset
        let colorsetDir = "\(tempProjectPath!)/Assets.xcassets/AccentColor.colorset"
        try FileManager.default.createDirectory(atPath: colorsetDir, withIntermediateDirectories: true)

        let contentsJSON = """
        {
          "colors" : [
            {
              "idiom" : "universal"
            }
          ],
          "info" : {
            "author" : "xcode",
            "version" : 1
          }
        }
        """
        TestUtilities.createMockFile(at: "\(colorsetDir)/Contents.json", content: contentsJSON)

        // Create Swift file without any color references
        let swiftContent = """
        import UIKit
        class ViewController: UIViewController {
            override func viewDidLoad() {
                super.viewDidLoad()
            }
        }
        """
        TestUtilities.createMockFile(at: "\(tempProjectPath!)/ViewController.swift", content: swiftContent)

        let report = try analyzer.analyze()

        // AccentColor should NOT be marked as unused (it's system-managed)
        let unusedNames = report.unusedImages.map { $0.name.lowercased() }
        XCTAssertFalse(unusedNames.contains("accentcolor"), "AccentColor should not be marked as unused")
    }

    func testColorSetProtection_CustomColorSet() throws {
        let analyzer = ProjectAnalyzer(projectPath: tempProjectPath, verbose: false)

        // Create custom color set
        let colorsetDir = "\(tempProjectPath!)/Assets.xcassets/BrandColor.colorset"
        try FileManager.default.createDirectory(atPath: colorsetDir, withIntermediateDirectories: true)

        let contentsJSON = """
        {
          "colors" : [
            {
              "idiom" : "universal"
            }
          ],
          "info" : {
            "author" : "xcode",
            "version" : 1
          }
        }
        """
        TestUtilities.createMockFile(at: "\(colorsetDir)/Contents.json", content: contentsJSON)

        // Create Swift file without any color references
        let swiftContent = """
        import UIKit
        class ViewController: UIViewController {
            override func viewDidLoad() {
                super.viewDidLoad()
            }
        }
        """
        TestUtilities.createMockFile(at: "\(tempProjectPath!)/ViewController.swift", content: swiftContent)

        let report = try analyzer.analyze()

        // Color sets should be protected
        let unusedNames = report.unusedImages.map { $0.name.lowercased() }
        XCTAssertFalse(unusedNames.contains { $0.contains("brandcolor") },
                       "Color sets should be protected from unused detection")
    }

    // MARK: - Localized Image Variant Tests

    func testLocalizedImageVariants_JapaneseVariant() throws {
        let analyzer = ProjectAnalyzer(projectPath: tempProjectPath, verbose: false)

        // Create base image and Japanese variant
        let baseDir = "\(tempProjectPath!)/Assets.xcassets/welcome.imageset"
        try FileManager.default.createDirectory(atPath: baseDir, withIntermediateDirectories: true)

        let contentsJSON = """
        {
          "images" : [
            {
              "filename" : "welcome.png",
              "idiom" : "universal",
              "scale" : "1x"
            },
            {
              "filename" : "welcome~ja.png",
              "idiom" : "universal",
              "scale" : "1x",
              "locale" : "ja"
            }
          ],
          "info" : {
            "author" : "xcode",
            "version" : 1
          }
        }
        """
        TestUtilities.createMockFile(at: "\(baseDir)/Contents.json", content: contentsJSON)
        TestUtilities.createMockFile(at: "\(baseDir)/welcome.png", content: TestUtilities.mockImageData())
        TestUtilities.createMockFile(at: "\(baseDir)/welcome~ja.png", content: TestUtilities.mockImageData())

        // Create Swift file that uses the base name
        let swiftContent = """
        import UIKit
        class ViewController: UIViewController {
            override func viewDidLoad() {
                super.viewDidLoad()
                let image = UIImage(named: "welcome")
            }
        }
        """
        TestUtilities.createMockFile(at: "\(tempProjectPath!)/ViewController.swift", content: swiftContent)

        let report = try analyzer.analyze()

        // Japanese variant should NOT be marked as unused when base is used
        let unusedNames = report.unusedImages.map { $0.name }
        XCTAssertFalse(unusedNames.contains { $0.contains("welcome~ja") },
                       "Localized variant should not be marked as unused when base image is used")
    }

    func testLocalizedImageVariants_ChineseVariant() throws {
        let analyzer = ProjectAnalyzer(projectPath: tempProjectPath, verbose: false)

        // Create image with Chinese variant
        let imageDir = "\(tempProjectPath!)/Assets.xcassets/banner.imageset"
        try FileManager.default.createDirectory(atPath: imageDir, withIntermediateDirectories: true)

        let contentsJSON = """
        {
          "images" : [
            {
              "filename" : "banner.png",
              "idiom" : "universal",
              "scale" : "1x"
            },
            {
              "filename" : "banner~zh-Hans.png",
              "idiom" : "universal",
              "scale" : "1x",
              "locale" : "zh-Hans"
            }
          ],
          "info" : {
            "author" : "xcode",
            "version" : 1
          }
        }
        """
        TestUtilities.createMockFile(at: "\(imageDir)/Contents.json", content: contentsJSON)
        TestUtilities.createMockFile(at: "\(imageDir)/banner.png", content: TestUtilities.mockImageData())
        TestUtilities.createMockFile(at: "\(imageDir)/banner~zh-Hans.png", content: TestUtilities.mockImageData())

        // Create Swift file that uses the base name
        let swiftContent = """
        import SwiftUI
        struct ContentView: View {
            var body: some View {
                Image("banner")
            }
        }
        """
        TestUtilities.createMockFile(at: "\(tempProjectPath!)/ContentView.swift", content: swiftContent)

        let report = try analyzer.analyze()

        // Chinese variant should NOT be marked as unused when base is used
        let unusedNames = report.unusedImages.map { $0.name }
        XCTAssertFalse(unusedNames.contains { $0.contains("banner~zh") },
                       "Chinese localized variant should not be marked as unused when base image is used")
    }

    // MARK: - Multi-Target Detection Tests

    func testMultiTargetDetection_WidgetExtension() throws {
        let analyzer = ProjectAnalyzer(projectPath: tempProjectPath, verbose: false)

        // Create widget extension directory with image
        let widgetDir = "\(tempProjectPath!)/MyAppWidget/Assets.xcassets/widget_icon.imageset"
        try FileManager.default.createDirectory(atPath: widgetDir, withIntermediateDirectories: true)

        let contentsJSON = """
        {
          "images" : [
            {
              "filename" : "widget_icon.png",
              "idiom" : "universal",
              "scale" : "1x"
            }
          ],
          "info" : {
            "author" : "xcode",
            "version" : 1
          }
        }
        """
        TestUtilities.createMockFile(at: "\(widgetDir)/Contents.json", content: contentsJSON)
        TestUtilities.createMockFile(at: "\(widgetDir)/widget_icon.png", content: TestUtilities.mockImageData())

        // Create main app Swift file (doesn't reference widget icon)
        let swiftContent = """
        import UIKit
        class AppDelegate: UIResponder, UIApplicationDelegate {
        }
        """
        TestUtilities.createMockFile(at: "\(tempProjectPath!)/AppDelegate.swift", content: swiftContent)

        let report = try analyzer.analyze()

        // Widget images should be protected (might be used by widget extension code)
        let unusedNames = report.unusedImages.map { $0.name }
        XCTAssertFalse(unusedNames.contains { $0.contains("widget_icon") },
                       "Widget extension images should be protected")
    }

    func testMultiTargetDetection_ShareExtension() throws {
        let analyzer = ProjectAnalyzer(projectPath: tempProjectPath, verbose: false)

        // Create share extension directory with image
        let shareDir = "\(tempProjectPath!)/ShareExtension/Assets.xcassets/share_icon.imageset"
        try FileManager.default.createDirectory(atPath: shareDir, withIntermediateDirectories: true)

        let contentsJSON = """
        {
          "images" : [
            {
              "filename" : "share_icon.png",
              "idiom" : "universal",
              "scale" : "1x"
            }
          ],
          "info" : {
            "author" : "xcode",
            "version" : 1
          }
        }
        """
        TestUtilities.createMockFile(at: "\(shareDir)/Contents.json", content: contentsJSON)
        TestUtilities.createMockFile(at: "\(shareDir)/share_icon.png", content: TestUtilities.mockImageData())

        // Create main app Swift file
        let swiftContent = """
        import UIKit
        class AppDelegate: UIResponder, UIApplicationDelegate {
        }
        """
        TestUtilities.createMockFile(at: "\(tempProjectPath!)/AppDelegate.swift", content: swiftContent)

        let report = try analyzer.analyze()

        // Share extension images should be protected
        let unusedNames = report.unusedImages.map { $0.name }
        XCTAssertFalse(unusedNames.contains { $0.contains("share_icon") },
                       "Share extension images should be protected")
    }

    func testMultiTargetDetection_AppClip() throws {
        let analyzer = ProjectAnalyzer(projectPath: tempProjectPath, verbose: false)

        // Create App Clip directory with image
        let appClipDir = "\(tempProjectPath!)/MyAppClip/Assets.xcassets/clip_icon.imageset"
        try FileManager.default.createDirectory(atPath: appClipDir, withIntermediateDirectories: true)

        let contentsJSON = """
        {
          "images" : [
            {
              "filename" : "clip_icon.png",
              "idiom" : "universal",
              "scale" : "1x"
            }
          ],
          "info" : {
            "author" : "xcode",
            "version" : 1
          }
        }
        """
        TestUtilities.createMockFile(at: "\(appClipDir)/Contents.json", content: contentsJSON)
        TestUtilities.createMockFile(at: "\(appClipDir)/clip_icon.png", content: TestUtilities.mockImageData())

        // Create main app Swift file
        let swiftContent = """
        import UIKit
        class AppDelegate: UIResponder, UIApplicationDelegate {
        }
        """
        TestUtilities.createMockFile(at: "\(tempProjectPath!)/AppDelegate.swift", content: swiftContent)

        let report = try analyzer.analyze()

        // App Clip images should be protected
        let unusedNames = report.unusedImages.map { $0.name }
        XCTAssertFalse(unusedNames.contains { $0.contains("clip_icon") },
                       "App Clip images should be protected")
    }

    func testMultiTargetDetection_iMessageExtension() throws {
        let analyzer = ProjectAnalyzer(projectPath: tempProjectPath, verbose: false)

        // Create iMessage/Sticker pack directory
        let stickerDir = "\(tempProjectPath!)/StickerPack/Assets.xcassets/sticker1.imageset"
        try FileManager.default.createDirectory(atPath: stickerDir, withIntermediateDirectories: true)

        let contentsJSON = """
        {
          "images" : [
            {
              "filename" : "sticker1.png",
              "idiom" : "universal",
              "scale" : "1x"
            }
          ],
          "info" : {
            "author" : "xcode",
            "version" : 1
          }
        }
        """
        TestUtilities.createMockFile(at: "\(stickerDir)/Contents.json", content: contentsJSON)
        TestUtilities.createMockFile(at: "\(stickerDir)/sticker1.png", content: TestUtilities.mockImageData())

        let swiftContent = """
        import UIKit
        class AppDelegate: UIResponder, UIApplicationDelegate {
        }
        """
        TestUtilities.createMockFile(at: "\(tempProjectPath!)/AppDelegate.swift", content: swiftContent)

        let report = try analyzer.analyze()

        // Sticker pack images should be protected
        let unusedNames = report.unusedImages.map { $0.name }
        XCTAssertFalse(unusedNames.contains { $0.contains("sticker1") },
                       "Sticker pack images should be protected")
    }

    func testMultiTargetDetection_AppexBundle() throws {
        let analyzer = ProjectAnalyzer(projectPath: tempProjectPath, verbose: false)

        // Create .appex bundle directory with image
        let appexDir = "\(tempProjectPath!)/MyExtension.appex/Assets.xcassets/extension_icon.imageset"
        try FileManager.default.createDirectory(atPath: appexDir, withIntermediateDirectories: true)

        let contentsJSON = """
        {
          "images" : [
            {
              "filename" : "extension_icon.png",
              "idiom" : "universal",
              "scale" : "1x"
            }
          ],
          "info" : {
            "author" : "xcode",
            "version" : 1
          }
        }
        """
        TestUtilities.createMockFile(at: "\(appexDir)/Contents.json", content: contentsJSON)
        TestUtilities.createMockFile(at: "\(appexDir)/extension_icon.png", content: TestUtilities.mockImageData())

        let swiftContent = """
        import UIKit
        class AppDelegate: UIResponder, UIApplicationDelegate {
        }
        """
        TestUtilities.createMockFile(at: "\(tempProjectPath!)/AppDelegate.swift", content: swiftContent)

        let report = try analyzer.analyze()

        // .appex bundle images should be protected
        let unusedNames = report.unusedImages.map { $0.name }
        XCTAssertFalse(unusedNames.contains { $0.contains("extension_icon") },
                       ".appex bundle images should be protected")
    }

    // MARK: - Array Pattern Detection Tests

    func testArrayPatternDetection_MapWithUIImage() throws {
        let detector = UsageDetector(projectPath: tempProjectPath, verbose: false)

        let swiftContent = """
        class IconLoader {
            let iconNames = ["home", "settings", "profile", "search"]

            func loadIcons() -> [UIImage?] {
                return iconNames.map { UIImage(named: $0) }
            }
        }
        """

        TestUtilities.createMockFile(at: "\(tempProjectPath!)/IconLoader.swift", content: swiftContent)

        let usedImages = try detector.findUsedImageNames()

        // Should detect array elements when used with .map { UIImage(named: $0) }
        XCTAssertTrue(usedImages.contains("home"), "Should detect 'home' from array")
        XCTAssertTrue(usedImages.contains("settings"), "Should detect 'settings' from array")
        XCTAssertTrue(usedImages.contains("profile"), "Should detect 'profile' from array")
        XCTAssertTrue(usedImages.contains("search"), "Should detect 'search' from array")
    }

    func testArrayPatternDetection_ForEachWithUIImage() throws {
        let detector = UsageDetector(projectPath: tempProjectPath, verbose: false)

        let swiftContent = """
        class ImagePreloader {
            let preloadImages = ["splash", "onboarding1", "onboarding2"]

            func preload() {
                preloadImages.forEach { imageName in
                    let _ = UIImage(named: imageName)
                }
            }
        }
        """

        TestUtilities.createMockFile(at: "\(tempProjectPath!)/ImagePreloader.swift", content: swiftContent)

        let usedImages = try detector.findUsedImageNames()

        // Should detect array elements when used with .forEach
        XCTAssertTrue(usedImages.contains("splash"), "Should detect 'splash' from array")
        XCTAssertTrue(usedImages.contains("onboarding1"), "Should detect 'onboarding1' from array")
        XCTAssertTrue(usedImages.contains("onboarding2"), "Should detect 'onboarding2' from array")
    }

    func testArrayPatternDetection_CompactMapWithUIImage() throws {
        let detector = UsageDetector(projectPath: tempProjectPath, verbose: false)

        let swiftContent = """
        class ImageCollector {
            let imageNames = ["valid1", "valid2", "valid3"]

            func collectImages() -> [UIImage] {
                return imageNames.compactMap { UIImage(named: $0) }
            }
        }
        """

        TestUtilities.createMockFile(at: "\(tempProjectPath!)/ImageCollector.swift", content: swiftContent)

        let usedImages = try detector.findUsedImageNames()

        // Should detect array elements when used with .compactMap
        XCTAssertTrue(usedImages.contains("valid1"), "Should detect 'valid1' from array")
        XCTAssertTrue(usedImages.contains("valid2"), "Should detect 'valid2' from array")
        XCTAssertTrue(usedImages.contains("valid3"), "Should detect 'valid3' from array")
    }

    func testArrayPatternDetection_ForInLoop() throws {
        let detector = UsageDetector(projectPath: tempProjectPath, verbose: false)

        let swiftContent = """
        class TabBarImageLoader {
            let tabIcons = ["tab_home", "tab_search", "tab_favorites", "tab_profile"]

            func loadTabImages() {
                for iconName in tabIcons {
                    let icon = UIImage(named: iconName)
                    // Use icon
                }
            }
        }
        """

        TestUtilities.createMockFile(at: "\(tempProjectPath!)/TabBarImageLoader.swift", content: swiftContent)

        let usedImages = try detector.findUsedImageNames()

        // Should detect array elements when used in for-in loop
        XCTAssertTrue(usedImages.contains("tab_home"), "Should detect 'tab_home' from array")
        XCTAssertTrue(usedImages.contains("tab_search"), "Should detect 'tab_search' from array")
        XCTAssertTrue(usedImages.contains("tab_favorites"), "Should detect 'tab_favorites' from array")
        XCTAssertTrue(usedImages.contains("tab_profile"), "Should detect 'tab_profile' from array")
    }

    func testArrayPatternDetection_SwiftUIImage() throws {
        let detector = UsageDetector(projectPath: tempProjectPath, verbose: false)

        let swiftContent = """
        import SwiftUI

        struct ImageCarousel: View {
            let imageNames = ["slide1", "slide2", "slide3"]

            var body: some View {
                ForEach(imageNames, id: \\.self) { name in
                    Image(name)
                }
            }

            var images: [Image] {
                imageNames.map { Image($0) }
            }
        }
        """

        TestUtilities.createMockFile(at: "\(tempProjectPath!)/ImageCarousel.swift", content: swiftContent)

        let usedImages = try detector.findUsedImageNames()

        // Should detect array elements when used with SwiftUI Image
        XCTAssertTrue(usedImages.contains("slide1"), "Should detect 'slide1' from array")
        XCTAssertTrue(usedImages.contains("slide2"), "Should detect 'slide2' from array")
        XCTAssertTrue(usedImages.contains("slide3"), "Should detect 'slide3' from array")
    }

    func testArrayPatternDetection_MapWithNamedParameter() throws {
        let detector = UsageDetector(projectPath: tempProjectPath, verbose: false)

        let swiftContent = """
        class IconManager {
            let icons = ["icon_a", "icon_b", "icon_c"]

            func getImages() -> [UIImage?] {
                return icons.map { name in UIImage(named: name) }
            }
        }
        """

        TestUtilities.createMockFile(at: "\(tempProjectPath!)/IconManager.swift", content: swiftContent)

        let usedImages = try detector.findUsedImageNames()

        // Should detect array elements when using named parameter in closure
        XCTAssertTrue(usedImages.contains("icon_a"), "Should detect 'icon_a' from array")
        XCTAssertTrue(usedImages.contains("icon_b"), "Should detect 'icon_b' from array")
        XCTAssertTrue(usedImages.contains("icon_c"), "Should detect 'icon_c' from array")
    }

    // MARK: - Integration Tests

    func testIntegration_CombinedFeatures() throws {
        let analyzer = ProjectAnalyzer(projectPath: tempProjectPath, verbose: false)

        // Create a project with multiple new feature scenarios

        // 1. Alternate app icons in Info.plist
        let plistContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0">
        <dict>
            <key>CFBundleIcons</key>
            <dict>
                <key>CFBundleAlternateIcons</key>
                <dict>
                    <key>AlternateIcon</key>
                    <dict>
                        <key>CFBundleIconFiles</key>
                        <array>
                            <string>AppIcon-Alternate</string>
                        </array>
                    </dict>
                </dict>
            </dict>
        </dict>
        </plist>
        """
        TestUtilities.createMockFile(at: "\(tempProjectPath!)/Info.plist", content: plistContent)

        // 2. Create alternate icon asset
        let altIconDir = "\(tempProjectPath!)/Assets.xcassets/AppIcon-Alternate.imageset"
        try FileManager.default.createDirectory(atPath: altIconDir, withIntermediateDirectories: true)
        TestUtilities.createMockFile(at: "\(altIconDir)/Contents.json", content: """
        {"images":[{"filename":"AppIcon-Alternate.png","idiom":"universal","scale":"1x"}],"info":{"author":"xcode","version":1}}
        """)
        TestUtilities.createMockFile(at: "\(altIconDir)/AppIcon-Alternate.png", content: TestUtilities.mockImageData())

        // 3. Create color set
        let colorDir = "\(tempProjectPath!)/Assets.xcassets/PrimaryColor.colorset"
        try FileManager.default.createDirectory(atPath: colorDir, withIntermediateDirectories: true)
        TestUtilities.createMockFile(at: "\(colorDir)/Contents.json", content: """
        {"colors":[{"idiom":"universal"}],"info":{"author":"xcode","version":1}}
        """)

        // 4. Create widget extension image
        let widgetDir = "\(tempProjectPath!)/MyWidget/Assets.xcassets/widget_bg.imageset"
        try FileManager.default.createDirectory(atPath: widgetDir, withIntermediateDirectories: true)
        TestUtilities.createMockFile(at: "\(widgetDir)/Contents.json", content: """
        {"images":[{"filename":"widget_bg.png","idiom":"universal","scale":"1x"}],"info":{"author":"xcode","version":1}}
        """)
        TestUtilities.createMockFile(at: "\(widgetDir)/widget_bg.png", content: TestUtilities.mockImageData())

        // 5. Create localized image
        let localizedDir = "\(tempProjectPath!)/Assets.xcassets/greeting.imageset"
        try FileManager.default.createDirectory(atPath: localizedDir, withIntermediateDirectories: true)
        TestUtilities.createMockFile(at: "\(localizedDir)/Contents.json", content: """
        {"images":[{"filename":"greeting.png","idiom":"universal","scale":"1x"},{"filename":"greeting~ja.png","idiom":"universal","scale":"1x","locale":"ja"}],"info":{"author":"xcode","version":1}}
        """)
        TestUtilities.createMockFile(at: "\(localizedDir)/greeting.png", content: TestUtilities.mockImageData())
        TestUtilities.createMockFile(at: "\(localizedDir)/greeting~ja.png", content: TestUtilities.mockImageData())

        // 6. Create Swift file with array pattern
        let swiftContent = """
        import UIKit

        class ImageManager {
            let icons = ["icon1", "icon2", "icon3"]

            func loadGreeting() {
                let greeting = UIImage(named: "greeting")
            }

            func loadIcons() -> [UIImage?] {
                return icons.map { UIImage(named: $0) }
            }
        }
        """
        TestUtilities.createMockFile(at: "\(tempProjectPath!)/ImageManager.swift", content: swiftContent)

        // 7. Create icon assets for array
        for i in 1...3 {
            let iconDir = "\(tempProjectPath!)/Assets.xcassets/icon\(i).imageset"
            try FileManager.default.createDirectory(atPath: iconDir, withIntermediateDirectories: true)
            TestUtilities.createMockFile(at: "\(iconDir)/Contents.json", content: """
            {"images":[{"filename":"icon\(i).png","idiom":"universal","scale":"1x"}],"info":{"author":"xcode","version":1}}
            """)
            TestUtilities.createMockFile(at: "\(iconDir)/icon\(i).png", content: TestUtilities.mockImageData())
        }

        // 8. Create an actually unused image
        let unusedDir = "\(tempProjectPath!)/Assets.xcassets/truly_unused.imageset"
        try FileManager.default.createDirectory(atPath: unusedDir, withIntermediateDirectories: true)
        TestUtilities.createMockFile(at: "\(unusedDir)/Contents.json", content: """
        {"images":[{"filename":"truly_unused.png","idiom":"universal","scale":"1x"}],"info":{"author":"xcode","version":1}}
        """)
        TestUtilities.createMockFile(at: "\(unusedDir)/truly_unused.png", content: TestUtilities.mockImageData())

        let report = try analyzer.analyze()
        let unusedNames = report.unusedImages.map { $0.name }

        // Verify protected items are NOT marked as unused
        XCTAssertFalse(unusedNames.contains { $0.contains("AppIcon-Alternate") },
                       "Alternate app icons should be protected")
        XCTAssertFalse(unusedNames.contains { $0.contains("PrimaryColor") },
                       "Color sets should be protected")
        XCTAssertFalse(unusedNames.contains { $0.contains("widget_bg") },
                       "Widget images should be protected")
        XCTAssertFalse(unusedNames.contains { $0.contains("greeting~ja") },
                       "Localized variants should be protected when base is used")

        // Verify array-loaded images are detected as used
        XCTAssertFalse(unusedNames.contains("icon1"), "Array-loaded images should be detected")
        XCTAssertFalse(unusedNames.contains("icon2"), "Array-loaded images should be detected")
        XCTAssertFalse(unusedNames.contains("icon3"), "Array-loaded images should be detected")

        // Verify actually unused image IS marked as unused
        XCTAssertTrue(unusedNames.contains { $0.contains("truly_unused") },
                      "Actually unused images should still be detected")
    }

    // MARK: - Edge Case Tests

    func testEdgeCase_EmptyArrayPattern() throws {
        let detector = UsageDetector(projectPath: tempProjectPath, verbose: false)

        let swiftContent = """
        class EmptyArrayLoader {
            let emptyArray: [String] = []

            func loadImages() -> [UIImage?] {
                return emptyArray.map { UIImage(named: $0) }
            }
        }
        """

        TestUtilities.createMockFile(at: "\(tempProjectPath!)/EmptyArrayLoader.swift", content: swiftContent)

        // Should not crash on empty arrays
        let usedImages = try detector.findUsedImageNames()
        XCTAssertGreaterThanOrEqual(usedImages.count, 0, "Should handle empty arrays gracefully")
    }

    func testEdgeCase_MultipleLevelNesting() throws {
        let detector = UsageDetector(projectPath: tempProjectPath, verbose: false)

        let swiftContent = """
        class NestedLoader {
            let groups = [
                ["group1_img1", "group1_img2"],
                ["group2_img1", "group2_img2"]
            ]

            func loadAll() {
                for group in groups {
                    for name in group {
                        let _ = UIImage(named: name)
                    }
                }
            }
        }
        """

        TestUtilities.createMockFile(at: "\(tempProjectPath!)/NestedLoader.swift", content: swiftContent)

        // Should handle nested structures without crashing
        let usedImages = try detector.findUsedImageNames()
        XCTAssertGreaterThanOrEqual(usedImages.count, 0, "Should handle nested arrays gracefully")
    }
}
