import Foundation
import CoreAudio
import IOBluetooth

struct AirPodsError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}

func normalizedAddress(_ value: String) -> String {
    value.replacingOccurrences(of: ":", with: "").replacingOccurrences(of: "-", with: "").lowercased()
}

func audioUInt32(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
    var property = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var value: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    guard AudioObjectGetPropertyData(object, &property, 0, nil, &size, &value) == noErr, size == MemoryLayout<UInt32>.size else { return nil }
    return value
}

func audioName(_ object: AudioObjectID) -> String? {
    var property = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var value: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    guard AudioObjectGetPropertyData(object, &property, 0, nil, &size, &value) == noErr else { return nil }
    return value?.takeRetainedValue() as String?
}

func audioOutputs() throws -> [AudioDeviceID] {
    var property = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    let system = AudioObjectID(kAudioObjectSystemObject)
    guard AudioObjectGetPropertyDataSize(system, &property, 0, nil, &size) == noErr else { throw AirPodsError("Cannot read macOS audio devices.") }
    guard size > 0 else { return [] }
    guard size % UInt32(MemoryLayout<AudioDeviceID>.size) == 0 else { throw AirPodsError("macOS returned an unrecognized audio device list.") }
    var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
    let result = devices.withUnsafeMutableBytes { AudioObjectGetPropertyData(system, &property, 0, nil, &size, $0.baseAddress!) }
    guard result == noErr else { throw AirPodsError("Cannot read macOS audio devices (\(result)).") }
    return devices.filter { id in
        guard audioUInt32(id, kAudioDevicePropertyTransportType) == kAudioDeviceTransportTypeBluetooth,
              audioUInt32(id, kAudioDevicePropertyDeviceIsAlive) == 1 else { return false }
        var streams = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        var bytes: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &bytes) == noErr && bytes > 0
    }
}

func selectedDevice(_ devices: [IOBluetoothDevice], preferred: String, outputAddress: String?) throws -> IOBluetoothDevice {
    if !preferred.isEmpty {
        let matches = devices.filter { ($0.name ?? "") == preferred || deviceName($0) == preferred || normalizedAddress($0.addressString ?? "") == normalizedAddress(preferred) }
        guard matches.count == 1 else { throw AirPodsError(matches.isEmpty ? "Preferred AirPods not found. Check the Device setting and pair them in Bluetooth settings." : "Several devices have this name. Set Device to the Bluetooth address instead.") }
        return matches[0]
    }
    let airpods = devices.filter { ($0.name ?? "").localizedCaseInsensitiveContains("airpods") || deviceName($0).localizedCaseInsensitiveContains("airpods") }
    let connected = airpods.filter { $0.isConnected() }
    let active = connected.filter { normalizedAddress($0.addressString ?? "") == outputAddress.map(normalizedAddress) }
    if active.count == 1 { return active[0] }
    if connected.count == 1 { return connected[0] }
    if airpods.count == 1 { return airpods[0] }
    if airpods.isEmpty { throw AirPodsError("No paired AirPods found. Pair them in Bluetooth settings, or set Device to their exact name if renamed.") }
    throw AirPodsError("Several AirPods found. Choose one in the workflow’s Device setting.")
}

func outputDevice(for device: IOBluetoothDevice) throws -> AudioDeviceID? {
    let matches = try audioOutputs().filter { id in
        if let mapped = bluetoothDevice(for: id) {
            return normalizedAddress(mapped.addressString ?? "") == normalizedAddress(device.addressString ?? "")
        }
        // shortcut: older systems without the identity mapper require unique names; upgrade if macOS replaces the mapper.
        return audioName(id) == device.name
    }
    let controls = matches.filter { readMode($0) != nil }
    if controls.count == 1 { return controls[0] }
    guard matches.count <= 1 else { throw AirPodsError("Several audio outputs match these AirPods. Try reconnecting them.") }
    return matches.first
}

