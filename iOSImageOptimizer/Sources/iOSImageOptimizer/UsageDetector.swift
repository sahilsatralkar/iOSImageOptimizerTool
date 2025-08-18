import Foundation
import Files

class UsageDetector {
    private let projectPath: String
    private let verbose: Bool
    
    init(projectPath: String, verbose: Bool = false) {
        self.projectPath = projectPath
        self.verbose = verbose
    }
    
    func findUsedImageNames() throws -> Set<String> {
        var usedImages = Set<String>()
        
        let folder = try Folder(path: projectPath)
        let projectParser = ProjectParser(projectPath: projectPath, verbose: verbose)
        
        // Check for runtime-computed image names
        let runtimePatterns = try detectRuntimeImagePatterns(in: folder)
        if !runtimePatterns.isEmpty && verbose {
            print("\n⚠️  Runtime-computed image names detected:")
            for pattern in runtimePatterns {
                print("  📱 \(pattern.file): \(pattern.pattern)")
            }
            print("  💡 Some images may appear unused but are loaded dynamically\n")
        }
        
        // Scan Swift files
        for file in folder.filteredRecursiveFiles where file.extension == "swift" {
            do {
                let content = try file.readAsString()
                usedImages.formUnion(findImageReferences(in: content, fileType: .swift))
            } catch {
                if verbose {
                    print("Warning: Skipping \(file.path) due to encoding issue: \(error)")
                }
                continue
            }
        }
        
        // Scan Objective-C implementation files
        for file in folder.filteredRecursiveFiles where file.extension == "m" || file.extension == "mm" {
            do {
                let content = try file.readAsString()
                usedImages.formUnion(findImageReferences(in: content, fileType: .objectiveC))
            } catch {
                if verbose {
                    print("Warning: Skipping \(file.path) due to encoding issue: \(error)")
                }
                continue
            }
        }
        
        // Scan Objective-C header files
        for file in folder.filteredRecursiveFiles where file.extension == "h" {
            do {
                let content = try file.readAsString()
                usedImages.formUnion(findImageReferences(in: content, fileType: .objectiveC))
            } catch {
                if verbose {
                    print("Warning: Skipping \(file.path) due to encoding issue: \(error)")
                }
                continue
            }
        }
        
        // Scan Storyboards and XIBs
        for file in folder.filteredRecursiveFiles where file.extension == "storyboard" || file.extension == "xib" {
            do {
                let content = try file.readAsString()
                usedImages.formUnion(findImageReferences(in: content, fileType: .interfaceBuilder))
            } catch {
                if verbose {
                    print("Warning: Skipping \(file.path) due to encoding issue: \(error)")
                }
                continue
            }
        }
        
        // Use ProjectParser for comprehensive scanning
        usedImages.formUnion(try projectParser.parseInfoPlists())
        usedImages.formUnion(try projectParser.parseStringsFiles())
        usedImages.formUnion(try projectParser.parseSettingsBundle())
        
        // Find string constants that might be image names
        usedImages.formUnion(try findStringConstants(in: folder))
        
        // CORE: Detect string interpolation patterns (always enabled)
        usedImages.formUnion(try detectInterpolationImageNames(in: folder))
        
        if verbose {
            print("Found \(usedImages.count) unique image references")
        }
        
        return usedImages
    }
    
    private enum FileType {
        case swift, objectiveC, interfaceBuilder
    }
    
