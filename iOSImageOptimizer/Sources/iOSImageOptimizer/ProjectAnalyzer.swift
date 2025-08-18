import Foundation
import Files
import Rainbow

struct AnalysisReport {
    let totalImages: Int
    let unusedImages: [ImageAsset]
    let totalSize: Int64
    let unusedImageSize: Int64
    let totalPotentialSavings: Int64
    
    // Apple compliance results
    let appleComplianceResults: AppleComplianceResults
    
    func printToConsole() {
        print("\n📊 " + "Analysis Complete".bold)
        print("=" * 50)
        
        // Apple compliance score
        let scoreColor = getScoreColor(appleComplianceResults.complianceScore)
        print("\n🎯 " + "Apple Compliance Score: \(appleComplianceResults.complianceScore)/100".applyingColor(scoreColor).bold)
        
        print("\n📈 " + "Summary:".bold)
        print("  Total images: \(totalImages)")
        print("  Total image size: \(formatBytes(totalSize))")
        print("  Unused images: \(unusedImages.count)".red)
        print("  Potential savings: \(formatBytes(totalPotentialSavings))".green)
        
        print("\n🍎 " + "Apple Guidelines Compliance:".bold)
        print("  PNG interlacing issues: \(appleComplianceResults.pngInterlacingIssues.count)".colorForIssueCount(appleComplianceResults.pngInterlacingIssues.count))
        print("  Color profile issues: \(appleComplianceResults.colorProfileIssues.count)".colorForIssueCount(appleComplianceResults.colorProfileIssues.count))
        print("  Asset catalog issues: \(appleComplianceResults.assetCatalogIssues.count)".colorForIssueCount(appleComplianceResults.assetCatalogIssues.count))
        print("  Design quality issues: \(appleComplianceResults.designQualityIssues.count)".colorForIssueCount(appleComplianceResults.designQualityIssues.count))
        
        printDetailedIssues()
        printActionableRecommendations()
        
        
    }
    
