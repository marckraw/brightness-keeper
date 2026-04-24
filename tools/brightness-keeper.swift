#!/usr/bin/env swift

import CoreGraphics
import Darwin
import Foundation
import IOKit
import IOKit.graphics

struct Config {
    var level: Float = 1.0
    var interval: TimeInterval?
    var quiet = false
    var useDDCCTL = false
    var ddcctlOnly = false
    var ddcctlDisplays: [Int] = []
    var useM1DDC = false
    var m1ddcOnly = false
    var m1ddcDisplays: [Int] = []
    var useBrightnessCLI = false
    var brightnessCLIOnly = false
    var brightnessDisplays: [Int] = []
    var useDisplayServices = false
    var displayServicesOnly = false
    var useLunar = false
    var lunarOnly = false
    var lunarDisplay = "Built-in"
    var diagnose = false
}

enum BrightnessKeeperError: Error, CustomStringConvertible {
    case invalidValue(String)
    case unknownArgument(String)
    case removedFallbackKeys
    case invalidDDCCTLDisplay(String)
    case ddcctlUnavailable
    case ddcctlNoDisplays
    case ddcctlFailed([Int], String)
    case m1ddcUnavailable
    case m1ddcFailed([Int], String)
    case brightnessCLIUnavailable
    case brightnessCLIFailed(String)
    case displayServicesUnavailable
    case displayServicesNoBuiltInDisplay
    case displayServicesFailed([CGDirectDisplayID])
    case lunarUnavailable
    case lunarFailed(String)
    case noDisplaysControlled

    var description: String {
        switch self {
        case .invalidValue(let value):
            return "Invalid brightness value: \(value). Use 0.0-1.0 or 0-100."
        case .unknownArgument(let argument):
            return "Unknown argument: \(argument). Run with --help for usage."
        case .removedFallbackKeys:
            return "--fallback-keys was removed because synthetic brightness-key events can behave unpredictably. Use --ddcctl or --ddcctl-only for DDC/CI monitors."
        case .invalidDDCCTLDisplay(let value):
            return "Invalid ddcctl display index: \(value). Use a positive integer, or a comma-separated list such as 1,2."
        case .ddcctlUnavailable:
            return "ddcctl was requested but was not found. Install it with Homebrew or MacPorts, then retry."
        case .ddcctlNoDisplays:
            return "ddcctl was requested but no display indexes could be detected. Run `ddcctl` directly to inspect available displays."
        case .ddcctlFailed(let displayIndexes, let output):
            let displays = displayIndexes.map(String.init).joined(separator: ",")
            let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedOutput.isEmpty {
                return "ddcctl failed for display index(es) \(displays), but produced no output. Try `ddcctl -d \(displayIndexes.first ?? 1) -b ?` directly."
            }
            return "ddcctl failed for display index(es) \(displays). Last ddcctl output:\n\(trimmedOutput)"
        case .m1ddcUnavailable:
            return "m1ddc was requested but was not found. Install it, then retry."
        case .m1ddcFailed(let displayIndexes, let output):
            let displays = displayIndexes.isEmpty ? "default" : displayIndexes.map(String.init).joined(separator: ",")
            let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedOutput.isEmpty {
                return "m1ddc failed for display index(es) \(displays), but produced no output. Try `m1ddc display list` directly."
            }
            return "m1ddc failed for display index(es) \(displays). Last m1ddc output:\n\(trimmedOutput)"
        case .brightnessCLIUnavailable:
            return "brightness CLI was requested but was not found. Install it with `brew install brightness`, then retry."
        case .brightnessCLIFailed(let output):
            let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedOutput.isEmpty {
                return "brightness CLI failed, but produced no output. Try `brightness -l` directly."
            }
            return "brightness CLI failed. Last brightness output:\n\(trimmedOutput)"
        case .displayServicesUnavailable:
            return "DisplayServices brightness API was requested but is not available on this macOS install."
        case .displayServicesNoBuiltInDisplay:
            return "DisplayServices brightness API was requested but no active built-in display was found."
        case .displayServicesFailed(let displayIDs):
            return "DisplayServices failed for built-in display ID(s): \(displayIDs.map { String($0) }.joined(separator: ", "))."
        case .lunarUnavailable:
            return "Lunar CLI was requested but was not found. Install Lunar, run `/Applications/Lunar.app/Contents/MacOS/Lunar install-cli`, then retry."
        case .lunarFailed(let output):
            let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedOutput.isEmpty {
                return "Lunar CLI failed, but produced no output. Try `lunar displays` directly."
            }
            return "Lunar CLI failed. Last Lunar output:\n\(trimmedOutput)"
        case .noDisplaysControlled:
            return "macOS did not accept brightness control for any display. For the built-in display, try --lunar. For external DDC/CI monitors, try --m1ddc."
        }
    }
}