func deviceName(_ device: IOBluetoothDevice) -> String {
    if let name = bluetoothDisplayName(device), !name.isEmpty { return name }
    if let output = try? outputDevice(for: device), let name = audioName(output) { return name }
    return device.name ?? "AirPods"
}

struct Battery: Equatable {
    var left: Int?
    var right: Int?
    var caseLevel: Int?
    var single: Int?
    var summary: String {
        var parts: [String] = []
        if let left { parts.append("L \(left)%") }
        if let right { parts.append("R \(right)%") }
        if let caseLevel { parts.append("Case \(caseLevel)%") }
        if let single, left == nil && right == nil { parts.append("\(single)%") }
        return parts.isEmpty ? "Unavailable" : parts.joined(separator: " · ")
    }
}

func parseBattery(_ data: Data, address: String) throws -> Battery {
    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let controllers = root["SPBluetoothDataType"] as? [[String: Any]] else { throw AirPodsError("macOS returned an unrecognized Bluetooth report.") }
    for controller in controllers {
        for entry in controller["device_connected"] as? [[String: Any]] ?? [] {
            for properties in entry.values {
                guard let properties = properties as? [String: Any],
                      let reportedAddress = properties["device_address"] as? String,
                      normalizedAddress(reportedAddress) == normalizedAddress(address) else { continue }
                func percent(_ key: String) -> Int? {
                    guard let raw = properties[key] as? String,
                          let value = Int(raw.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespacesAndNewlines)),
                          (0...100).contains(value) else { return nil }
                    return value
                }
                return Battery(left: percent("device_batteryLevelLeft"), right: percent("device_batteryLevelRight"), caseLevel: percent("device_batteryLevelCase"), single: percent("device_batteryLevelMain") ?? percent("device_batteryLevel"))
            }
        }
    }
    return Battery()
}

func readBattery(_ device: IOBluetoothDevice) throws -> Battery {
    guard device.isConnected() else { return Battery() }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
    process.arguments = ["SPBluetoothDataType", "-json", "-timeout", "8"]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    try process.run()
    DispatchQueue.global().asyncAfter(deadline: .now() + 10) { if process.isRunning { process.terminate() } }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw AirPodsError("Battery lookup failed. Check Alfred’s Bluetooth permission in System Settings.") }
    return try parseBattery(data, address: device.addressString ?? "")
}

let modeNames: [UInt32: String] = [1: "Off", 2: "Noise Cancellation", 3: "Transparency", 4: "Adaptive"]
let modeArguments: [String: UInt32] = ["mode:off": 1, "mode:anc": 2, "mode:transparency": 3, "mode:adaptive": 4]

struct Snapshot {
    var name: String
    var address: String
    var connected: Bool
    var battery: Battery
    var batteryError: String? = nil
    var isDefault: Bool
    var mode: UInt32?
    var mask: UInt32?
}

struct MenuItem: Encodable {
    var title: String
    var subtitle: String
    var arg: String? = nil
    var valid: Bool = true
    var variables: [String: String]? = nil
    var text: [String: String]? = nil
}

