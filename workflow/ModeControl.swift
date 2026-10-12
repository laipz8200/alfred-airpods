import CoreAudio
import Foundation

// Undocumented BTAudioHAL property facts: https://github.com/raulgg/pods-control/blob/main/Sources/AirPodsControl/CoreAudioRoutingBackend.swift
private let ModeCurrentSelector: AudioObjectPropertySelector = 0x6c73746d // lstm
private let ModeSupportSelector: AudioObjectPropertySelector = 0x6c736d73 // lsms

private enum ModeControlError: LocalizedError {
    case invalidValue, unavailable, unsupported, notSettable, badSize, system(OSStatus), notRetained(UInt32?)

    var errorDescription: String? {
        switch self {
        case .invalidValue: return "Listening mode must be Off, Noise Cancellation, Transparency, or Adaptive."
        case .unavailable: return "macOS does not expose listening controls for these AirPods."
        case .unsupported: return "These AirPods do not report support for this listening mode."
        case .notSettable: return "macOS currently prevents changing this listening mode."
        case .badSize: return "The macOS listening-control interface has changed."
        case .system(let status): return "macOS listening control failed (\(status))."
        case .notRetained(let actual):
            return "macOS did not retain the requested listening mode (reported \(actual.map(String.init) ?? "unknown")). For Off, enable Off Listening Mode in your AirPods settings."
        }
    }
}

private func ModeAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                               mElement: kAudioObjectPropertyElementMain)
}

private func ModeReadUInt32(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) throws -> UInt32 {
    var address = ModeAddress(selector)
    guard AudioObjectHasProperty(id, &address) else { throw ModeControlError.unavailable }
    var size: UInt32 = 0
    var status = AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size)
    guard status == noErr else { throw ModeControlError.system(status) }
    guard size == MemoryLayout<UInt32>.size else { throw ModeControlError.badSize }
    var value: UInt32 = 0
    status = AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value)
    guard status == noErr else { throw ModeControlError.system(status) }
    guard size == MemoryLayout<UInt32>.size else { throw ModeControlError.badSize }
    return value
}

func readMode(_ id: AudioDeviceID) -> UInt32? {
    guard let value = try? ModeReadUInt32(id, ModeCurrentSelector), (1...4).contains(value) else { return nil }
    return value
}

func supportedModeMask(_ id: AudioDeviceID) -> UInt32? {
    try? ModeReadUInt32(id, ModeSupportSelector)
}

func setMode(_ value: UInt32, device: AudioDeviceID) throws {
    guard (1...4).contains(value) else { throw ModeControlError.invalidValue }
    _ = try ModeReadUInt32(device, ModeCurrentSelector)
    if value > 1 {
        let mask = try ModeReadUInt32(device, ModeSupportSelector)
        guard mask & (1 << (value - 2)) != 0 else { throw ModeControlError.unsupported }
    }
    var address = ModeAddress(ModeCurrentSelector)
    var settable = DarwinBoolean(false)
    var status = AudioObjectIsPropertySettable(device, &address, &settable)
    guard status == noErr else { throw ModeControlError.system(status) }
    guard settable.boolValue else { throw ModeControlError.notSettable }
    var target = value
    status = AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &target)
    guard status == noErr else { throw ModeControlError.system(status) }
    // HAL caches writes optimistically: settle before verifying the final OS-reported state, not an accessory acknowledgement.
    var observed: UInt32?
    for _ in 0..<16 {
        Thread.sleep(forTimeInterval: 0.05)
        observed = readMode(device)
    }
    guard observed == value else { throw ModeControlError.notRetained(observed) }
}