struct BrightnessResult {
    let iokitServices: Int
    let coreDisplayDisplays: Int
    let ddcctlDisplays: Int
    let m1ddcDisplays: Int
    let brightnessCLIDisplays: Int
    let displayServicesDisplays: Int
    let lunarDisplays: Int

    var total: Int {
        iokitServices + coreDisplayDisplays + ddcctlDisplays + m1ddcDisplays + brightnessCLIDisplays + displayServicesDisplays + lunarDisplays
    }
}

func usage() {
    print("""
    brightness-keeper

    Force display brightness to a target level using macOS display services.

    Usage:
      tools/brightness-keeper [--level 100] [--interval 3600] [--quiet]
      tools/brightness-keeper --once --level 100

    Options:
      --level, -l       Target brightness. Accepts 0.0-1.0 or 0-100. Default: 100.
      --interval, -i    Re-apply brightness every N seconds. If omitted, runs once.
      --once            Run once, even if --interval is present earlier.
      --ddcctl          Also set brightness with ddcctl DDC/CI control.
      --ddcctl-only     Only use ddcctl DDC/CI control.
      --ddcctl-display  ddcctl display index, repeatable or comma-separated. Default: detected displays.
      --m1ddc           Also set brightness with m1ddc DDC/CI control.
      --m1ddc-only      Only use m1ddc DDC/CI control.
      --m1ddc-display   m1ddc display index, repeatable or comma-separated. Default: m1ddc default.
      --brightness-cli  Also set brightness with the Homebrew brightness CLI.
      --brightness-only Only use the Homebrew brightness CLI.
      --brightness-display
                        brightness CLI display index, repeatable or comma-separated. Default: detected built-in display.
      --display-services
                        Also set built-in brightness with local DisplayServices API.
      --display-services-only
                        Only use local DisplayServices API.
      --lunar           Also set built-in display brightness with Lunar CLI.
      --lunar-only      Only use Lunar CLI.
      --lunar-display   Lunar display selector. Default: Built-in.
      --diagnose        Print display/control diagnostics and exit.
      --quiet, -q       Only print errors.
      --help, -h        Show this help.

    Examples:
      tools/brightness-keeper --level 100 --display-services --m1ddc --m1ddc-display 1
      tools/brightness-keeper --level 85 --interval 3600 --display-services --m1ddc --m1ddc-display 1
    """)
}

func parseLevel(_ raw: String) throws -> Float {
    guard let parsed = Float(raw) else {
        throw BrightnessKeeperError.invalidValue(raw)
    }

    let normalized = parsed > 1.0 ? parsed / 100.0 : parsed
    guard normalized >= 0.0 && normalized <= 1.0 else {
        throw BrightnessKeeperError.invalidValue(raw)
    }

    return normalized
}

func parseDDCCTLDisplays(_ raw: String) throws -> [Int] {
    let parts = raw.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
    guard !parts.isEmpty else {
        throw BrightnessKeeperError.invalidDDCCTLDisplay(raw)
    }

    return try parts.map { part in
        guard let index = Int(part), index > 0 else {
            throw BrightnessKeeperError.invalidDDCCTLDisplay(part)
        }
        return index
    }
}

func parseM1DDCDisplays(_ raw: String) throws -> [Int] {
    try parseDDCCTLDisplays(raw)
}

func parseBrightnessDisplays(_ raw: String) throws -> [Int] {
    let parts = raw.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
    guard !parts.isEmpty else {
        throw BrightnessKeeperError.invalidDDCCTLDisplay(raw)
    }

    return try parts.map { part in
        guard let index = Int(part), index >= 0 else {
            throw BrightnessKeeperError.invalidDDCCTLDisplay(part)
        }
        return index
    }
}

