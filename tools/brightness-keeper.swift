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
    var useM1DDC = false
    var m1ddcOnly = false
    var m1ddcDisplays: [Int] = []
    var useDisplayServices = false
    var displayServicesOnly = false
    var diagnose = false
}

enum BrightnessKeeperError: Error, CustomStringConvertible {
    case invalidValue(String)
    case unknownArgument(String)
    case invalidM1DDCDisplay(String)
    case m1ddcUnavailable
    case m1ddcFailed([Int], String)
    case displayServicesUnavailable
    case displayServicesNoBuiltInDisplay
    case displayServicesFailed([CGDirectDisplayID])
    case noDisplaysControlled

    var description: String {
        switch self {
        case .invalidValue(let value):
            return "Invalid brightness value: \(value). Use 0.0-1.0 or 0-100."
        case .unknownArgument(let argument):
            return "Unknown argument: \(argument). Run with --help for usage."
        case .invalidM1DDCDisplay(let value):
            return "Invalid m1ddc display index: \(value). Use a positive integer, or a comma-separated list such as 1,2."
        case .m1ddcUnavailable:
            return "m1ddc was requested but was not found. Install it, then retry."
        case .m1ddcFailed(let displayIndexes, let output):
            let displays = displayIndexes.isEmpty ? "default" : displayIndexes.map(String.init).joined(separator: ",")
            let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedOutput.isEmpty {
                return "m1ddc failed for display index(es) \(displays), but produced no output. Try `m1ddc display list` directly."
            }
            return "m1ddc failed for display index(es) \(displays). Last m1ddc output:\n\(trimmedOutput)"
        case .displayServicesUnavailable:
            return "DisplayServices brightness API was requested but is not available on this macOS install."
        case .displayServicesNoBuiltInDisplay:
            return "DisplayServices brightness API was requested but no active built-in display was found."
        case .displayServicesFailed(let displayIDs):
            return "DisplayServices failed for built-in display ID(s): \(displayIDs.map { String($0) }.joined(separator: ", "))."
        case .noDisplaysControlled:
            return "macOS did not accept brightness control for any display. For the built-in display, try --display-services. For external DDC/CI monitors, try --m1ddc."
        }
    }
}

struct BrightnessResult {
    let iokitServices: Int
    let coreDisplayDisplays: Int
    let m1ddcDisplays: Int
    let displayServicesDisplays: Int

    var total: Int {
        iokitServices + coreDisplayDisplays + m1ddcDisplays + displayServicesDisplays
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
      --m1ddc           Also set brightness with m1ddc DDC/CI control.
      --m1ddc-only      Only use m1ddc DDC/CI control.
      --m1ddc-display   m1ddc display index, repeatable or comma-separated. Default: m1ddc default.
      --display-services
                        Also set built-in brightness with local DisplayServices API.
      --display-services-only
                        Only use local DisplayServices API.
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

func parseM1DDCDisplays(_ raw: String) throws -> [Int] {
    let parts = raw.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
    guard !parts.isEmpty else {
        throw BrightnessKeeperError.invalidM1DDCDisplay(raw)
    }

    return try parts.map { part in
        guard let index = Int(part), index > 0 else {
            throw BrightnessKeeperError.invalidM1DDCDisplay(part)
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
        case "--m1ddc":
            config.useM1DDC = true
        case "--m1ddc-only":
            config.useM1DDC = true
            config.m1ddcOnly = true
        case "--display-services":
            config.useDisplayServices = true
        case "--display-services-only":
            config.useDisplayServices = true
            config.displayServicesOnly = true
        case "--diagnose":
            config.diagnose = true
        case "--once":
            config.interval = nil
        case "--m1ddc-display":
            index += 1
            guard index < arguments.count else {
                throw BrightnessKeeperError.invalidM1DDCDisplay("")
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
            } else if argument.hasPrefix("--m1ddc-display=") {
                config.useM1DDC = true
                config.m1ddcDisplays.append(contentsOf: try parseM1DDCDisplays(String(argument.dropFirst("--m1ddc-display=".count))))
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

@discardableResult
func setBrightness(_ config: Config) throws -> BrightnessResult {
    let helperBackendOnly = config.m1ddcOnly || config.displayServicesOnly
    let iokitServices = helperBackendOnly ? 0 : setBrightnessWithIOKit(config.level)
    let coreDisplayDisplays = helperBackendOnly ? 0 : setBrightnessWithCoreDisplay(config.level)
    let m1ddcDisplays = config.useM1DDC
        ? try setBrightnessWithM1DDC(config.level, displayIndexes: config.m1ddcDisplays)
        : 0
    let displayServicesDisplays = config.useDisplayServices
        ? try setBuiltInBrightnessWithDisplayServices(config.level)
        : 0

    let result = BrightnessResult(
        iokitServices: iokitServices,
        coreDisplayDisplays: coreDisplayDisplays,
        m1ddcDisplays: m1ddcDisplays,
        displayServicesDisplays: displayServicesDisplays
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
        if let m1ddcPath = executablePath(named: "m1ddc") {
            print("m1ddc path: \(m1ddcPath)")
            if let result = runCommand(m1ddcPath, arguments: ["display", "list"]) {
                print("m1ddc display list:")
                print(result.output.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        } else {
            print("m1ddc path: not found")
        }
        exit(0)
    }

    @discardableResult
    func apply() -> Bool {
        do {
            let result = try setBrightness(config)
            if !config.quiet {
                let active = activeDisplayCount()
                print("\(Date()) set brightness to \(percentString(config.level)); IOKit services: \(result.iokitServices); CoreDisplay displays: \(result.coreDisplayDisplays); m1ddc displays: \(result.m1ddcDisplays); DisplayServices: \(result.displayServicesDisplays); active displays: \(active).")
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
