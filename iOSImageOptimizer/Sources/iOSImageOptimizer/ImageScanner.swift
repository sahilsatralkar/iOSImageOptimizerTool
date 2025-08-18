import Foundation
import Files
import CoreGraphics
import ImageIO

struct ImageAsset: Encodable {
    let name: String
    let path: String
    let size: Int64
    let type: ImageType
    let scale: Int?
    let dimensions: CGSize?
    let isInterlaced: Bool?
    let colorProfile: String?
    
    enum ImageType: Equatable, Encodable {
        case png, jpeg, pdf, svg
        case assetCatalog(scale: String)
    }
}

class ImageScanner {
    private let projectPath: String
    
    // Directories to exclude from scanning
    private let excludedDirectories = [
        "DerivedData",
        "Pods",
        ".build",
        "Carthage",
        "node_modules",
        ".git",
        "build",
        "Build",
        "xcuserdata",
        ".swiftpm",
        "SourcePackages"
    ]
    
    init(projectPath: String) {
        self.projectPath = projectPath
    }
    
    func scanForImages() throws -> [ImageAsset] {
        var images: [ImageAsset] = []
        
        let folder = try Folder(path: projectPath)
        
        // Scan for standalone images
        images.append(contentsOf: try scanStandaloneImages(in: folder))
        
        // Scan asset catalogs with proper name handling
        images.append(contentsOf: try scanAssetCatalogsEnhanced(in: folder))
        
        return images
    }
    
    private func shouldExcludeDirectory(_ path: String) -> Bool {
        for excluded in excludedDirectories {
            if path.contains("/\(excluded)/") || path.hasSuffix("/\(excluded)") {
                return true
            }
        }
        return false
    }
    
    private func scanStandaloneImages(in folder: Folder) throws -> [ImageAsset] {
        var images: [ImageAsset] = []
        
        // Use custom recursive traversal to properly skip excluded directories
        try scanFolderRecursively(folder) { file in
            guard let imageType = imageType(for: file.extension ?? "") else { return }
            
            // Skip images in .xcassets
            if file.path.contains(".xcassets") { return }
            
            let metadata = getImageMetadata(at: file.path, type: imageType)
            let asset = ImageAsset(
                name: file.nameExcludingExtension,
                path: file.path,
                size: getFileSize(file),
                type: imageType,
                scale: extractScale(from: file.name),
                dimensions: metadata.dimensions,
                isInterlaced: metadata.isInterlaced,
                colorProfile: metadata.colorProfile
            )
            images.append(asset)
        }
        
        return images
    }
    
    private func scanFolderRecursively(_ folder: Folder, fileHandler: (File) throws -> Void) throws {
        // Process files in current folder
        for file in folder.files {
            try fileHandler(file)
        }
        
        // Recursively process subfolders, skipping excluded ones
        for subfolder in folder.subfolders {
            // Skip excluded directories
            if excludedDirectories.contains(subfolder.name) {
                continue
            }
            
            try scanFolderRecursively(subfolder, fileHandler: fileHandler)
        }
    }
    
    private func scanAssetCatalogs(in folder: Folder) throws -> [ImageAsset] {
        var images: [ImageAsset] = []
        
        try scanFoldersRecursively(folder) { subfolder in
            if subfolder.name.hasSuffix(".xcassets") {
                images.append(contentsOf: try scanAssetCatalog(subfolder))
            }
        }
        
        return images
    }
    
    private func scanFoldersRecursively(_ folder: Folder, folderHandler: (Folder) throws -> Void) throws {
        // Process current folder
        try folderHandler(folder)
        
        // Recursively process subfolders, skipping excluded ones
        for subfolder in folder.subfolders {
            // Skip excluded directories
            if excludedDirectories.contains(subfolder.name) {
                continue
            }
            
            try scanFoldersRecursively(subfolder, folderHandler: folderHandler)
        }
    }
    
    private func scanAssetCatalog(_ catalog: Folder) throws -> [ImageAsset] {
        var images: [ImageAsset] = []
        
        for imageSet in catalog.filteredRecursiveSubfolders {
            if imageSet.name.hasSuffix(".imageset") {
                let assetName = imageSet.name.replacingOccurrences(of: ".imageset", with: "")
                
                for file in imageSet.files {
                    if let imageType = imageType(for: file.extension ?? "") {
                        let scale = extractScale(from: file.name) ?? 1
                        let metadata = getImageMetadata(at: file.path, type: imageType)
                        let asset = ImageAsset(
                            name: assetName,
                            path: file.path,
                            size: getFileSize(file),
                            type: .assetCatalog(scale: "\(scale)x"),
                            scale: scale,
                            dimensions: metadata.dimensions,
                            isInterlaced: metadata.isInterlaced,
                            colorProfile: metadata.colorProfile
                        )
                        images.append(asset)
                    }
                }
            }
        }
        
        return images
    }
    