func parseConfig(arguments: [String]) throws -> Config {
    var config = Config()
    var index = 0

    while index < arguments.count {
        let argument = arguments[index]

        switch argument {
        case "--help", "-h":
            usage()
            exit(0)
        case "--quiet", "-q":
            config.quiet = true
        case "--fallback-keys":
            throw BrightnessKeeperError.removedFallbackKeys
        case "--ddcctl":
            config.useDDCCTL = true
        case "--ddcctl-only":
            config.useDDCCTL = true
            config.ddcctlOnly = true
        case "--m1ddc":
            config.useM1DDC = true
        case "--m1ddc-only":
            config.useM1DDC = true
            config.m1ddcOnly = true
        case "--brightness-cli":
            config.useBrightnessCLI = true
        case "--brightness-only":
            config.useBrightnessCLI = true
            config.brightnessCLIOnly = true
        case "--display-services":
            config.useDisplayServices = true
        case "--display-services-only":
            config.useDisplayServices = true
            config.displayServicesOnly = true
        case "--lunar":
            config.useLunar = true
        case "--lunar-only":
            config.useLunar = true
            config.lunarOnly = true
        case "--brightness-display":
            index += 1
            guard index < arguments.count else {
                throw BrightnessKeeperError.invalidDDCCTLDisplay("")
            }
            config.useBrightnessCLI = true
            config.brightnessDisplays.append(contentsOf: try parseBrightnessDisplays(arguments[index]))
        case "--lunar-display":
            index += 1
            guard index < arguments.count else {
                throw BrightnessKeeperError.invalidValue("")
            }
            config.useLunar = true
            config.lunarDisplay = arguments[index]
        case "--diagnose":
            config.diagnose = true
        case "--once":
            config.interval = nil
        case "--ddcctl-display":
            index += 1
            guard index < arguments.count else {
                throw BrightnessKeeperError.invalidDDCCTLDisplay("")
            }
            config.useDDCCTL = true
            config.ddcctlDisplays.append(contentsOf: try parseDDCCTLDisplays(arguments[index]))
        case "--m1ddc-display":
            index += 1
            guard index < arguments.count else {
                throw BrightnessKeeperError.invalidDDCCTLDisplay("")
            }
            config.useM1DDC = true
            config.m1ddcDisplays.append(contentsOf: try parseM1DDCDisplays(arguments[index]))
        case "--level", "-l":
            index += 1
            guard index < arguments.count else {
                throw BrightnessKeeperError.invalidValue("")
            }
            config.level = try parseLevel(arguments[index])
        case "--interval", "-i":
            index += 1
            guard index < arguments.count, let interval = TimeInterval(arguments[index]), interval > 0 else {
                throw BrightnessKeeperError.invalidValue(index < arguments.count ? arguments[index] : "")
            }
            config.interval = interval
        default:
            if argument.hasPrefix("--level=") {
                config.level = try parseLevel(String(argument.dropFirst("--level=".count)))
            } else if argument.hasPrefix("--interval=") {
                let raw = String(argument.dropFirst("--interval=".count))
                guard let interval = TimeInterval(raw), interval > 0 else {
                    throw BrightnessKeeperError.invalidValue(raw)
                }
                config.interval = interval
            } else if argument.hasPrefix("--ddcctl-display=") {
                config.useDDCCTL = true
                config.ddcctlDisplays.append(contentsOf: try parseDDCCTLDisplays(String(argument.dropFirst("--ddcctl-display=".count))))
            } else if argument.hasPrefix("--m1ddc-display=") {
                config.useM1DDC = true
                config.m1ddcDisplays.append(contentsOf: try parseM1DDCDisplays(String(argument.dropFirst("--m1ddc-display=".count))))
            } else if argument.hasPrefix("--brightness-display=") {
                config.useBrightnessCLI = true
                config.brightnessDisplays.append(contentsOf: try parseBrightnessDisplays(String(argument.dropFirst("--brightness-display=".count))))
            } else if argument.hasPrefix("--lunar-display=") {
                config.useLunar = true
                config.lunarDisplay = String(argument.dropFirst("--lunar-display=".count))
            } else {
                throw BrightnessKeeperError.unknownArgument(argument)
            }
        }

        index += 1
    }

    return config
}