    func exportJSON() throws {
        let jsonData = try JSONEncoder().encode(self)
        print(String(data: jsonData, encoding: .utf8) ?? "{}")
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    private func getScoreColor(_ score: Int) -> ColorType {
        if score >= 80 { return .named(.green) }
        if score >= 60 { return .named(.yellow) }
        return .named(.red)
    }
    
    private func printDetailedIssues() {
        if !unusedImages.isEmpty {
            print("\n🗑️  " + "Unused Images:".bold.red)
            for image in unusedImages.prefix(10) {
                print("  ❌ \(image.name) (\(formatBytes(image.size)))")
                print("     Path: \(image.path)")
            }
            if unusedImages.count > 10 {
                print("  ... and \(unusedImages.count - 10) more")
            }
        }
        
        if !appleComplianceResults.pngInterlacingIssues.isEmpty {
            print("\n🖼️  " + "PNG Interlacing Issues:".bold.yellow)
            for issue in appleComplianceResults.pngInterlacingIssues.prefix(5) {
                print("  ⚠️ \(issue.image.name) - \(issue.performanceImpact) impact")
                print("     \(issue.recommendation)".dim)
            }
            if appleComplianceResults.pngInterlacingIssues.count > 5 {
                print("  ... and \(appleComplianceResults.pngInterlacingIssues.count - 5) more")
            }
        }
        
        if !appleComplianceResults.colorProfileIssues.isEmpty {
            print("\n🎨  " + "Color Profile Issues:".bold.yellow)
            for issue in appleComplianceResults.colorProfileIssues.prefix(5) {
                print("  🟡 \(issue.image.name) - \(getIssueTypeDescription(issue.issueType))")
                print("     \(issue.recommendation)".dim)
            }
            if appleComplianceResults.colorProfileIssues.count > 5 {
                print("  ... and \(appleComplianceResults.colorProfileIssues.count - 5) more")
            }
        }
        
        if !appleComplianceResults.assetCatalogIssues.isEmpty {
            print("\n📁  " + "Asset Catalog Issues:".bold.yellow)
            for issue in appleComplianceResults.assetCatalogIssues.prefix(5) {
                print("  📦 \(issue.image.name) - \(getAssetIssueDescription(issue.issueType))")
                print("     \(issue.recommendation)".dim)
            }
            if appleComplianceResults.assetCatalogIssues.count > 5 {
                print("  ... and \(appleComplianceResults.assetCatalogIssues.count - 5) more")
            }
        }
        
        if !appleComplianceResults.designQualityIssues.isEmpty {
            print("\n🎨  " + "Design Quality Issues:".bold.yellow)
            for issue in appleComplianceResults.designQualityIssues.prefix(5) {
                print("  🔍 \(issue.image.name) - \(issue.impact)")
                print("     \(issue.recommendation)".dim)
            }
            if appleComplianceResults.designQualityIssues.count > 5 {
                print("  ... and \(appleComplianceResults.designQualityIssues.count - 5) more")
            }
        }
    }
    
    private func printActionableRecommendations() {
        print("\n💡 " + "Prioritized Action Items:".bold)
        
        var recommendations: [(priority: Int, action: String)] = []
        
        if !unusedImages.isEmpty {
            recommendations.append((1, "Remove \(unusedImages.count) unused images to save \(formatBytes(unusedImageSize))"))
        }
        
        let criticalPNG = appleComplianceResults.pngInterlacingIssues.filter { $0.performanceImpact == "Critical" }
        if !criticalPNG.isEmpty {
            recommendations.append((2, "Fix \(criticalPNG.count) critical PNG interlacing issues"))
        }
        
        let missingProfiles = appleComplianceResults.colorProfileIssues.filter { 
            if case .missing = $0.issueType { return true }
            return false
        }
        if !missingProfiles.isEmpty {
            recommendations.append((3, "Add color profiles to \(missingProfiles.count) images"))
        }
        
        let criticalAssetIssues = appleComplianceResults.assetCatalogIssues.filter { 
            if case .missingScaleVariant = $0.issueType { return true }
            return false
        }
        if !criticalAssetIssues.isEmpty {
            recommendations.append((4, "Add missing scale variants for \(criticalAssetIssues.count) images"))
        }
        
        let designIssues = appleComplianceResults.designQualityIssues.filter {
            $0.issueType == .tooSmallForHighRes || $0.issueType == .inefficientDimensions
        }
        if !designIssues.isEmpty {
            recommendations.append((5, "Address \(designIssues.count) design quality issues"))
        }
        
        for (index, recommendation) in recommendations.enumerated() {
            print("  \(index + 1). \(recommendation.action)")
        }
        
        if recommendations.isEmpty {
            print("  ✅ No critical issues found! Your images follow Apple guidelines well.")
        }
    }
    
    private func getIssueTypeDescription(_ issueType: ColorProfileIssue.ColorProfileIssueType) -> String {
        switch issueType {
        case .missing:
            return "Missing color profile"
        case .incompatible(let current, let recommended):
            return "Incompatible profile (\(current) → \(recommended))"
        case .outdated(let current):
            return "Outdated profile (\(current))"
        }
    }
    
    private func getAssetIssueDescription(_ issueType: AssetCatalogIssue.AssetCatalogIssueType) -> String {
        switch issueType {
        case .shouldBeInCatalog:
            return "Should be in Asset Catalog"
        case .missingScaleVariant(let missing):
            return "Missing scale variants: \(missing.joined(separator: ", "))"
        case .orphanedScale(let scale):
            return "Orphaned scale variant: \(scale)"
        case .incorrectNaming:
            return "Incorrect naming convention"
        }
    }
}

extension AnalysisReport: Encodable {}

// MARK: - String Extensions for Colors

extension String {
    func colorForIssueCount(_ count: Int) -> String {
        if count == 0 { return self.green }
        if count <= 3 { return self.yellow }
        return self.red
    }
}

class ProjectAnalyzer {
    private let projectPath: String
    private let verbose: Bool
    
    
    init(projectPath: String, verbose: Bool = false) {
        self.projectPath = projectPath
        self.verbose = verbose
    }
    
    func analyze() throws -> AnalysisReport {
        // Step 1: Find all images
        if verbose { print("Scanning for images...") }
        let scanner = ImageScanner(projectPath: projectPath)
        let allImages = try scanner.scanForImages()
        
        if verbose { print("Found \(allImages.count) images") }
        
        // Step 2: Find used images (includes pattern-based detection)
        if verbose { print("Detecting image usage...") }
        let detector = UsageDetector(projectPath: projectPath, verbose: verbose)
        let usedImageNames = try detector.findUsedImageNames()
        
        // Step 3: Identify unused images with enhanced cross-referencing
        let unusedImages = try identifyUnusedImagesWithCrossValidation(allImages: allImages, usedImageNames: usedImageNames)
        
        // Step 4: Apple compliance validation
        if verbose { print("Running Apple compliance validation...") }
        let validator = AppleComplianceValidator()
        let appleComplianceResults = validator.validateImages(allImages)
        
        // Step 5: Calculate metrics (only unused images provide savings)
        let totalSize = allImages.reduce(0) { $0 + $1.size }
        let unusedImageSize = unusedImages.reduce(0) { $0 + $1.size }
        let totalPotentialSavings = unusedImageSize
        
        return AnalysisReport(
            totalImages: allImages.count,
            unusedImages: unusedImages,
            totalSize: totalSize,
            unusedImageSize: unusedImageSize,
            totalPotentialSavings: totalPotentialSavings,
            appleComplianceResults: appleComplianceResults
        )
    }
    
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    // MARK: - Enhanced Cross-Validation Logic
    
