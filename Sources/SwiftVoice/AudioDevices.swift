import CoreAudio
import Foundation

struct AudioInputDevice: Equatable {
    let id: AudioDeviceID
    let name: String
}

enum AudioDevices {
    static func inputDevices() -> [AudioInputDevice] {
        allDeviceIDs()
            .filter(hasInputChannels)
            .compactMap { id in
                guard let name = deviceName(id) else { return nil }
                return AudioInputDevice(id: id, name: name)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func defaultInputDevice() -> AudioInputDevice? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)

        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &id
        ) == noErr, id != 0, let name = deviceName(id) else {
            return nil
        }
        return AudioInputDevice(id: id, name: name)
    }

    static func setDefaultInputDevice(_ id: AudioDeviceID) throws {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var mutableID = id
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &mutableID
        )
        guard status == noErr else {
            throw AudioDeviceError.switchFailed(status)
        }
    }

    private static func allDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size
        ) == noErr else {
            return []
        }

        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = Array(repeating: AudioDeviceID(0), count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &ids
        ) == noErr else {
            return []
        }
        return ids
    }

    private static func hasInputChannels(_ id: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr else {
            return false
        }

        let pointer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { pointer.deallocate() }

        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, pointer) == noErr else {
            return false
        }

        let buffers = UnsafeMutableAudioBufferListPointer(
            pointer.assumingMemoryBound(to: AudioBufferList.self)
        )
        return buffers.reduce(0) { $0 + Int($1.mNumberChannels) } > 0
    }

    static func isCurrentInputBluetoothOrHeadset() -> Bool {
        guard let defaultDevice = defaultInputDevice() else { return false }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transportType: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        if AudioObjectGetPropertyData(defaultDevice.id, &address, 0, nil, &size, &transportType) == noErr {
            if transportType == kAudioDeviceTransportTypeBluetooth ||
               transportType == kAudioDeviceTransportTypeBluetoothLE {
                return true
            }
        }
        let lowerName = defaultDevice.name.lowercased()
        return lowerName.contains("airpods") || lowerName.contains("bluetooth") || lowerName.contains("headset") || lowerName.contains("headphones")
    }

    private static func deviceName(_ id: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &name) { pointer in
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, pointer)
        }
        return status == noErr ? name as String : nil
    }
}

enum AudioDeviceError: LocalizedError {
    case switchFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case let .switchFailed(status):
            return "Не удалось переключить микрофон (CoreAudio: \(status))."
        }
    }
}