func displayServices() -> [io_service_t] {
    var iterator: io_iterator_t = 0
    let result = IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IODisplayConnect"), &iterator)

    guard result == KERN_SUCCESS else {
        return []
    }

    defer {
        IOObjectRelease(iterator)
    }

    var services: [io_service_t] = []
    while true {
        let service = IOIteratorNext(iterator)
        if service == 0 {
            break
        }
        services.append(service)
    }

    return services
}

func activeDisplays() -> [CGDirectDisplayID] {
    var count: UInt32 = 0
    CGGetActiveDisplayList(0, nil, &count)

    guard count > 0 else {
        return []
    }

    var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
    CGGetActiveDisplayList(count, &displays, &count)
    return Array(displays.prefix(Int(count)))
}

func activeDisplayCount() -> Int {
    activeDisplays().count
}

func setBrightnessWithIOKit(_ level: Float) -> Int {
    let services = displayServices()
    var successCount = 0

    for service in services {
        defer {
            IOObjectRelease(service)
        }

        let result = IODisplaySetFloatParameter(
            service,
            IOOptionBits(0),
            kIODisplayBrightnessKey as CFString,
            level
        )

        if result == KERN_SUCCESS {
            successCount += 1
        }
    }

    return successCount
}

func setBrightnessWithCoreDisplay(_ level: Float) -> Int {
    typealias SetUserBrightness = @convention(c) (CGDirectDisplayID, Double) -> Void

    guard let handle = dlopen("/System/Library/PrivateFrameworks/CoreDisplay.framework/CoreDisplay", RTLD_LAZY) else {
        return 0
    }

    defer {
        dlclose(handle)
    }

    guard let symbol = dlsym(handle, "CoreDisplay_Display_SetUserBrightness") else {
        return 0
    }

    let setUserBrightness = unsafeBitCast(symbol, to: SetUserBrightness.self)
    let displays = activeDisplays()

    for display in displays {
        setUserBrightness(display, Double(level))
    }

    return displays.count
}

func setBuiltInBrightnessWithDisplayServices(_ level: Float) throws -> Int {
    typealias SetBrightness = @convention(c) (CGDirectDisplayID, Float) -> Int32

    guard let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY) else {
        throw BrightnessKeeperError.displayServicesUnavailable
    }

    defer {
        dlclose(handle)
    }

    guard let symbol = dlsym(handle, "DisplayServicesSetBrightness") else {
        throw BrightnessKeeperError.displayServicesUnavailable
    }

    let setBrightness = unsafeBitCast(symbol, to: SetBrightness.self)
    let builtInDisplays = activeDisplays().filter { CGDisplayIsBuiltin($0) != 0 }

    guard !builtInDisplays.isEmpty else {
        throw BrightnessKeeperError.displayServicesNoBuiltInDisplay
    }

    var successCount = 0
    var failedDisplays: [CGDirectDisplayID] = []

    for display in builtInDisplays {
        let result = setBrightness(display, level)
        if result == 0 {
            successCount += 1
        } else {
            failedDisplays.append(display)
        }
    }

    if successCount == 0 {
        throw BrightnessKeeperError.displayServicesFailed(failedDisplays)
    }

    return successCount
}

func displayServicesSetBrightnessAvailable() -> Bool {
    guard let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY) else {
        return false
    }

    defer {
        dlclose(handle)
    }

    return dlsym(handle, "DisplayServicesSetBrightness") != nil
}

func coreDisplaySetUserBrightnessAvailable() -> Bool {
    guard let handle = dlopen("/System/Library/PrivateFrameworks/CoreDisplay.framework/CoreDisplay", RTLD_LAZY) else {
        return false
    }

    defer {
        dlclose(handle)
    }

    return dlsym(handle, "CoreDisplay_Display_SetUserBrightness") != nil
}

struct CommandResult {
    let status: Int32
    let output: String
}

func runCommand(_ executablePath: String, arguments: [String]) -> CommandResult? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executablePath)
    process.arguments = arguments

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe

    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        return nil
    }

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return CommandResult(
        status: process.terminationStatus,
        output: String(data: data, encoding: .utf8) ?? ""
    )
}

func executablePath(named executableName: String) -> String? {
    let defaultPath = "/opt/homebrew/bin:/usr/local/bin:/opt/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    let environmentPath = ProcessInfo.processInfo.environment["PATH"] ?? defaultPath
    let searchPath = (environmentPath + ":" + defaultPath).split(separator: ":").map(String.init)

    for directory in searchPath {
        let path = (directory as NSString).appendingPathComponent(executableName)
        if FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
    }

    return nil
}

