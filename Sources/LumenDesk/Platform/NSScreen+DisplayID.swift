import AppKit

extension NSScreen {
    var displayID: UInt32 {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        let value = deviceDescription[key] as? NSNumber
        return value?.uint32Value ?? UInt32(abs(hashValue))
    }

    var descriptor: DisplayDescriptor {
        let size = frame.size
        let width = Int(size.width)
        let height = Int(size.height)
        return DisplayDescriptor(
            id: displayID,
            name: localizedName,
            sizeDescription: "\(width)x\(height)"
        )
    }
}