    private func imageType(for fileExtension: String) -> ImageAsset.ImageType? {
        switch fileExtension.lowercased() {
        case "png": return .png
        case "jpg", "jpeg": return .jpeg
        case "pdf": return .pdf
        case "svg": return .svg
        default: return nil
        }
    }
    
    private func extractScale(from filename: String) -> Int? {
        if filename.contains("@3x") { return 3 }
        if filename.contains("@2x") { return 2 }
        return 1
    }
    
    private func getFileSize(_ file: File) -> Int64 {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
            return attributes[.size] as? Int64 ?? 0
        } catch {
            return 0
        }
    }
    
    // MARK: - Image Metadata Reading
    
    private struct ImageMetadata {
        let dimensions: CGSize?
        let isInterlaced: Bool?
        let colorProfile: String?
    }
    
    private func getImageMetadata(at path: String, type: ImageAsset.ImageType) -> ImageMetadata {
        let dimensions = getImageDimensions(at: path)
        let isInterlaced = type == .png ? checkPNGInterlacing(at: path) : nil
        let colorProfile = readColorProfile(at: path)
        
        return ImageMetadata(
            dimensions: dimensions,
            isInterlaced: isInterlaced,
            colorProfile: colorProfile
        )
    }
    
    private func getImageDimensions(at path: String) -> CGSize? {
        guard let imageSource = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let imageProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any] else {
            return nil
        }
        
        guard let width = imageProperties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = imageProperties[kCGImagePropertyPixelHeight] as? NSNumber else {
            return nil
        }
        
        return CGSize(width: width.doubleValue, height: height.doubleValue)
    }
    
    private func checkPNGInterlacing(at path: String) -> Bool? {
        guard let data = NSData(contentsOfFile: path),
              data.length >= 33 else {
            return nil
        }
        
        // PNG interlace method is at byte 28 in the IHDR chunk
        // PNG signature (8 bytes) + IHDR length (4) + "IHDR" (4) + width (4) + height (4) + bit depth (1) + color type (1) + compression (1) + filter (1) + interlace (1)
        var interlaceMethod: UInt8 = 0
        data.getBytes(&interlaceMethod, range: NSRange(location: 28, length: 1))
        
        return interlaceMethod == 1 // 1 = interlaced, 0 = non-interlaced
    }
    
    private func readColorProfile(at path: String) -> String? {
        guard let imageSource = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let imageProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any] else {
            return nil
        }
        
        // Check for color profile information
        if let colorModel = imageProperties[kCGImagePropertyColorModel] as? String {
            return colorModel
        }
        
        // Check for ICC profile (use a string key since the constant might not be available)
        if let profileDescription = imageProperties["ProfileDescription" as CFString] as? String {
            return profileDescription
        }
        
        // Check for embedded color space
        if imageProperties[kCGImagePropertyHasAlpha] != nil {
            return "RGB" // Basic fallback
        }
        
        return nil
    }
    
    // MARK: - Enhanced Asset Catalog Scanning
    
    private func scanAssetCatalogsEnhanced(in folder: Folder) throws -> [ImageAsset] {
        var images: [ImageAsset] = []
        
        try scanFoldersRecursively(folder) { subfolder in
            if subfolder.name.hasSuffix(".xcassets") {
                let projectParser = ProjectParser(projectPath: projectPath)
                let assetInfos = try projectParser.parseAssetCatalogs()
                
                for assetInfo in assetInfos {
                    for variant in assetInfo.variants {
                        let variantPath = "\(assetInfo.path)/\(variant.filename)"
                        if let file = try? File(path: variantPath) {
                            let imageType = imageType(for: (variantPath as NSString).pathExtension) ?? .png
                            let metadata = getImageMetadata(at: variantPath, type: imageType)
                            
                            let asset = ImageAsset(
                                name: assetInfo.name, // Use the actual asset name from Contents.json
                                path: variantPath,
                                size: getFileSize(file),
                                type: .assetCatalog(scale: variant.scale),
                                scale: extractScaleFromVariant(variant.scale),
                                dimensions: metadata.dimensions,
                                isInterlaced: metadata.isInterlaced,
                                colorProfile: metadata.colorProfile
                            )
                            images.append(asset)
                        }
                    }
                }
            }
        }
        
        return images
    }
    
    private func extractScaleFromVariant(_ scaleString: String) -> Int {
        if scaleString.contains("3x") { return 3 }
        if scaleString.contains("2x") { return 2 }
        return 1
    }
}