    private func identifyUnusedImagesWithCrossValidation(allImages: [ImageAsset], usedImageNames: Set<String>) throws -> [ImageAsset] {
        var unusedImages: [ImageAsset] = []
        
        // Build comprehensive name variants for each image
        for image in allImages {
            // Skip test reference images, watchOS complications, and system-managed assets
            if isTestReferenceImage(image) || isWatchOSComplication(image) || isSystemManagedAsset(image) {
                if verbose {
                    let type = isTestReferenceImage(image) ? "test" : 
                              isWatchOSComplication(image) ? "watchOS" : "system"
                    print("Skipping special image: \(image.name) (\(type))")
                }
                continue
            }
            
            let imageNameVariants = generateImageNameVariants(for: image)
            
            // Check if ANY variant is referenced in the code
            let isUsed = imageNameVariants.contains { variant in
                usedImageNames.contains(variant)
            }
            
            if !isUsed {
                // Double-check with file system validation
                if !isReferencedInProjectFiles(imageName: image.name) {
                    unusedImages.append(image)
                }
            }
        }
        
        return unusedImages
    }
    
    private func generateImageNameVariants(for image: ImageAsset) -> Set<String> {
        var variants = Set<String>()
        
        // Add the base name
        variants.insert(image.name)
        
        // Add name without extension
        if let nameWithoutExt = image.name.components(separatedBy: ".").first, nameWithoutExt != image.name {
            variants.insert(nameWithoutExt)
        }
        
        // Add scale variants (@2x, @3x patterns)
        let baseName = image.name.replacingOccurrences(of: "@2x", with: "").replacingOccurrences(of: "@3x", with: "")
        variants.insert(baseName)
        variants.insert("\(baseName)@2x")
        variants.insert("\(baseName)@3x")
        
        // Add filename variants from asset catalog structure
        if case .assetCatalog = image.type {
            let pathComponents = image.path.components(separatedBy: "/")
            if let imagesetFolder = pathComponents.first(where: { $0.hasSuffix(".imageset") }) {
                let assetFolderName = imagesetFolder.replacingOccurrences(of: ".imageset", with: "")
                variants.insert(assetFolderName)
            }
        }
        
        // Add common iOS naming patterns
        variants.insert(image.name.lowercased())
        variants.insert(image.name.uppercased())
        
        return variants
    }
    
    private func isReferencedInProjectFiles(imageName: String) -> Bool {
        // Additional safety check - look for the image name as a plain string anywhere in project files
        do {
            let folder = try Folder(path: projectPath)
            for file in folder.filteredRecursiveFiles {
                if let ext = file.extension,
                   ["swift", "m", "mm", "h", "storyboard", "xib", "plist", "strings"].contains(ext) {
                    let content = try file.readAsString()
                    if content.contains(imageName) {
                        return true
                    }
                }
            }
        } catch {
            // If there's an error reading files, err on the side of caution
            return true
        }
        
        return false
    }
    
    private func isTestReferenceImage(_ image: ImageAsset) -> Bool {
        let path = image.path.lowercased()
        let name = image.name.lowercased()
        
        return path.contains("referenceimages") ||
               path.contains("tests/") ||
               path.contains("test/") ||
               name.contains("test") ||
               name.contains("snapshot") ||
               path.contains("snapshot")
    }
    
    private func isWatchOSComplication(_ image: ImageAsset) -> Bool {
        let path = image.path.lowercased()
        
        return path.contains("watch extension") ||
               path.contains("watchkit") ||
               path.contains("complication") ||
               path.contains(".watchapp/") ||
               path.contains("watch app")
    }
    
    private func isSystemManagedAsset(_ image: ImageAsset) -> Bool {
        let path = image.path.lowercased()
        
        return path.contains("appicon.solidimagestack") ||      // visionOS app icons
               path.contains("appicon.appiconset") ||           // iOS app icons
               path.contains("launchimage.launchimage") ||      // Launch images
               path.contains(".solidimagestacklayer") ||        // visionOS icon layers
               path.contains("assets.car") ||                   // Compiled assets
               (path.contains("appicon") && path.contains(".imageset")) // App icon variants
    }
}