import Foundation
import Files

// Helper to provide filtered recursive iteration
struct FileIteratorHelper {
    // Directories to exclude from scanning
    static let excludedDirectories = [
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
        "SourcePackages",
        ".cocoapods",
        "vendor"
    ]
    
    static func shouldExcludeDirectory(_ path: String) -> Bool {
        for excluded in excludedDirectories {
            if path.contains("/\(excluded)/") || path.hasSuffix("/\(excluded)") {
                return true
            }
        }
        return false
    }
    
    // Get all files recursively, excluding certain directories
    static func recursiveFiles(in folder: Folder) -> [File] {
        var files: [File] = []
        recursivelyCollectFiles(in: folder, into: &files)
        return files
    }
    
    private static func recursivelyCollectFiles(in folder: Folder, into files: inout [File]) {
        // Add files from current folder
        for file in folder.files {
            files.append(file)
        }
        
        // Recursively process subfolders, skipping excluded ones
        for subfolder in folder.subfolders {
            if excludedDirectories.contains(subfolder.name) {
                continue
            }
            recursivelyCollectFiles(in: subfolder, into: &files)
        }
    }
    
    // Get all subfolders recursively, excluding certain directories
    static func recursiveSubfolders(in folder: Folder) -> [Folder] {
        var folders: [Folder] = []
        recursivelyCollectFolders(in: folder, into: &folders)
        return folders
    }
    
    private static func recursivelyCollectFolders(in folder: Folder, into folders: inout [Folder]) {
        // Process subfolders, skipping excluded ones
        for subfolder in folder.subfolders {
            if excludedDirectories.contains(subfolder.name) {
                continue
            }
            folders.append(subfolder)
            recursivelyCollectFolders(in: subfolder, into: &folders)
        }
    }
}

// Extension to make it easier to use
extension Folder {
    var filteredRecursiveFiles: [File] {
        return FileIteratorHelper.recursiveFiles(in: self)
    }
    
    var filteredRecursiveSubfolders: [Folder] {
        return FileIteratorHelper.recursiveSubfolders(in: self)
    }
}