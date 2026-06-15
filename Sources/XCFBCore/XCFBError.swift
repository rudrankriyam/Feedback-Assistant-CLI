import Foundation

public enum XCFBError: Error, CustomStringConvertible {
    case missingValue(String)
    case invalidArgument(String)
    case missingFile(String)
    case sqlite(String)
    case processFailed(String, Int32)
    case web(String)

    public var description: String {
        switch self {
        case .missingValue(let flag):
            return "Missing value for \(flag)"
        case .invalidArgument(let message):
            return message
        case .missingFile(let path):
            return "File not found: \(path)"
        case .sqlite(let message):
            return "SQLite error: \(message)"
        case .processFailed(let command, let status):
            return "\(command) failed with exit code \(status)"
        case .web(let message):
            return "Feedback Assistant web error: \(message)"
        }
    }
}