func lunarExecutablePath() -> String? {
    if let path = executablePath(named: "lunar") {
        return path
    }

    let appPath = "/Applications/Lunar.app/Contents/MacOS/Lunar"
    if FileManager.default.isExecutableFile(atPath: appPath) {
        return appPath
    }

    return nil
}

func detectedDDCCTLDisplayIndexes(ddcctlPath: String) -> [Int] {
    guard let result = runCommand(ddcctlPath, arguments: []) else {
        return []
    }

    let lines = result.output.split(separator: "\n").map(String.init)
    for line in lines where line.contains("found") && line.contains("display") {
        let parts = line.split { !$0.isNumber }
        if let rawCount = parts.first, let count = Int(rawCount), count > 0 {
            return Array(1...count)
        }
    }

    let detectedCount = lines.filter { line in
        line.contains("NSScreen #") || line.contains("CGDisplay ")
    }.count

    guard detectedCount > 0 else {
        return []
    }

    return Array(1...detectedCount)
}

func setBrightnessWithDDCCTL(_ level: Float, displayIndexes requestedDisplayIndexes: [Int]) throws -> Int {
    guard let ddcctlPath = executablePath(named: "ddcctl") else {
        throw BrightnessKeeperError.ddcctlUnavailable
    }

    let displayIndexes = requestedDisplayIndexes.isEmpty
        ? detectedDDCCTLDisplayIndexes(ddcctlPath: ddcctlPath)
        : requestedDisplayIndexes

    guard !displayIndexes.isEmpty else {
        throw BrightnessKeeperError.ddcctlNoDisplays
    }

    let brightness = String(Int(round(level * 100)))
    var successCount = 0
    var failures: [String] = []

    for displayIndex in displayIndexes {
        let arguments = ["-d", String(displayIndex), "-b", brightness]
        guard let result = runCommand(ddcctlPath, arguments: arguments) else {
            failures.append("$ ddcctl \(arguments.joined(separator: " "))\nfailed to launch ddcctl")
            continue
        }

        if result.status == 0 {
            successCount += 1
        } else {
            failures.append("$ ddcctl \(arguments.joined(separator: " "))\n\(result.output)")
        }
    }

    if successCount == 0 {
        throw BrightnessKeeperError.ddcctlFailed(displayIndexes, failures.joined(separator: "\n"))
    }

    return successCount
}

func setBrightnessWithM1DDC(_ level: Float, displayIndexes: [Int]) throws -> Int {
    guard let m1ddcPath = executablePath(named: "m1ddc") else {
        throw BrightnessKeeperError.m1ddcUnavailable
    }

    let brightness = String(Int(round(level * 100)))
    var successCount = 0
    var failures: [String] = []

    if displayIndexes.isEmpty {
        let arguments = ["set", "luminance", brightness]
        guard let result = runCommand(m1ddcPath, arguments: arguments) else {
            throw BrightnessKeeperError.m1ddcFailed([], "$ m1ddc \(arguments.joined(separator: " "))\nfailed to launch m1ddc")
        }

        if result.status == 0 {
            return 1
        }

        throw BrightnessKeeperError.m1ddcFailed([], "$ m1ddc \(arguments.joined(separator: " "))\n\(result.output)")
    }

    for displayIndex in displayIndexes {
        let arguments = ["display", String(displayIndex), "set", "luminance", brightness]
        guard let result = runCommand(m1ddcPath, arguments: arguments) else {
            failures.append("$ m1ddc \(arguments.joined(separator: " "))\nfailed to launch m1ddc")
            continue
        }

        if result.status == 0 {
            successCount += 1
        } else {
            failures.append("$ m1ddc \(arguments.joined(separator: " "))\n\(result.output)")
        }
    }

    if successCount == 0 {
        throw BrightnessKeeperError.m1ddcFailed(displayIndexes, failures.joined(separator: "\n"))
    }

    return successCount
}

