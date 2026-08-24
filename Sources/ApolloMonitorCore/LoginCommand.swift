/// What `ApolloMonitor --login [on|off|status]` was asked to do.
public enum LoginCommand: Equatable {
    case enable
    case disable
    case status
}

/// The result of looking for `--login` on a command line.
public enum LoginRequest: Equatable {
    /// No `--login` flag — run the menu-bar app as usual.
    case absent
    case command(LoginCommand)
    /// `--login` followed by something that is not `on`, `off` or `status`.
    case unrecognized(String)

    public static let flag = "--login"

    /// Usage line for the unrecognized case.
    public static let usage = "usage: ApolloMonitor --login [on|off|status]"

    public static func parse(arguments: [String]) -> LoginRequest {
        guard let flagIndex = arguments.firstIndex(of: flag) else { return .absent }

        // A bare `--login`, or one followed by another flag, only reports:
        // an incomplete command must not silently change registration.
        let valueIndex = flagIndex + 1
        guard valueIndex < arguments.count else { return .command(.status) }
        let value = arguments[valueIndex]
        guard !value.hasPrefix("--") else { return .command(.status) }

        switch value {
        case "on": return .command(.enable)
        case "off": return .command(.disable)
        case "status": return .command(.status)
        default: return .unrecognized(value)
        }
    }
}
