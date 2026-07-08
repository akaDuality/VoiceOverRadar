import Darwin
import Foundation

/// A native process running on the host Mac. Simulated iOS apps run as real
/// host processes (under `.../CoreSimulator/Devices/...`), each publishing its
/// own accessibility tree via the same AX API used for macOS apps.
public struct RunningProcess: Identifiable, Sendable, Hashable {
    public let id: pid_t
    public let name: String
    public let executablePath: String

    /// True when this process is an app running inside the iOS Simulator.
    public var isSimulatorApp: Bool {
        executablePath.contains("/CoreSimulator/Devices/")
    }
}

public enum HostProcesses {

    /// All processes on the host that we can resolve an executable path for.
    public static func all() -> [RunningProcess] {
        let maxCount = proc_listallpids(nil, 0)
        guard maxCount > 0 else { return [] }

        var pids = [pid_t](repeating: 0, count: Int(maxCount))
        let byteCount = proc_listallpids(&pids, maxCount * Int32(MemoryLayout<pid_t>.stride))
        guard byteCount > 0 else { return [] }

        let count = Int(byteCount) / MemoryLayout<pid_t>.stride
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        var result: [RunningProcess] = []

        for index in 0..<count {
            let pid = pids[index]
            guard pid > 0 else { continue }
            let length = proc_pidpath(pid, &buffer, UInt32(MAXPATHLEN))
            guard length > 0 else { continue }
            let path = String(cString: buffer)
            result.append(
                RunningProcess(id: pid, name: displayName(for: path), executablePath: path)
            )
        }
        return result
    }

    /// Simulated iOS apps only (what you usually want to inspect).
    public static func simulatorApps() -> [RunningProcess] {
        all().filter(\.isSimulatorApp).sorted { $0.name < $1.name }
    }

    /// The Simulator.app host process(es). On recent OSes the simulated app's
    /// accessibility is bridged through here rather than the app's own process.
    public static func simulatorHosts() -> [RunningProcess] {
        all().filter { $0.executablePath.hasSuffix("Simulator.app/Contents/MacOS/Simulator") }
    }

    /// For `.../MyApp.app/MyApp` returns `MyApp`; otherwise the last path component.
    private static func displayName(for path: String) -> String {
        if let range = path.range(of: ".app/") {
            return (String(path[..<range.lowerBound]) as NSString).lastPathComponent
        }
        return (path as NSString).lastPathComponent
    }
}