    private func findImageReferences(in content: String, fileType: FileType) -> Set<String> {
        var references = Set<String>()
        
        let patterns: [String]
        
        switch fileType {
        case .swift:
            patterns = [
                #"UIImage\s*\(\s*named:\s*"([^"]+)""#,                    // UIImage(named: "...")
                #"Image\s*\(\s*"([^"]+)""#,                               // SwiftUI Image("...")
                #"UIImage\s*\(\s*systemName:\s*"([^"]+)""#,              // SF Symbols
                #"#imageLiteral\s*\(\s*resourceName:\s*"([^"]+)""#,       // Image literals
                #"UIImage\s*\(\s*contentsOfFile:\s*"([^"]+)""#,          // UIImage(contentsOfFile: "...")
                #"Bundle\.main\.path\s*\(\s*forResource:\s*"([^"]+)""#,   // Bundle.main.path(forResource: "...")
                #"NSBundle\.main\.pathForResource\s*\(\s*"([^"]+)""#,     // NSBundle.main.pathForResource("...")
                #""([^"]*\.(png|jpg|jpeg|gif|svg|pdf))""#,               // Direct file references with extensions
                #"let\s+\w+\s*=\s*"([^"]+)""#,                          // String constants
                #"static\s+let\s+\w+\s*=\s*"([^"]+)""#,                  // Static string constants
                #"case\s+\w+\s*=\s*"([^"]+)""#,                          // Enum cases
                #"recordSnapshot\s*\(\s*[^)]*named:\s*"([^"]+)""#,       // Snapshot testing
                #"verifyView\s*\(\s*[^)]*named:\s*"([^"]+)""#,           // Snapshot testing
                #"FBSnapshotVerifyView\s*\(\s*[^)]*identifier:\s*"([^"]+)""#, // FBSnapshotTestCase
                #"CLKComplicationTemplate"#,                              // WatchOS complications (partial match)
                #"CLKImageProvider\s*\(\s*onePieceImage:\s*UIImage\s*\(\s*named:\s*"([^"]+)""#, // WatchOS image provider
                #"spriteWithFile:\s*@"([^"]+)""#,                     // Cocos2D sprite loading
                #"imageWithContentsOfFile:\s*@"([^"]+)""#,            // Direct file loading
                #"itemWithNormalImage:\s*@"([^"]+)""#                 // Cocos2D menu items
            ]
            
        case .objectiveC:
            patterns = [
                #"\[UIImage\s+imageNamed:\s*@"([^"]+)""#,                // [UIImage imageNamed:@"..."]
                #"imageWithContentsOfFile:[^"]*@"([^"]+)""#,              // imageWithContentsOfFile
                #"\[NSBundle\s+pathForResource:\s*@"([^"]+)""#,          // [NSBundle pathForResource:@"..."]
                #"UIImageNamed\s*\(\s*@"([^"]+)""#,                      // UIImageNamed(@"...")
                #"@"([^"]*\.(png|jpg|jpeg|gif|svg|pdf))""#,              // Direct file references
                #"#define\s+\w+\s+@"([^"]+)""#,                          // #define constants
                #"NSString\s*\*\s*\w+\s*=\s*@"([^"]+)""#                  // NSString constants
            ]
            
        case .interfaceBuilder:
            patterns = [
                #"image="([^"]+)""#,                                      // image="..."
                #"imageName="([^"]+)""#,                                  // imageName="..."
                #"<image[^>]+name="([^"]+)""#,                           // <image name="...">
                #"<imageView[^>]+image="([^"]+)""#,                      // <imageView image="...">
                #"backgroundImage="([^"]+)""#,                           // backgroundImage="..."
                #"selectedImage="([^"]+)""#,                             // selectedImage="..."
                #"<tabBarItem[^>]+image="([^"]+)""#,                     // <tabBarItem image="...">
                #"<navigationItem[^>]+titleView="([^"]+)""#,              // <navigationItem titleView="...">
                #"<button[^>]+backgroundImage="([^"]+)""#                 // <button backgroundImage="...">
            ]
        }
        
        for pattern in patterns {
            let regex = try? NSRegularExpression(pattern: pattern, options: [])
            let matches = regex?.matches(in: content, options: [], range: NSRange(content.startIndex..., in: content)) ?? []
            
            for match in matches {
                if let range = Range(match.range(at: 1), in: content) {
                    let imageName = String(content[range])
                    references.insert(imageName)
                    
                    // For framework-managed HD images (Cocos2D, etc.)
                    if fileType == .swift || fileType == .objectiveC {
                        let hdVariants = generateFrameworkHDVariants(for: imageName)
                        references.formUnion(hdVariants)
                    }
                }
            }
        }
        
        return references
    }
    
