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
    var fallbackKeys = false
    var diagnose = false
}

enum BrightnessKeeperError: Error, CustomStringConvertible {
    case invalidValue(String)
    case unknownArgument(String)
    case noDisplaysControlled

    var description: String {
        switch self {
        case .invalidValue(let value):
            return "Invalid brightness value: \(value). Use 0.0-1.0 or 0-100."
        case .unknownArgument(let argument):
            return "Unknown argument: \(argument). Run with --help for usage."
        case .noDisplaysControlled:
            return "macOS did not accept brightness control for any display."
        }
    }
}

struct BrightnessResult {
    let iokitServices: Int
    let coreDisplayDisplays: Int
    let brightnessKeyFallback: Bool

    var total: Int {
        iokitServices + coreDisplayDisplays + (brightnessKeyFallback ? 1 : 0)
    }
}

func usage() {
    print("""
    brightness-keeper

    Force display brightness to a target level using macOS display services.

    Usage:
      tools/brightness-keeper [--level 100] [--interval 10] [--quiet]
      tools/brightness-keeper --once --level 100

    Options:
      --level, -l       Target brightness. Accepts 0.0-1.0 or 0-100. Default: 100.
      --interval, -i    Re-apply brightness every N seconds. If omitted, runs once.
      --once            Run once, even if --interval is present earlier.
      --fallback-keys   If APIs fail and level is 100, press brightness-up keys.
      --diagnose        Print display/control diagnostics and exit.
      --quiet, -q       Only print errors.
      --help, -h        Show this help.

    Examples:
      tools/brightness-keeper --level 100
      tools/brightness-keeper --level 85 --interval 15
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
            config.fallbackKeys = true
        case "--diagnose":
            config.diagnose = true
        case "--once":
            config.interval = nil
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
    typealias SetUserBrightness = @convention(c) (CGDirectDisplayID, Double) -> Int32

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
    var successCount = 0

    for display in activeDisplays() {
        let result = setUserBrightness(display, Double(level))
        if result == 0 {
            successCount += 1
        }
    }

    return successCount
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

func setBrightnessWithKeyboardFallback() -> Bool {
    let script = """
    tell application "System Events"
      repeat 32 times
        key code 145
        delay 0.01
      end repeat
    end tell
    """

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = ["-e", script]

    do {
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    } catch {
        return false
    }
}

@discardableResult
func setBrightness(_ level: Float, fallbackKeys: Bool) throws -> BrightnessResult {
    let iokitServices = setBrightnessWithIOKit(level)
    let coreDisplayDisplays = setBrightnessWithCoreDisplay(level)
    var brightnessKeyFallback = false

    if iokitServices + coreDisplayDisplays == 0 && fallbackKeys && level >= 0.99 {
        brightnessKeyFallback = setBrightnessWithKeyboardFallback()
    }

    let result = BrightnessResult(
        iokitServices: iokitServices,
        coreDisplayDisplays: coreDisplayDisplays,
        brightnessKeyFallback: brightnessKeyFallback
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
        exit(0)
    }

    @discardableResult
    func apply() -> Bool {
        do {
            let result = try setBrightness(config.level, fallbackKeys: config.fallbackKeys)
            if !config.quiet {
                let active = activeDisplayCount()
                print("\(Date()) set brightness to \(percentString(config.level)); IOKit services: \(result.iokitServices); CoreDisplay displays: \(result.coreDisplayDisplays); key fallback: \(result.brightnessKeyFallback); active displays: \(active).")
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
