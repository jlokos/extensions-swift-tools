// Copyright © 2024 Raycast. All rights reserved.

import Foundation

/// Command-Line tool generating the `@main` Swift file for a Swift executable target intended to be used from a Raycast extension.
///
/// This command is customizable by using the following _short_ options.
/// - `-o /path/to/mainfile.swift` (required) specifies the full path to the file that will be generated.
/// - `-m name` (required) specifies the name of the module where this `@main` Swift fille will be added.
/// - `-t name` (required) specifies the name for the structure marked as `@main`.
@main struct SwiftCodeGenerator {
  static func main() throws {
    // 1. Extract all flags/options passed to this Command-Line tool.
    let (fileURL, moduleName, typeName) = try CommandLine.structuredArguments(flags: "-o", "-m", "-t")
    // 2. Generate the @main Swift file.
    let fileContent = mainFile(module: consume moduleName, entry: consume typeName)
    // 3. Write the Swift file to the designated path.
    try fileContent.write(to: consume fileURL, atomically: true, encoding: .utf8)
  }
}

// MARK: -

/// Generates the `@main` file for an executable target.
private func mainFile(module moduleName: String, entry entryTypeName: String) -> String {
  #"""
  import Foundation
  import RaycastSwiftMacros

  @main struct \#(entryTypeName) {
    static func main() async {
      var stderr = StandardError()

      guard CommandLine.argc > 1, let ptr = CommandLine.unsafeArgv[1] else {
        Swift.print(InsufficientArgumentsError().localizedDescription, to: &stderr)
        exit(EXIT_FAILURE)
      }

      let funcName = String(cString: ptr).drop { $0.isWhitespace }
      guard !funcName.isEmpty else {
        Swift.print(MissingFunctionError().localizedDescription, to: &stderr)
        exit(EXIT_FAILURE)
      }

      let proxyName = "\#(moduleName)._Proxy\(funcName)"
      guard let proxy = NSClassFromString(proxyName) as? _Ray.Proxy.Type else {
        Swift.print(MissingProxyError(name: proxyName).localizedDescription, to: &stderr)
        exit(EXIT_FAILURE)
      }

      let callback = _Ray.Callback()
      proxy._execute(callback)
      do {
        Swift.print(try await callback.encodedString)
      } catch let error {
        Swift.print(error, to: &stderr)
        exit(EXIT_FAILURE)
      }
    }
  }

  private extension \#(entryTypeName) {
    struct StandardError: TextOutputStream {
      func write(_ string: String) {
        FileHandle.standardError.write(Data(string.utf8))
      }
    }

    final class InsufficientArgumentsError: LocalizedError {
      let (file, function, line, column): (String, String, Int, Int)

      init(file: String = #fileID, function: String = #function, line: Int = #line, column: Int = #column) {
        (self.file, self.function, self.line, self.column) = (file, function, line, column)
      }

      var errorDescription: String? { "Not enough Command-Line arguments" }
      var failureReason: String? { "The Swift executable received less arguments than expected" }

      var helpAnchor: String? {
        let args = (0..<CommandLine.argc).compactMap { CommandLine.unsafeArgv[Int($0)] }.map { String(cString: $0) }
        return "The arguments provided are:\n\(args.joined(separator: "\n"))"
      }
    }

    final class MissingFunctionError: LocalizedError {
      let (file, function, line, column): (String, String, Int, Int)

      init(file: String = #fileID, function: String = #function, line: Int = #line, column: Int = #column) {
        (self.file, self.function, self.line, self.column) = (file, function, line, column)
      }

      var errorDescription: String? { "No function name provided" }
      var failureReason: String? { "A Swift function name is required to know which function to execute" }
      var recoverySuggestion: String? { "Pass one of the Swift function names that can be executed from TypeScript/JavaScript" }
    }

    final class MissingProxyError: LocalizedError {
      let name: String
      let (file, function, line, column): (String, String, Int, Int)

      init(name: String, file: String = #fileID, function: String = #function, line: Int = #line, column: Int = #column) {
        self.name = name
        (self.file, self.function, self.line, self.column) = (file, function, line, column)
      }

      var errorDescription: String? { "No ObjC proxy class provided" }
      var failureReason: String? { "The proxy class for the \(name) Swift function wasn't found" }
      var recoverySuggestion: String? { "Provide the matched ObjC Proxy class name for the targeted function" }
      var helpAnchor: String? { "Swift functions are exposed to TypeScript/JavaScript through ObjC classes. Every exported function requires a unique proxy ObjC class" }
    }
  }
  """#
}
