import Foundation
import Files

struct ProjectFile {
    let path: String
    let name: String
    let type: FileType
    
    enum FileType {
        case image(extension: String)
        case assetCatalog
        case sourceCode
        case interfaceBuilder
        case plist
        case strings
        case other
    }
}

struct AssetInfo {
    let name: String
    let path: String
    let variants: [AssetVariant]
}

struct AssetVariant {
    let filename: String
    let scale: String
    let idiom: String
    let size: String?
}

class ProjectParser {
    private let projectPath: String
    private let verbose: Bool
    
    init(projectPath: String, verbose: Bool = false) {
        self.projectPath = projectPath
        self.verbose = verbose
    }
    
    // MARK: - Project.pbxproj Parsing
    
    func parseProjectFile() throws -> [ProjectFile] {
        var projectFiles: [ProjectFile] = []
        
        // Find .xcodeproj directories
        let folder = try Folder(path: projectPath)
        for subfolder in folder.filteredRecursiveSubfolders {
            if subfolder.name.hasSuffix(".xcodeproj") {
                let pbxprojPath = "\(subfolder.path)/project.pbxproj"
                if let file = try? File(path: pbxprojPath) {
                    projectFiles.append(contentsOf: try parseProjectPbxproj(file))
                }
            }
        }
        
        return projectFiles
    }
    
    private func parseProjectPbxproj(_ file: File) throws -> [ProjectFile] {
        let content = try file.readAsString()
        var files: [ProjectFile] = []
        
        // Parse PBXFileReference sections
        let fileReferencePattern = #"\/\* (.+?) \*\/ = \{\s*isa = PBXFileReference;.*?(?:lastKnownFileType|explicitFileType) = ([^;]+);.*?path = ([^;]+);"#
        
        let regex = try NSRegularExpression(pattern: fileReferencePattern, options: [.dotMatchesLineSeparators])
        let matches = regex.matches(in: content, options: [], range: NSRange(content.startIndex..., in: content))
        
        for match in matches {
            if let nameRange = Range(match.range(at: 1), in: content),
               let typeRange = Range(match.range(at: 2), in: content),
               let pathRange = Range(match.range(at: 3), in: content) {
                
                let fileName = String(content[nameRange])
                let fileType = String(content[typeRange])
                let filePath = String(content[pathRange]).trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
                
                if let projectFile = createProjectFile(name: fileName, type: fileType, path: filePath) {
                    files.append(projectFile)
                }
            }
        }
        
        return files
    }
    
    private func createProjectFile(name: String, type: String, path: String) -> ProjectFile? {
        let fileType: ProjectFile.FileType
        
        switch type {
        case let t where t.contains("image"):
            let ext = (path as NSString).pathExtension.lowercased()
            fileType = .image(extension: ext)
        case "folder.assetcatalog":
            fileType = .assetCatalog
        case let t where t.contains("sourcecode.swift") || t.contains("sourcecode.c.objc"):
            fileType = .sourceCode
        case let t where t.contains("file.storyboard") || t.contains("file.xib"):
            fileType = .interfaceBuilder
        case "text.plist.xml":
            fileType = .plist
        case "text.plist.strings":
            fileType = .strings
        default:
            return nil // Skip non-relevant files
        }
        
        return ProjectFile(path: path, name: name, type: fileType)
    }
    
    // MARK: - Asset Catalog Contents.json Parsing
    
    func parseAssetCatalogs() throws -> [AssetInfo] {
        var assets: [AssetInfo] = []
        
        let folder = try Folder(path: projectPath)
        for subfolder in folder.filteredRecursiveSubfolders {
            if subfolder.name.hasSuffix(".xcassets") {
                assets.append(contentsOf: try parseAssetCatalog(subfolder))
            }
        }
        
        return assets
    }
    
    private func parseAssetCatalog(_ catalog: Folder) throws -> [AssetInfo] {
        var assets: [AssetInfo] = []
        
        for imageSet in catalog.filteredRecursiveSubfolders {
            if imageSet.name.hasSuffix(".imageset") {
                if let asset = try parseImageSet(imageSet) {
                    assets.append(asset)
                }
            }
        }
        
        return assets
    }
    
    private func parseImageSet(_ imageSet: Folder) throws -> AssetInfo? {
        let contentsFile = imageSet.path + "/Contents.json"
        guard let file = try? File(path: contentsFile) else { return nil }
        
        do {
            let content = try file.readAsString()
            guard let data = content.data(using: .utf8),
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let images = json["images"] as? [[String: Any]] else {
                return nil
            }
        
            let assetName = imageSet.name.replacingOccurrences(of: ".imageset", with: "")
            var variants: [AssetVariant] = []
            
            for imageInfo in images {
                let filename = imageInfo["filename"] as? String ?? ""
                let scale = imageInfo["scale"] as? String ?? "1x"
                let idiom = imageInfo["idiom"] as? String ?? "universal"
                let size = imageInfo["size"] as? String
                
                if !filename.isEmpty {
                    variants.append(AssetVariant(filename: filename, scale: scale, idiom: idiom, size: size))
                }
            }
            
            return AssetInfo(name: assetName, path: imageSet.path, variants: variants)
        } catch {
            // Handle JSON parsing errors gracefully
            if verbose {
                print("Warning: Failed to parse \(contentsFile): \(error)")
            }
            return nil
        }
    }
    
    // MARK: - Info.plist Parsing
    
