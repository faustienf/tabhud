import Darwin
import Foundation

/// Who started an app, when it wasn't the user. Apps opened the usual way (Dock, Finder,
/// Spotlight, login items) are started by launchd. Anything else was started by a program: an
/// automation tool driving a browser of its own, a terminal, Xcode running a build. Such a copy
/// looks just like the user's own app on the wheel, so the wheel says whose it is.
enum AppLauncher {
    /// The name of the program that started the app; nil for the usual case.
    static func name(ofParentOf pid: pid_t) -> String? {
        guard let parent = parentPID(of: pid), parent > 1 else { return nil }
        return title(of: parent)
    }

    private static func parentPID(of pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info.kp_eproc.e_ppid
    }

    /// The name `ps` shows: the first argument. Node tools put their own name there
    /// ("chrome-devtools-mcp"), where the executable only says "node".
    private static func title(of pid: pid_t) -> String? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        if sysctl(&mib, u_int(mib.count), nil, &size, nil, 0) == 0, size > 0 {
            var bytes = [UInt8](repeating: 0, count: size)
            if sysctl(&mib, u_int(mib.count), &bytes, &size, nil, 0) == 0,
               let name = firstArgument(inProcessArguments: bytes.prefix(size)).flatMap(displayName) {
                return name
            }
        }
        var name = [UInt8](repeating: 0, count: 4 * Int(MAXCOMLEN))
        guard proc_name(pid, &name, UInt32(name.count)) > 0 else { return nil }
        return String(decoding: name.prefix { $0 != 0 }, as: UTF8.self)
    }

    /// KERN_PROCARGS2 is the argument count, the executable's path, NUL padding, then the
    /// arguments, each ending in NUL.
    static func firstArgument(inProcessArguments bytes: some Collection<UInt8>) -> String? {
        let countSize = MemoryLayout<Int32>.size
        guard bytes.count > countSize,
              Array(bytes.prefix(countSize)).withUnsafeBytes({ $0.loadUnaligned(as: Int32.self) }) > 0
        else { return nil } // no arguments: what follows is the environment
        var rest = bytes.dropFirst(countSize)
        rest = rest.drop { $0 != 0 } // the executable's path
        rest = rest.drop { $0 == 0 }
        let argument = rest.prefix { $0 != 0 }
        return argument.isEmpty ? nil : String(decoding: argument, as: UTF8.self)
    }

    /// "/bin/zsh" → "zsh"; "-zsh" (a login shell) → "zsh"; "npm exec tool" → "npm".
    static func displayName(_ argument: String) -> String? {
        // A path may have spaces ("…/Google Chrome"); a process title is a name and arguments.
        let command = argument.hasPrefix("/") ? argument : String(argument.prefix { $0 != " " })
        var name = (command as NSString).lastPathComponent
        if name.hasPrefix("-") { name.removeFirst() }
        return name.isEmpty ? nil : name
    }
}
