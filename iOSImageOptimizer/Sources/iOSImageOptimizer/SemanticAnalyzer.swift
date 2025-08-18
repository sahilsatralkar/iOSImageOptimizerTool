import Foundation
import Files

struct VariableAssignment {
    let name: String
    let value: String
    let type: AssignmentType
    
    enum AssignmentType {
        case constant, arrayLiteral, enumCase
    }
}

struct StringInterpolation {
    let pattern: String
    let variable: String
    let prefix: String
    let suffix: String
}

class SemanticAnalyzer {
    private let projectPath: String
    private let verbose: Bool
    
    init(projectPath: String, verbose: Bool = false) {
        self.projectPath = projectPath
        self.verbose = verbose
    }
    
    func analyzeImageReferences() throws -> Set<String> {
        var imageReferences = Set<String>()
        
        let folder = try Folder(path: projectPath)
        
        // Step 1: Find all variable assignments
        let variables = try findVariableAssignments(in: folder)
        
        // Step 2: Find string interpolation patterns
        let interpolations = try findStringInterpolations(in: folder)
        
        // Step 3: Resolve interpolations with variable values
        for interpolation in interpolations {
            let resolvedImages = resolveInterpolation(interpolation, with: variables)
            imageReferences.formUnion(resolvedImages)
        }
        
        return imageReferences
    }
    
    private func findVariableAssignments(in folder: Folder) throws -> [VariableAssignment] {
        var assignments: [VariableAssignment] = []
        
        for file in folder.filteredRecursiveFiles where file.extension == "swift" {
            do {
                let content = try file.readAsString()
                assignments.append(contentsOf: parseVariableAssignments(in: content))
            } catch {
                continue
            }
        }
        
        return assignments
    }
    
    private func parseVariableAssignments(in content: String) -> [VariableAssignment] {
        var assignments: [VariableAssignment] = []
        
        let patterns = [
            // Array literals: let icons = ["Green", "Orange", "Purple"]
            #"let\s+(\w+):\s*\[String\]\s*=\s*\[(.*?)\]"#,
            // String constants: let selectedIcon = "Green"
            #"let\s+(\w+):\s*String\s*=\s*"([^"]+)""#,
            // Enum cases: case green = "Green"
            #"case\s+(\w+)\s*=\s*"([^"]+)""#,
            // Published properties with default: var selectedIcon: String = "Default"
            #"var\s+(\w+):\s*String\s*=.*?"([^"]+)""#
        ]
        
        for (index, pattern) in patterns.enumerated() {
            let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
            let matches = regex?.matches(in: content, options: [], range: NSRange(content.startIndex..., in: content)) ?? []
            
            for match in matches {
                if match.numberOfRanges >= 3,
                   let nameRange = Range(match.range(at: 1), in: content),
                   let valueRange = Range(match.range(at: 2), in: content) {
                    
                    let name = String(content[nameRange])
                    let value = String(content[valueRange])
                    
                    let type: VariableAssignment.AssignmentType = index == 0 ? .arrayLiteral : 
                                                                  index == 2 ? .enumCase : .constant
                    
                    if type == .arrayLiteral {
                        // Parse array elements
                        let elements = parseArrayElements(value)
                        for element in elements {
                            assignments.append(VariableAssignment(name: name, value: element, type: type))
                        }
                    } else {
                        assignments.append(VariableAssignment(name: name, value: value, type: type))
                    }
                }
            }
        }
        
        return assignments
    }
    
    private func parseArrayElements(_ arrayContent: String) -> [String] {
        let pattern = #""([^"]+)""#
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        let matches = regex?.matches(in: arrayContent, options: [], range: NSRange(arrayContent.startIndex..., in: arrayContent)) ?? []
        
        var elements: [String] = []
        for match in matches {
            if let range = Range(match.range(at: 1), in: arrayContent) {
                elements.append(String(arrayContent[range]))
            }
        }
        return elements
    }
    
