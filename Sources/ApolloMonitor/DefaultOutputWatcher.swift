import CoreAudio
import Foundation

/// Tracks whether macOS's default output device is the Apollo.
///
/// This gates the volume-key interception. The Apollo has no Core Audio volume
/// control of its own — which is exactly why macOS's volume HUD shows a greyed
/// out slider for it — so the keys are only worth stealing while it is the output
/// device. Switch to the built-in speakers or a USB interface and the keys must
/// go back to doing their normal job, because those devices *do* have their own
/// volume and macOS handles them correctly.
///
/// The answer is cached rather than queried per keystroke: the lookup happens
/// inside the event-tap callback, and HAL calls talk to coreaudiod, which can
/// block. A tap that blocks gets disabled by the system.
final class DefaultOutputWatcher {
    private(set) var isUniversalAudio = false

    private var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    init() {
        refresh()
        // Update the moment the output device changes, so switching to the
        // speakers and immediately pressing volume-up does the right thing.
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main
        ) { [weak self] _, _ in
            self?.refresh()
        }
    }

    func refresh() {
        let wasUniversalAudio = isUniversalAudio
        isUniversalAudio = Self.defaultOutputIsUniversalAudio()
        if isUniversalAudio != wasUniversalAudio {
            log.notice("default output is Universal Audio: \(self.isUniversalAudio, privacy: .public)")
        }
    }

    // MARK: - Core Audio

    private static func defaultOutputIsUniversalAudio() -> Bool {
        guard let device = defaultOutputDevice() else { return false }
        // Match the manufacturer ("Universal Audio, Inc.") rather than the device
        // name, so this holds for any Apollo, not just the Thunderbolt driver's
        // "Universal Audio Thunderbolt".
        let fields = [
            string(device, kAudioObjectPropertyManufacturer),
            string(device, kAudioObjectPropertyName),
        ]
        return fields.compactMap { $0 }.contains { $0.contains("Universal Audio") }
    }

    private static func defaultOutputDevice() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device
        )
        return status == noErr && device != 0 ? device : nil
    }

    private static func string(
        _ device: AudioDeviceID, _ selector: AudioObjectPropertySelector
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(device, &address) else { return nil }

        var value: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(device, &address, 0, nil, &size, pointer)
        }
        return status == noErr ? value as String : nil
    }
}
