import Foundation

/// Writes a ZIP archive of uncompressed ("stored") entries, which is all a
/// `.docx` needs. Word, Pages, LibreOffice and Google Docs all read stored
/// entries.
public struct ZipWriter {
    private struct Entry {
        let name: [UInt8]
        let crc: UInt32
        let size: UInt32
        let offset: UInt32
    }

    private var data = Data()
    private var entries: [Entry] = []
    private let dosTime: UInt16
    private let dosDate: UInt16

    /// `date` is stamped on every entry (as local wall-clock time in UTC,
    /// which is what ZIP's DOS format holds).
    public init(date: Date = Date()) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let year: Int = max(1980, min(2107, c.year ?? 1980))
        let month: Int = c.month ?? 1, day: Int = c.day ?? 1
        let hour: Int = c.hour ?? 0, minute: Int = c.minute ?? 0, second: Int = c.second ?? 0
        let packedDate: Int = ((year - 1980) << 9) | (month << 5) | day
        let packedTime: Int = (hour << 11) | (minute << 5) | (second / 2)
        dosDate = UInt16(packedDate)
        dosTime = UInt16(packedTime)
    }

    public mutating func add(_ name: String, _ contents: Data) {
        let nameBytes = Array(name.utf8)
        let crc = CRC32.checksum(contents)
        let entry = Entry(name: nameBytes, crc: crc, size: UInt32(contents.count), offset: UInt32(data.count))
        data.append(le32: 0x0403_4b50)
        data.append(le16: 20)          // version needed
        data.append(le16: 0x0800)      // UTF-8 names
        data.append(le16: 0)           // stored
        data.append(le16: dosTime)
        data.append(le16: dosDate)
        data.append(le32: crc)
        data.append(le32: entry.size)
        data.append(le32: entry.size)
        data.append(le16: UInt16(nameBytes.count))
        data.append(le16: 0)           // extra length
        data.append(contentsOf: nameBytes)
        data.append(contents)
        entries.append(entry)
    }

    public mutating func add(_ name: String, _ text: String) {
        add(name, Data(text.utf8))
    }

    /// The finished archive.
    public func finish() -> Data {
        var out = data
        let start = UInt32(out.count)
        for e in entries {
            out.append(le32: 0x0201_4b50)
            out.append(le16: 20)       // version made by
            out.append(le16: 20)       // version needed
            out.append(le16: 0x0800)
            out.append(le16: 0)
            out.append(le16: dosTime)
            out.append(le16: dosDate)
            out.append(le32: e.crc)
            out.append(le32: e.size)
            out.append(le32: e.size)
            out.append(le16: UInt16(e.name.count))
            out.append(le16: 0)        // extra
            out.append(le16: 0)        // comment
            out.append(le16: 0)        // disk
            out.append(le16: 0)        // internal attributes
            out.append(le32: 0)        // external attributes
            out.append(le32: e.offset)
            out.append(contentsOf: e.name)
        }
        let size = UInt32(out.count) - start
        out.append(le32: 0x0605_4b50)
        out.append(le16: 0)
        out.append(le16: 0)
        out.append(le16: UInt16(entries.count))
        out.append(le16: UInt16(entries.count))
        out.append(le32: size)
        out.append(le32: start)
        out.append(le16: 0)
        return out
    }
}

/// CRC-32 (IEEE 802.3), as ZIP uses.
public enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    public static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }
}

extension Data {
    mutating func append(le16 v: UInt16) {
        append(contentsOf: [UInt8(v & 0xFF), UInt8(v >> 8)])
    }

    mutating func append(le32 v: UInt32) {
        append(contentsOf: [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8(v >> 24)])
    }
}