    func parseInfoPlists() throws -> Set<String> {
        var imageReferences = Set<String>()
        
        let folder = try Folder(path: projectPath)
        for file in folder.filteredRecursiveFiles where file.name == "Info.plist" {
            do {
                let content = try file.readAsString()
                imageReferences.formUnion(parseInfoPlistContent(content))
            } catch {
                // Skip files with encoding/format issues but continue processing
                if verbose {
                    print("Warning: Skipping \(file.path) due to format issue: \(error)")
                }
                continue
            }
        }
        
        return imageReferences
    }
    
    private func parseInfoPlistContent(_ content: String) -> Set<String> {
        var references = Set<String>()
        
        // App Icon references
        let patterns = [
            #"<key>CFBundleIconName</key>\s*<string>([^<]+)</string>"#,
            #"<key>CFBundleIconFile</key>\s*<string>([^<]+)</string>"#,
            #"<key>UILaunchImageFile</key>\s*<string>([^<]+)</string>"#,
            #"<key>UILaunchStoryboardName</key>\s*<string>([^<]+)</string>"#,
            #"<string>([^<]*\.(?:png|jpg|jpeg|gif|svg|pdf))</string>"# // Any image file references
        ]
        
        for pattern in patterns {
            let regex = try? NSRegularExpression(pattern: pattern, options: [])
            let matches = regex?.matches(in: content, options: [], range: NSRange(content.startIndex..., in: content)) ?? []
            
            for match in matches {
                if let range = Range(match.range(at: 1), in: content) {
                    let reference = String(content[range])
                    references.insert(reference)
                    // Also add without extension for iOS naming conventions
                    if let nameWithoutExt = reference.components(separatedBy: ".").first, nameWithoutExt != reference {
                        references.insert(nameWithoutExt)
                    }
                }
            }
        }
        
        return references
    }
    
    // MARK: - Strings File Parsing
    
    func parseStringsFiles() throws -> Set<String> {
        var imageReferences = Set<String>()
        
        let folder = try Folder(path: projectPath)
        for file in folder.filteredRecursiveFiles where file.extension == "strings" {
            do {
                let content = try file.readAsString()
                imageReferences.formUnion(parseStringsFileContent(content))
            } catch {
                // Skip files with encoding issues but continue processing
                if verbose {
                    print("Warning: Skipping \(file.path) due to encoding issue: \(error)")
                }
                continue
            }
        }
        
        return imageReferences
    }
    
    private func parseStringsFileContent(_ content: String) -> Set<String> {
        var references = Set<String>()
        
        // Parse .strings file format: "key" = "value";
        let pattern = #""([^"]*)" = "([^"]+)";"#
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        let matches = regex?.matches(in: content, options: [], range: NSRange(content.startIndex..., in: content)) ?? []
        
        for match in matches {
            // Check both key and value for image references
            for i in 1...2 {
                if let range = Range(match.range(at: i), in: content) {
                    let text = String(content[range])
                    if isLikelyImageReference(text) {
                        references.insert(text)
                        // Also add without extension
                        if let nameWithoutExt = text.components(separatedBy: ".").first, nameWithoutExt != text {
                            references.insert(nameWithoutExt)
                        }
                    }
                }
            }
        }
        
        return references
    }
    
    // MARK: - Settings Bundle Parsing
    
    func parseSettingsBundle() throws -> Set<String> {
        var imageReferences = Set<String>()
        
        let folder = try Folder(path: projectPath)
        for subfolder in folder.filteredRecursiveSubfolders where subfolder.name.hasSuffix(".bundle") {
            // Parse plist files in bundle
            for file in subfolder.filteredRecursiveFiles where file.extension == "plist" {
                do {
                    let content = try file.readAsString()
                    imageReferences.formUnion(parseInfoPlistContent(content))
                } catch {
                    // Skip files with encoding/format issues but continue processing
                    if verbose {
                        print("Warning: Skipping \(file.path) due to format issue: \(error)")
                    }
                    continue
                }
            }
            
            // Parse strings files in bundle
            for file in subfolder.filteredRecursiveFiles where file.extension == "strings" {
                do {
                    let content = try file.readAsString()
                    imageReferences.formUnion(parseStringsFileContent(content))
                } catch {
                    // Skip files with encoding issues but continue processing
                    if verbose {
                        print("Warning: Skipping \(file.path) due to encoding issue: \(error)")
                    }
                    continue
                }
            }
            
            // Parse image files in bundle
            for file in subfolder.filteredRecursiveFiles {
                if let ext = file.extension, isImageExtension(ext) {
                    imageReferences.insert(file.nameExcludingExtension)
                }
            }
        }
        
        return imageReferences
    }
    
    // MARK: - Helper Methods
    
    func isLikelyImageReference(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        return lowercased.contains("icon") ||
               lowercased.contains("image") ||
               lowercased.contains("logo") ||
               lowercased.contains("button") ||
               lowercased.contains("background") ||
               lowercased.hasSuffix(".png") ||
               lowercased.hasSuffix(".jpg") ||
               lowercased.hasSuffix(".jpeg") ||
               lowercased.hasSuffix(".gif") ||
               lowercased.hasSuffix(".svg") ||
               lowercased.hasSuffix(".pdf")
    }
    
    func isImageExtension(_ ext: String) -> Bool {
        let imageExtensions = ["png", "jpg", "jpeg", "gif", "svg", "pdf"]
        return imageExtensions.contains(ext.lowercased())
    }
}