func menuItems(_ snapshot: Snapshot, query: String) -> [MenuItem] {
    let detail = "\(snapshot.name) · \(snapshot.connected ? "Connected" : "Disconnected")"
    let batteryMessage = "\(snapshot.name): \(snapshot.battery.summary) (last reported by macOS)"
    let batterySubtitle = snapshot.batteryError ?? (snapshot.connected ? "\(detail) · Last reported by macOS; case may be cached" : "\(detail) · Connect to read battery levels")
    var entries: [(MenuItem, String)] = [
        (MenuItem(title: "Battery — \(snapshot.battery.summary)", subtitle: batterySubtitle, arg: "battery", text: ["copy": batteryMessage, "largetype": batteryMessage]), "battery charge level status"),
        (MenuItem(title: snapshot.isDefault ? "AirPods are the default output" : "Connect and use as default output", subtitle: detail, arg: "connect"), "connect default output audio use")
    ]
    for (arg, value) in modeArguments.sorted(by: { $0.value < $1.value }) {
        let supported = snapshot.connected && snapshot.mode != nil && (value == 1 || (snapshot.mask.map { $0 & (1 << (value - 2)) != 0 } ?? false))
        var subtitle = snapshot.mode == value ? "Current listening mode · \(snapshot.name)" : "Set listening mode · \(snapshot.name)"
        if !snapshot.connected { subtitle = "Connect AirPods first" }
        else if !supported { subtitle = "This mode is unavailable on this device or macOS version" }
        else if value == 1 { subtitle += " · Requires Allow Off in AirPods settings" }
        entries.append((MenuItem(title: modeNames[value]!, subtitle: subtitle, arg: arg, valid: supported), "mode listening \(arg.replacingOccurrences(of: ":", with: " ")) \(modeNames[value]!.lowercased())"))
    }
    let words = query.lowercased().split(whereSeparator: { $0.isWhitespace })
    var items = entries.filter { entry in words.allSatisfy { entry.1.contains($0) || entry.0.title.lowercased().contains($0) } }.map { entry -> MenuItem in
        var item = entry.0
        item.variables = ["airpods_target": snapshot.address]
        return item
    }
    if items.isEmpty { items = [MenuItem(title: "No matching AirPods command", subtitle: "Try battery, connect, or mode", valid: false)] }
    return items
}

func makeDefaultOutput(_ device: IOBluetoothDevice) throws {
    if !device.isConnected() {
        let result = device.openConnection()
        guard result == kIOReturnSuccess else { throw AirPodsError("Could not connect AirPods (\(result)). Take them out of the case and enable Bluetooth.") }
    }
    let deadline = Date().addingTimeInterval(8)
    var output: AudioDeviceID?
    repeat {
        output = try outputDevice(for: device)
        if output != nil { break }
        Thread.sleep(forTimeInterval: 0.2)
    } while Date() < deadline
    guard var output else { throw AirPodsError("AirPods connected, but their audio output is unavailable. Put them in your ears and retry.") }
    var property = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    let result = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &property, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &output)
    guard result == noErr else { throw AirPodsError("Could not set the default audio output (\(result)).") }
    let verifyUntil = Date().addingTimeInterval(2)
    repeat {
        if audioUInt32(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice) == output { return }
        Thread.sleep(forTimeInterval: 0.05)
    } while Date() < verifyUntil
    throw AirPodsError("macOS did not retain AirPods as the default output. Try again after any audio route change finishes.")
}

