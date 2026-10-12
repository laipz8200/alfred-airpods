import Foundation
import CoreAudio
import IOBluetooth
import ObjectiveC

// Private mapping facts: https://github.com/raulgg/pods-control/blob/main/Sources/AirPodsControl/IOBluetoothAudio.swift
func bluetoothDevice(for audioDevice: AudioDeviceID) -> IOBluetoothDevice? {
    let selector = NSSelectorFromString("bluetoothDevice:")
    guard let manager: AnyClass = NSClassFromString("IOBluetoothAudioManager"),
          let method = class_getClassMethod(manager, selector),
          method_getNumberOfArguments(method) == 3 else { return nil }
    let resultType = method_copyReturnType(method)
    defer { free(resultType) }
    guard let argumentType = method_copyArgumentType(method, 2) else { return nil }
    defer { free(argumentType) }
    guard String(cString: resultType) == "@", String(cString: argumentType) == "I" else { return nil }
    let lookup = unsafeBitCast(method_getImplementation(method),
                              to: (@convention(c) (AnyObject, Selector, UInt32) -> Unmanaged<AnyObject>?).self)
    return lookup(manager as AnyObject, selector, audioDevice)?.takeUnretainedValue() as? IOBluetoothDevice
}

func bluetoothDisplayName(_ device: IOBluetoothDevice) -> String? {
    let selector = NSSelectorFromString("getDisplayName")
    guard let method = class_getInstanceMethod(type(of: device), selector),
          method_getNumberOfArguments(method) == 2 else { return nil }
    let resultType = method_copyReturnType(method)
    defer { free(resultType) }
    guard String(cString: resultType) == "@" else { return nil }
    return device.perform(selector)?.takeUnretainedValue() as? String
}