    private func findStringConstants(in folder: Folder) throws -> Set<String> {
        var constants = Set<String>()
        
        for file in folder.filteredRecursiveFiles where file.extension == "swift" {
            do {
                let content = try file.readAsString()
                
                // Find string constants that might be image names
                let constantPatterns = [
                    #"let\s+\w+\s*=\s*"([^"]+\.(?:png|jpg|jpeg|gif|svg|pdf))""#,  // let imageName = "image.png"
                    #"static\s+let\s+\w+\s*=\s*"([^"]+)""#,                          // static let imageName = "..."
                    #"case\s+\w+\s*=\s*"([^"]+)""#                                   // enum case imageName = "..."
                ]
                
                for pattern in constantPatterns {
                    let regex = try? NSRegularExpression(pattern: pattern, options: [])
                    let matches = regex?.matches(in: content, options: [], range: NSRange(content.startIndex..., in: content)) ?? []
                    
                    for match in matches {
                        if let range = Range(match.range(at: 1), in: content) {
                            let constantValue = String(content[range])
                            // Only include if it looks like an image name
                            if isLikelyImageName(constantValue) {
                                constants.insert(constantValue)
                                // Also add without extension for iOS naming conventions
                                if let nameWithoutExt = constantValue.components(separatedBy: ".").first, nameWithoutExt != constantValue {
                                    constants.insert(nameWithoutExt)
                                }
                            }
                        }
                    }
                }
            } catch {
                // Skip files with encoding issues but continue processing
                continue
            }
        }
        
        return constants
    }
    