func selfTest() throws {
    let fixture = Data(#"{"SPBluetoothDataType":[{"device_connected":[{"AirPods":{"device_address":"AA:BB:CC:DD:EE:FF","device_batteryLevelLeft":"0%","device_batteryLevelRight":"100%","device_batteryLevelCase":"86%"}},{"Other":{"device_address":"11:22:33:44:55:66","device_batteryLevelLeft":"25%"}}]}]}"#.utf8)
    let battery = try parseBattery(fixture, address: "aa-bb-cc-dd-ee-ff")
    precondition(battery == Battery(left: 0, right: 100, caseLevel: 86))
    let absent = try parseBattery(fixture, address: "00:00:00:00:00:00")
    precondition(absent == Battery())
    let invalid = Data(#"{"SPBluetoothDataType":[{"device_connected":[{"AirPods":{"device_address":"AA:BB:CC:DD:EE:FF","device_batteryLevelLeft":"101%","device_batteryLevelRight":"-1%"}}]}]}"#.utf8)
    let invalidBattery = try parseBattery(invalid, address: "AA:BB:CC:DD:EE:FF")
    precondition(invalidBattery == Battery())
    do { _ = try parseBattery(Data("{}".utf8), address: ""); preconditionFailure("Malformed report accepted") } catch {}
    let snapshot = Snapshot(name: "Test’s AirPods", address: "AA:BB:CC:DD:EE:FF", connected: true, battery: battery, isDefault: false, mode: 2, mask: 7)
    precondition(menuItems(snapshot, query: "").count == 6)
    precondition(menuItems(snapshot, query: "mode anc").first?.arg == "mode:anc")
    precondition(menuItems(snapshot, query: "BATTERY").first?.arg == "battery")
    precondition(menuItems(snapshot, query: "connect").first?.arg == "connect")
    precondition(menuItems(snapshot, query: "transparency").first?.valid == true)
    var disconnected = snapshot
    disconnected.connected = false
    precondition(menuItems(disconnected, query: "mode").allSatisfy { !$0.valid })
    var limited = snapshot
    limited.mask = 3
    precondition(menuItems(limited, query: "adaptive").first?.valid == false)
    let encoded = try JSONEncoder().encode(["items": menuItems(snapshot, query: "")])
    let decoded = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
    precondition(decoded?["items"] != nil)
    precondition(readMode(0) == nil && supportedModeMask(0) == nil)
    for invalidMode: UInt32 in [0, 5, UInt32.max] {
        do { try setMode(invalidMode, device: 0); preconditionFailure("Invalid mode accepted") } catch {}
    }
    do { _ = try selectedDevice([], preferred: "", outputAddress: nil); preconditionFailure("Missing devices accepted") } catch {}
    print("Self-test passed: battery parsing, bounds, missing devices, command filtering, capability gating, JSON.")
}

@main
struct AirPodsWorkflow {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let command = arguments.first ?? "menu"
        do {
            if command == "--self-test" { try selfTest(); return }
            guard command == "menu" || command == "action" else { throw AirPodsError("Usage: airpods menu [query] | action battery|connect|mode:off|mode:anc|mode:transparency|mode:adaptive | --self-test") }
            let query = arguments.dropFirst().first ?? ""
            if command == "action", query != "battery", query != "connect", modeArguments[query] == nil { throw AirPodsError("Unknown AirPods action.") }
            let environment = ProcessInfo.processInfo.environment
            let preferred = (environment["airpods_target"] ?? environment["device"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
            let defaultID = audioUInt32(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice)
            let outputAddress = defaultID.flatMap { bluetoothDevice(for: $0)?.addressString }
            let device = try selectedDevice(devices, preferred: preferred, outputAddress: outputAddress)
            if command == "menu" {
                let output = try outputDevice(for: device)
                var battery = Battery()
                var batteryError: String?
                do { battery = try readBattery(device) } catch { batteryError = error.localizedDescription }
                let snapshot = Snapshot(name: deviceName(device), address: device.addressString ?? "", connected: device.isConnected(), battery: battery, batteryError: batteryError, isDefault: output != nil && output == defaultID, mode: output.flatMap(readMode), mask: output.flatMap(supportedModeMask))
                let data = try JSONEncoder().encode(["items": menuItems(snapshot, query: query)])
                print(String(decoding: data, as: UTF8.self))
            } else if query == "battery" {
                guard device.isConnected() else { throw AirPodsError("AirPods are disconnected. Run the connect command first.") }
                let battery = try readBattery(device)
                guard battery != Battery() else { throw AirPodsError("Battery unavailable. Open the case near your Mac, then retry.") }
                print("\(deviceName(device)): \(battery.summary) (last reported by macOS)")
            } else if query == "connect" {
                try makeDefaultOutput(device)
                print("\(deviceName(device)) are now the default audio output.")
            } else if let mode = modeArguments[query] {
                guard device.isConnected(), let output = try outputDevice(for: device) else { throw AirPodsError("Connect AirPods before changing listening mode.") }
                try setMode(mode, device: output)
                print("\(deviceName(device)): \(modeNames[mode]!) (reported by macOS)")
            }
        } catch {
            let message = error.localizedDescription
            if command == "menu" {
                let items = [MenuItem(title: "AirPods unavailable", subtitle: message, valid: false)]
                if let data = try? JSONEncoder().encode(["items": items]) { print(String(decoding: data, as: UTF8.self)) }
            } else {
                // Keep actionable errors on stdout so Alfred can display them as notifications.
                print("AirPods: \(message)")
                exit(1)
            }
        }
    }
}