func detectedBuiltInBrightnessDisplayIndexes(brightnessPath: String) -> [Int] {
    guard let result = runCommand(brightnessPath, arguments: ["-l"]), result.status == 0 else {
        return []
    }

    return result.output
        .split(separator: "\n")
        .compactMap { line -> Int? in
            guard line.contains("built-in") else {
                return nil
            }

            let pattern = #"display\s+([0-9]+):"#
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: String(line), range: NSRange(line.startIndex..., in: line)),
                  let range = Range(match.range(at: 1), in: line) else {
                return nil
            }

            return Int(line[range])
        }
}

func brightnessCLIReportsFailedBrightness(_ output: String, displayIndex: Int) -> Bool {
    let lines = output.split(separator: "\n").map(String.init)
    let displayPrefix = "display \(displayIndex):"

    for (index, line) in lines.enumerated() where line.hasPrefix(displayPrefix) {
        guard line.contains("built-in") else {
            continue
        }

        let nextIndex = index + 1
        guard nextIndex < lines.count else {
            return false
        }

        return lines[nextIndex].contains("failed to get brightness")
    }

    return false
}

func setBrightnessWithBrightnessCLI(_ level: Float, displayIndexes requestedDisplayIndexes: [Int]) throws -> Int {
    guard let brightnessPath = executablePath(named: "brightness") else {
        throw BrightnessKeeperError.brightnessCLIUnavailable
    }

    let brightness = String(format: "%.4f", Double(level))
    let displayListResult = runCommand(brightnessPath, arguments: ["-l"])
    let displayIndexes = requestedDisplayIndexes.isEmpty
        ? detectedBuiltInBrightnessDisplayIndexes(brightnessPath: brightnessPath)
        : requestedDisplayIndexes

    if let displayListResult, displayListResult.status == 0 {
        let unsupportedIndexes = displayIndexes.filter {
            brightnessCLIReportsFailedBrightness(displayListResult.output, displayIndex: $0)
        }

        if !unsupportedIndexes.isEmpty {
            throw BrightnessKeeperError.brightnessCLIFailed("""
            brightness -l reports that it cannot read brightness for built-in display index(es) \(unsupportedIndexes.map(String.init).joined(separator: ",")).
            \(displayListResult.output)
            """)
        }
    }

    let argumentSets = displayIndexes.isEmpty
        ? [[brightness]]
        : displayIndexes.map { ["-d", String($0), brightness] }
    var successCount = 0
    var failures: [String] = []

    for arguments in argumentSets {
        guard let result = runCommand(brightnessPath, arguments: arguments) else {
            failures.append("$ brightness \(arguments.joined(separator: " "))\nfailed to launch brightness")
            continue
        }

        if result.status == 0 {
            successCount += 1
        } else {
            failures.append("$ brightness \(arguments.joined(separator: " "))\n\(result.output)")
        }
    }

    if successCount == 0 {
        throw BrightnessKeeperError.brightnessCLIFailed(failures.joined(separator: "\n"))
    }

    return successCount
}

func setBrightnessWithLunar(_ level: Float, display: String) throws -> Int {
    guard let lunarPath = lunarExecutablePath() else {
        throw BrightnessKeeperError.lunarUnavailable
    }

    let brightness = String(Int(round(level * 100)))
    let arguments = ["displays", display, "brightness", brightness]

    guard let result = runCommand(lunarPath, arguments: arguments) else {
        throw BrightnessKeeperError.lunarFailed("$ lunar \(arguments.joined(separator: " "))\nfailed to launch Lunar CLI")
    }

    guard result.status == 0 else {
        throw BrightnessKeeperError.lunarFailed("$ lunar \(arguments.joined(separator: " "))\n\(result.output)")
    }

    return 1
}