    private func isLikelyImageName(_ name: String) -> Bool {
        let lowercased = name.lowercased()
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
    
    private func generateFrameworkHDVariants(for imageName: String) -> Set<String> {
        var variants = Set<String>()
        
        // Remove extension for processing
        let nameWithoutExt = imageName.replacingOccurrences(of: ".png", with: "")
                                     .replacingOccurrences(of: ".jpg", with: "")
                                     .replacingOccurrences(of: ".jpeg", with: "")
        
        // Common framework HD suffixes
        let hdSuffixes = ["-hd", "@2x", "@3x", "-ipad", "-ipadhd"]
        
        for suffix in hdSuffixes {
            variants.insert("\(nameWithoutExt)\(suffix)")
            variants.insert("\(nameWithoutExt)\(suffix).png")
            variants.insert("\(nameWithoutExt)\(suffix).jpg")
        }
        
        // Also add original name variants
        variants.insert(nameWithoutExt)
        variants.insert("\(nameWithoutExt).png")
        variants.insert("\(nameWithoutExt).jpg")
        
        return variants
    }
    
    // MARK: - Runtime Pattern Detection
    
    struct RuntimePattern {
        let file: String
        let pattern: String
        let line: Int
    }
    
    private func detectRuntimeImagePatterns(in folder: Folder) throws -> [RuntimePattern] {
        var patterns: [RuntimePattern] = []
        
        for file in folder.filteredRecursiveFiles where file.extension == "swift" || file.extension == "m" || file.extension == "mm" {
            do {
                let content = try file.readAsString()
                patterns.append(contentsOf: findRuntimePatterns(in: content, fileName: file.name))
            } catch {
                continue
            }
        }
        
        return patterns
    }
    
    private func findRuntimePatterns(in content: String, fileName: String) -> [RuntimePattern] {
        var patterns: [RuntimePattern] = []
        let lines = content.components(separatedBy: .newlines)
        
        let runtimePatterns = [
            // String interpolation patterns
            (#"Image\s*\(\s*\"[^\"]*\\\([^)]+\)[^\"]*\""#, "String interpolation in Image()"),
            (#"UIImage\s*\(\s*named:\s*\"[^\"]*\\\([^)]+\)[^\"]*\""#, "String interpolation in UIImage(named:)"),
            (#"spriteWithFile:\s*@\"[^\"]*\\\([^)]+\)[^\"]*\""#, "String interpolation in Cocos2D"),
            
            // Variable-based loading
            (#"Image\s*\(\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*\)"#, "Variable-based Image loading"),
            (#"UIImage\s*\(\s*named:\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*\)"#, "Variable-based UIImage loading"),
            (#"spriteWithFile:\s*([a-zA-Z_][a-zA-Z0-9_]*)"#, "Variable-based Cocos2D loading"),
            
            // Function-based generation
            (#"Image\s*\(\s*\w+\s*\([^)]*\)\s*\)"#, "Function-generated Image name"),
            (#"UIImage\s*\(\s*named:\s*\w+\s*\([^)]*\)\s*\)"#, "Function-generated UIImage name"),
            (#"spriteWithFile:\s*\w+\s*\([^)]*\)"#, "Function-generated Cocos2D name"),
            
            // Array/collection access
            (#"Image\s*\(\s*\w+\s*\[\s*[^]]+\s*\]\s*\)"#, "Array-based Image selection"),
            (#"UIImage\s*\(\s*named:\s*\w+\s*\[\s*[^]]+\s*\]\s*\)"#, "Array-based UIImage selection"),
            
            // Property access
            (#"Image\s*\(\s*\w+\.\w+\s*\)"#, "Property-based Image loading"),
            (#"UIImage\s*\(\s*named:\s*\w+\.\w+\s*\)"#, "Property-based UIImage loading")
        ]
        
        for (lineIndex, line) in lines.enumerated() {
            for (pattern, description) in runtimePatterns {
                let regex = try? NSRegularExpression(pattern: pattern, options: [])
                let matches = regex?.matches(in: line, options: [], range: NSRange(line.startIndex..., in: line)) ?? []
                
                if !matches.isEmpty {
                    patterns.append(RuntimePattern(
                        file: fileName,
                        pattern: "\(description): \(line.trimmingCharacters(in: .whitespaces))",
                        line: lineIndex + 1
                    ))
                }
            }
        }
        
        return patterns
    }
    
    // MARK: - Core String Interpolation Detection (Always Enabled)
    
    private func detectInterpolationImageNames(in folder: Folder) throws -> Set<String> {
        var resolvedImages = Set<String>()
        
        // Find all interpolation patterns
        var interpolationPatterns: [String] = []
        var variableAssignments: [String: [String]] = [:]
        
        for file in folder.filteredRecursiveFiles where file.extension == "swift" {
            do {
                let content = try file.readAsString()
                
                // Extract variable assignments
                let assignments = extractVariableAssignments(from: content)
                for (key, values) in assignments {
                    variableAssignments[key, default: []].append(contentsOf: values)
                }
                
                // Extract interpolation patterns
                interpolationPatterns.append(contentsOf: extractInterpolationPatterns(from: content))
            } catch {
                continue
            }
        }
        
        // Resolve interpolations with known variables
        for pattern in interpolationPatterns {
            let resolved = resolveInterpolationPattern(pattern, with: variableAssignments)
            resolvedImages.formUnion(resolved)
        }
        
        return resolvedImages
    }
    
    private func extractVariableAssignments(from content: String) -> [String: [String]] {
        var assignments: [String: [String]] = [:]
        
        let patterns = [
            // Array assignments: let icons = ["Green", "Orange", "Purple"]
            (#"let\s+(\w+):\s*\[String\]\s*=\s*\[(.*?)\]"#, true),
            // String assignments: var selectedIcon: String = "Default"
            (#"var\s+(\w+):\s*String\s*=.*?"([^"]+)""#, false),
            // Enum cases: case green = "Green"
            (#"case\s+(\w+)\s*=\s*"([^"]+)""#, false)
        ]
        
        for (pattern, isArray) in patterns {
            let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
            let matches = regex?.matches(in: content, options: [], range: NSRange(content.startIndex..., in: content)) ?? []
            
            for match in matches {
                if match.numberOfRanges >= 3,
                   let nameRange = Range(match.range(at: 1), in: content),
                   let valueRange = Range(match.range(at: 2), in: content) {
                    
                    let varName = String(content[nameRange])
                    let valueString = String(content[valueRange])
                    
                    if isArray {
                        // Parse array elements
                        let elements = extractArrayElements(from: valueString)
                        assignments[varName] = elements
                    } else {
                        assignments[varName] = [valueString]
                    }
                }
            }
        }
        
        return assignments
    }
    
    private func extractArrayElements(from arrayString: String) -> [String] {
        let pattern = #""([^"]+)""#
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        let matches = regex?.matches(in: arrayString, options: [], range: NSRange(arrayString.startIndex..., in: arrayString)) ?? []
        
        var elements: [String] = []
        for match in matches {
            if let range = Range(match.range(at: 1), in: arrayString) {
                elements.append(String(arrayString[range]))
            }
        }
        return elements
    }
    
    private func extractInterpolationPatterns(from content: String) -> [String] {
        var patterns: [String] = []
        
        let interpolationRegex = [
            #"Image\s*\(\s*"([^"]*\\\([^)]+\)[^"]*)""#,
            #"UIImage\s*\(\s*named:\s*"([^"]*\\\([^)]+\)[^"]*)""#,
            #"spriteWithFile:\s*@"([^"]*\\\([^)]+\)[^"]*)""#
        ]
        
        for pattern in interpolationRegex {
            let regex = try? NSRegularExpression(pattern: pattern, options: [])
            let matches = regex?.matches(in: content, options: [], range: NSRange(content.startIndex..., in: content)) ?? []
            
            for match in matches {
                if let range = Range(match.range(at: 1), in: content) {
                    patterns.append(String(content[range]))
                }
            }
        }
        
        return patterns
    }
    
    private func resolveInterpolationPattern(_ pattern: String, with variables: [String: [String]]) -> Set<String> {
        var resolved = Set<String>()
        
        // Extract variable name from interpolation: "Icons/\(selectedIcon)" -> "selectedIcon"
        let variablePattern = #"\\\(([^)]+)\)"#
        let regex = try? NSRegularExpression(pattern: variablePattern, options: [])
        let matches = regex?.matches(in: pattern, options: [], range: NSRange(pattern.startIndex..., in: pattern)) ?? []
        
        for match in matches {
            if let range = Range(match.range(at: 1), in: pattern) {
                let fullVariable = String(pattern[range])
                let baseVariable = fullVariable.components(separatedBy: ".").last ?? fullVariable
                
                // Try to find matching variable values
                var foundValues: [String] = []
                
                // Exact match
                if let values = variables[baseVariable] {
                    foundValues = values
                }
                
                // Partial match (for properties like userSettings.selectedIcon)
                if foundValues.isEmpty {
                    for (key, values) in variables {
                        if fullVariable.contains(key) {
                            foundValues = values
                            break
                        }
                    }
                }
                
                // Fallback to common theme values
                if foundValues.isEmpty {
                    foundValues = getCommonThemeValues(for: pattern)
                }
                
                // Resolve pattern with found values
                for value in foundValues {
                    let resolvedPattern = pattern.replacingOccurrences(of: "\\(\(fullVariable))", with: value)
                    resolved.insert(resolvedPattern)
                    
                    // Also add without extension
                    if let nameWithoutExt = resolvedPattern.components(separatedBy: ".").first, nameWithoutExt != resolvedPattern {
                        resolved.insert(nameWithoutExt)
                    }
                    
                    // CRITICAL FIX: Handle path-to-filename conversion
                    // "Icons/Green" should also match "GreenIcon"
                    if resolvedPattern.contains("/") {
                        let pathComponents = resolvedPattern.components(separatedBy: "/")
                        if let lastComponent = pathComponents.last {
                            // Add variants: "Green" → "GreenIcon", "GreenButton", etc.
                            let commonSuffixes = ["Icon", "Button", "Background", "Image"]
                            for suffix in commonSuffixes {
                                resolved.insert("\(lastComponent)\(suffix)")
                            }
                            // Also add the bare component
                            resolved.insert(lastComponent)
                        }
                    }
                    
                    // REVERSE: Handle filename-to-path conversion
                    // "GreenIcon" should also match "Icons/Green"
                    if !resolvedPattern.contains("/") {
                        let commonPrefixes = ["Icons", "Images", "Themes", "Assets"]
                        for prefix in commonPrefixes {
                            resolved.insert("\(prefix)/\(value)")
                        }
                    }
                }
            }
        }
        
        return resolved
    }
    
    private func getCommonThemeValues(for pattern: String) -> [String] {
        let patternLower = pattern.lowercased()
        
        // Theme/color patterns
        if patternLower.contains("icon") || patternLower.contains("theme") || patternLower.contains("color") {
            return ["Default", "Green", "Orange", "Purple", "Red", "Blue", "Yellow", "Silver", "Space Gray", "Dark", "Light"]
        }
        
        // Size patterns
        if patternLower.contains("size") {
            return ["Small", "Medium", "Large", "XL", "XXL"]
        }
        
        // Device patterns
        if patternLower.contains("device") {
            return ["iPhone", "iPad", "TV", "Watch", "Mac"]
        }
        
        // State patterns
        if patternLower.contains("state") {
            return ["Normal", "Active", "Selected", "Disabled", "Highlighted"]
        }
        
        return []
    }
}