import Foundation
import Testing
@testable import CmdTabWheel

/// Who started an app, read from the process table.
struct AppLauncherTests {
    /// KERN_PROCARGS2 the way the kernel lays it out: argc, executable path, NUL padding,
    /// the arguments, then the environment.
    private func processArguments(path: String, _ arguments: [String]) -> [UInt8] {
        var bytes = withUnsafeBytes(of: Int32(arguments.count)) { Array($0) }
        bytes += Array(path.utf8) + [0, 0, 0, 0]
        for argument in arguments { bytes += Array(argument.utf8) + [0] }
        bytes += Array("HOME=/somewhere".utf8) + [0]
        return bytes
    }

    @Test func theFirstArgumentIsWhatPsShows() {
        // Node tools rename themselves: the executable is node, the title their own name.
        let bytes = processArguments(path: "/opt/homebrew/bin/node", ["chrome-devtools-mcp", "--isolated"])
        #expect(AppLauncher.firstArgument(inProcessArguments: bytes) == "chrome-devtools-mcp")
    }

    @Test func nothingToReadIsNoName() {
        #expect(AppLauncher.firstArgument(inProcessArguments: []) == nil)
        #expect(AppLauncher.firstArgument(inProcessArguments: processArguments(path: "/bin/zsh", [])) == nil)
    }

    @Test func theNameIsTheProgramWithoutPathOrArguments() {
        #expect(AppLauncher.displayName("chrome-devtools-mcp") == "chrome-devtools-mcp")
        #expect(AppLauncher.displayName("/bin/zsh") == "zsh")
        #expect(AppLauncher.displayName("-zsh") == "zsh") // a login shell
        #expect(AppLauncher.displayName("npm exec chrome-devtools-mcp --isolated") == "npm")
        #expect(AppLauncher.displayName("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")
            == "Google Chrome")
        #expect(AppLauncher.displayName("") == nil)
    }

    @Test func launchdIsNobodyToMention() {
        #expect(AppLauncher.name(ofParentOf: 1) == nil)
    }

    @Test func aProcessAProgramStartedNamesIt() {
        // The tests themselves were started by the test runner, not by launchd.
        #expect(AppLauncher.name(ofParentOf: getpid()) != nil)
    }
}
