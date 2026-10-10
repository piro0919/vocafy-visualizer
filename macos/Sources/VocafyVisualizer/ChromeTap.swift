import AudioToolbox
import CoreAudio
import Foundation

/// Listens to what Chrome plays, through a Core Audio process tap. Only Chrome's processes are
/// tapped, so system sounds and other apps stay out of the bars. Nothing is recorded: the
/// samples go to the spectrum and are overwritten.
///
/// Chrome plays from helper processes that come and go, and the tap is bound to the output
/// device, so `refresh()` rebuilds the tap whenever either changes.
@MainActor
final class ChromeTap {
    private let spectrum: Spectrum
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProc: AudioDeviceIOProcID?
    private var current = ""

    init(spectrum: Spectrum) {
        self.spectrum = spectrum
    }

    var isRunning: Bool { ioProc != nil }

    func refresh() {
        let chrome = processObjects().filter { bundleID(of: $0)?.hasPrefix("com.google.Chrome") == true }.sorted()
        let output = defaultOutputUID() ?? ""
        let next = "\(chrome)|\(output)"
        if next == current { return }
        current = next
        stop()
        if !chrome.isEmpty && !output.isEmpty { start(chrome, outputUID: output) }
    }

    private func start(_ processes: [AudioObjectID], outputUID: String) {
        let description = CATapDescription(stereoMixdownOfProcesses: processes)
        description.uuid = UUID()
        description.muteBehavior = .unmuted
        description.isPrivate = true
        guard AudioHardwareCreateProcessTap(description, &tapID) == noErr else { return }

        var formatAddress = address(kAudioTapPropertyFormat)
        var format = AudioStreamBasicDescription()
        var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        if AudioObjectGetPropertyData(tapID, &formatAddress, 0, nil, &formatSize, &format) == noErr {
            spectrum.sampleRate = Float(format.mSampleRate)
        }

        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Vocafy Visualizer",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [
                [kAudioSubTapDriftCompensationKey: true, kAudioSubTapUIDKey: description.uuid.uuidString]
            ],
        ]
        guard AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID) == noErr else {
            stop()
            return
        }

        var proc: AudioDeviceIOProcID?
        let status = AudioDeviceCreateIOProcIDWithBlock(&proc, aggregateID, nil, Self.receiver(for: spectrum))
        guard status == noErr, let proc else {
            stop()
            return
        }
        ioProc = proc
        if AudioDeviceStart(aggregateID, proc) != noErr { stop() }
    }

    /// The block Core Audio calls on its own thread. Made outside the main actor: a closure
    /// written inside this class would inherit the main actor, and Swift 6 stops the app when
    /// the audio thread calls it.
    private nonisolated static func receiver(for spectrum: Spectrum) -> AudioDeviceIOBlock {
        { _, input, _, _, _ in
            let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
            guard let buffer = buffers.first, let data = buffer.mData else { return }
            let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            spectrum.push(
                UnsafeBufferPointer(start: data.assumingMemoryBound(to: Float.self), count: count),
                channels: Int(buffer.mNumberChannels))
        }
    }

    func stop() {
        if let ioProc {
            AudioDeviceStop(aggregateID, ioProc)
            AudioDeviceDestroyIOProcID(aggregateID, ioProc)
        }
        ioProc = nil
        if aggregateID != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggregateID) }
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
        tapID = AudioObjectID(kAudioObjectUnknown)
        spectrum.reset()
    }
}

// MARK: - Core Audio properties

private func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(
        mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
}

/// The processes Core Audio knows about, as audio objects.
private func processObjects() -> [AudioObjectID] {
    let system = AudioObjectID(kAudioObjectSystemObject)
    var listAddress = address(kAudioHardwarePropertyProcessObjectList)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(system, &listAddress, 0, nil, &size) == noErr else { return [] }
    var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    guard AudioObjectGetPropertyData(system, &listAddress, 0, nil, &size, &ids) == noErr else { return [] }
    return ids
}

private func bundleID(of process: AudioObjectID) -> String? {
    stringProperty(of: process, kAudioProcessPropertyBundleID)
}

private func defaultOutputUID() -> String? {
    var deviceAddress = address(kAudioHardwarePropertyDefaultSystemOutputDevice)
    var device = AudioObjectID(0)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    guard
        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &deviceAddress, 0, nil, &size, &device) == noErr
    else { return nil }
    return stringProperty(of: device, kAudioDevicePropertyDeviceUID)
}

private func stringProperty(of object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
    var propertyAddress = address(selector)
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    var value: Unmanaged<CFString>?
    guard AudioObjectGetPropertyData(object, &propertyAddress, 0, nil, &size, &value) == noErr else { return nil }
    return value?.takeRetainedValue() as String?
}