@discardableResult
func setBrightness(_ config: Config) throws -> BrightnessResult {
    let helperBackendOnly = config.ddcctlOnly || config.m1ddcOnly || config.brightnessCLIOnly || config.displayServicesOnly || config.lunarOnly
    let iokitServices = helperBackendOnly ? 0 : setBrightnessWithIOKit(config.level)
    let coreDisplayDisplays = helperBackendOnly ? 0 : setBrightnessWithCoreDisplay(config.level)
    let ddcctlDisplays = config.useDDCCTL
        ? try setBrightnessWithDDCCTL(config.level, displayIndexes: config.ddcctlDisplays)
        : 0
    let m1ddcDisplays = config.useM1DDC
        ? try setBrightnessWithM1DDC(config.level, displayIndexes: config.m1ddcDisplays)
        : 0
    let brightnessCLIDisplays = config.useBrightnessCLI
        ? try setBrightnessWithBrightnessCLI(config.level, displayIndexes: config.brightnessDisplays)
        : 0
    let displayServicesDisplays = config.useDisplayServices
        ? try setBuiltInBrightnessWithDisplayServices(config.level)
        : 0
    let lunarDisplays = config.useLunar
        ? try setBrightnessWithLunar(config.level, display: config.lunarDisplay)
        : 0

    let result = BrightnessResult(
        iokitServices: iokitServices,
        coreDisplayDisplays: coreDisplayDisplays,
        ddcctlDisplays: ddcctlDisplays,
        m1ddcDisplays: m1ddcDisplays,
        brightnessCLIDisplays: brightnessCLIDisplays,
        displayServicesDisplays: displayServicesDisplays,
        lunarDisplays: lunarDisplays
    )

    if result.total == 0 {
        throw BrightnessKeeperError.noDisplaysControlled
    }

    return result
}

func percentString(_ level: Float) -> String {
    "\(Int(round(level * 100)))%"
}

do {
    let config = try parseConfig(arguments: Array(CommandLine.arguments.dropFirst()))

    if config.diagnose {
        let services = displayServices()
        print("Active displays: \(activeDisplayCount())")
        print("IODisplayConnect services: \(services.count)")
        for service in services {
            IOObjectRelease(service)
        }
        print("CoreDisplay SetUserBrightness available: \(coreDisplaySetUserBrightnessAvailable())")
        print("DisplayServices SetBrightness available: \(displayServicesSetBrightnessAvailable())")
        if let ddcctlPath = executablePath(named: "ddcctl") {
            let displayIndexes = detectedDDCCTLDisplayIndexes(ddcctlPath: ddcctlPath)
            print("ddcctl path: \(ddcctlPath)")
            print("ddcctl detected displays: \(displayIndexes.map(String.init).joined(separator: ", "))")
        } else {
            print("ddcctl path: not found")
        }
        if let m1ddcPath = executablePath(named: "m1ddc") {
            print("m1ddc path: \(m1ddcPath)")
            if let result = runCommand(m1ddcPath, arguments: ["display", "list"]) {
                print("m1ddc display list:")
                print(result.output.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        } else {
            print("m1ddc path: not found")
        }
        if let brightnessPath = executablePath(named: "brightness") {
            print("brightness CLI path: \(brightnessPath)")
            if let result = runCommand(brightnessPath, arguments: ["-l"]) {
                print("brightness CLI display list:")
                print(result.output.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            let builtInDisplayIndexes = detectedBuiltInBrightnessDisplayIndexes(brightnessPath: brightnessPath)
            print("brightness CLI detected built-in displays: \(builtInDisplayIndexes.map(String.init).joined(separator: ", "))")
        } else {
            print("brightness CLI path: not found")
        }
        if let lunarPath = lunarExecutablePath() {
            print("Lunar CLI path: \(lunarPath)")
            if let result = runCommand(lunarPath, arguments: ["displays"]) {
                print("Lunar displays:")
                print(result.output.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        } else {
            print("Lunar CLI path: not found")
        }
        exit(0)
    }

    @discardableResult
    func apply() -> Bool {
        do {
            let result = try setBrightness(config)
            if !config.quiet {
                let active = activeDisplayCount()
                print("\(Date()) set brightness to \(percentString(config.level)); IOKit services: \(result.iokitServices); CoreDisplay displays: \(result.coreDisplayDisplays); ddcctl displays: \(result.ddcctlDisplays); m1ddc displays: \(result.m1ddcDisplays); brightness CLI: \(result.brightnessCLIDisplays); DisplayServices: \(result.displayServicesDisplays); Lunar: \(result.lunarDisplays); active displays: \(active).")
            }
            return true
        } catch {
            fputs("brightness-keeper: \(error)\n", stderr)
            return false
        }
    }

    let firstApplySucceeded = apply()

    if let interval = config.interval {
        while true {
            Thread.sleep(forTimeInterval: interval)
            apply()
        }
    } else if !firstApplySucceeded {
        exit(1)
    }
} catch {
    fputs("brightness-keeper: \(error)\n", stderr)
    exit(2)
}