    private func findStringInterpolations(in folder: Folder) throws -> [StringInterpolation] {
        var interpolations: [StringInterpolation] = []
        
        for file in folder.filteredRecursiveFiles where file.extension == "swift" {
            do {
                let content = try file.readAsString()
                interpolations.append(contentsOf: parseStringInterpolations(in: content))
            } catch {
                continue
            }
        }
        
        return interpolations
    }
    
    private func parseStringInterpolations(in content: String) -> [StringInterpolation] {
        var interpolations: [StringInterpolation] = []
        
        let patterns = [
            // Image("path/\(variable)")
            #"Image\s*\(\s*"([^"]*)\\\(([^)]+)\)([^"]*)""#,
            // UIImage(named: "path/\(variable)")
            #"UIImage\s*\(\s*named:\s*"([^"]*)\\\(([^)]+)\)([^"]*)""#,
            // spriteWithFile:@"path/\(variable)" (Cocos2D)
            #"spriteWithFile:\s*@"([^"]*)\\\(([^)]+)\)([^"]*)""#
        ]
        
        for pattern in patterns {
            let regex = try? NSRegularExpression(pattern: pattern, options: [])
            let matches = regex?.matches(in: content, options: [], range: NSRange(content.startIndex..., in: content)) ?? []
            
            for match in matches {
                if match.numberOfRanges >= 4,
                   let prefixRange = Range(match.range(at: 1), in: content),
                   let variableRange = Range(match.range(at: 2), in: content),
                   let suffixRange = Range(match.range(at: 3), in: content) {
                    
                    let prefix = String(content[prefixRange])
                    let variable = String(content[variableRange]).trimmingCharacters(in: .whitespaces)
                    let suffix = String(content[suffixRange])
                    let fullPattern = prefix + "\\(\(variable))" + suffix
                    
                    interpolations.append(StringInterpolation(
                        pattern: fullPattern,
                        variable: variable,
                        prefix: prefix,
                        suffix: suffix
                    ))
                }
            }
        }
        
        return interpolations
    }
    
    private func resolveInterpolation(_ interpolation: StringInterpolation, with variables: [VariableAssignment]) -> Set<String> {
        var resolvedImages = Set<String>()
        
        // Extract base variable name (handle dot notation)
        let baseVariable = interpolation.variable.components(separatedBy: ".").first ?? interpolation.variable
        
        // Find matching variable assignments
        let matchingVariables = variables.filter { $0.name == baseVariable }
        
        for variable in matchingVariables {
            let resolvedPath = interpolation.prefix + variable.value + interpolation.suffix
            resolvedImages.insert(resolvedPath)
            
            // Also add without extension
            if let nameWithoutExt = resolvedPath.components(separatedBy: ".").first, nameWithoutExt != resolvedPath {
                resolvedImages.insert(nameWithoutExt)
            }
        }
        
        // If no exact match found, try to infer from common patterns
        if matchingVariables.isEmpty {
            resolvedImages.formUnion(inferFromCommonPatterns(interpolation, variables: variables))
        }
        
        return resolvedImages
    }
    
    private func inferFromCommonPatterns(_ interpolation: StringInterpolation, variables: [VariableAssignment]) -> Set<String> {
        var inferred = Set<String>()
        
        // Common color names for theming
        let commonThemeValues = ["Default", "Green", "Orange", "Purple", "Red", "Blue", "Yellow", "Silver", "Space Gray"]
        
        // If the interpolation looks like a theme/color system
        if interpolation.prefix.lowercased().contains("icon") || 
           interpolation.prefix.lowercased().contains("theme") ||
           interpolation.variable.lowercased().contains("color") ||
           interpolation.variable.lowercased().contains("theme") {
            
            for themeValue in commonThemeValues {
                let resolvedPath = interpolation.prefix + themeValue + interpolation.suffix
                inferred.insert(resolvedPath)
                
                if let nameWithoutExt = resolvedPath.components(separatedBy: ".").first, nameWithoutExt != resolvedPath {
                    inferred.insert(nameWithoutExt)
                }
            }
        }
        
        return inferred
    }
}