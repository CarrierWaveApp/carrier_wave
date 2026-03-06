import Foundation

// MARK: - SerialPort

/// Low-level POSIX termios serial port wrapper.
/// Uses /dev/cu.* ports to avoid DCD blocking on /dev/tty.*.
final class SerialPort: @unchecked Sendable {
    // MARK: Lifecycle

    init(path: String) {
        self.path = path
    }

    deinit {
        close()
    }

    // MARK: Internal

    let path: String
    private(set) var fileDescriptor: Int32 = -1

    var isOpen: Bool {
        fileDescriptor >= 0
    }

    func open(
        baudRate: Int = 19_200,
        dataBits: Int = 8,
        stopBits: Int = 1,
        parity: ParityType = .none,
        flowControl: FlowControlType = .none,
        assertDTR: Bool = true,
        assertRTS: Bool = true
    ) throws {
        let fd = Darwin.open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard fd >= 0 else {
            throw SerialPortError.failedToOpen(path: path, errno: errno)
        }

        if ioctl(fd, TIOCEXCL) == -1 {
            Darwin.close(fd)
            throw SerialPortError.failedToGetExclusive(path: path)
        }

        // De-assert DTR/RTS before termios to prevent Elecraft TEST mode
        applyDTRRTS(fd: fd, assertDTR: assertDTR, assertRTS: assertRTS)

        var options = termios()
        tcgetattr(fd, &options)
        configureSpeed(&options, baudRate: baudRate)
        configureLineParams(&options, dataBits: dataBits, stopBits: stopBits, parity: parity)
        configureFlowControl(&options, flowControl: flowControl)
        tcsetattr(fd, TCSANOW, &options)
        tcflush(fd, TCIOFLUSH)

        fileDescriptor = fd

        // Re-apply after tcsetattr (which may have re-asserted them)
        applyDTRRTS(fd: fd, assertDTR: assertDTR, assertRTS: assertRTS)
    }

    func close() {
        guard fileDescriptor >= 0 else {
            return
        }
        Darwin.close(fileDescriptor)
        fileDescriptor = -1
    }

    func write(_ data: Data) throws -> Int {
        guard fileDescriptor >= 0 else {
            throw SerialPortError.portNotOpen
        }

        let written = data.withUnsafeBytes { buffer -> Int in
            guard let ptr = buffer.baseAddress else {
                return -1
            }
            return Darwin.write(fileDescriptor, ptr, buffer.count)
        }

        guard written >= 0 else {
            throw SerialPortError.writeFailed(errno: errno)
        }

        // Ensure data is transmitted to hardware (not just buffered in kernel)
        tcdrain(fileDescriptor)

        return written
    }

    func read(maxBytes: Int = 4_096) throws -> Data {
        guard fileDescriptor >= 0 else {
            throw SerialPortError.portNotOpen
        }

        var buffer = [UInt8](repeating: 0, count: maxBytes)
        let bytesRead = Darwin.read(fileDescriptor, &buffer, maxBytes)

        guard bytesRead >= 0 else {
            if errno == EAGAIN {
                return Data()
            }
            throw SerialPortError.readFailed(errno: errno)
        }

        return Data(buffer[0 ..< bytesRead])
    }

    /// Set DTR signal state (used for CW keying fallback)
    func setDTR(_ state: Bool) throws {
        guard fileDescriptor >= 0 else {
            throw SerialPortError.portNotOpen
        }
        var flag: Int32 = TIOCM_DTR
        let result = ioctl(fileDescriptor, state ? TIOCMBIS : TIOCMBIC, &flag)
        guard result >= 0 else {
            throw SerialPortError.ioctlFailed(errno: errno)
        }
    }

    /// Set RTS signal state (used for PTT on some radios)
    func setRTS(_ state: Bool) throws {
        guard fileDescriptor >= 0 else {
            throw SerialPortError.portNotOpen
        }
        var flag: Int32 = TIOCM_RTS
        let result = ioctl(fileDescriptor, state ? TIOCMBIS : TIOCMBIC, &flag)
        guard result >= 0 else {
            throw SerialPortError.ioctlFailed(errno: errno)
        }
    }

    // MARK: Private

    private static func baudRateConstant(for rate: Int) -> speed_t {
        switch rate {
        case 1_200: speed_t(B1200)
        case 2_400: speed_t(B2400)
        case 4_800: speed_t(B4800)
        case 9_600: speed_t(B9600)
        case 19_200: speed_t(B19200)
        case 38_400: speed_t(B38400)
        case 57_600: speed_t(B57600)
        case 115_200: speed_t(B115200)
        case 230_400: speed_t(B230400)
        default: speed_t(B19200)
        }
    }

    private func configureSpeed(_ options: inout termios, baudRate: Int) {
        let speed = Self.baudRateConstant(for: baudRate)
        cfsetispeed(&options, speed)
        cfsetospeed(&options, speed)
        cfmakeraw(&options)
    }

    private func configureLineParams(
        _ options: inout termios,
        dataBits: Int, stopBits: Int, parity: ParityType
    ) {
        options.c_cflag &= ~UInt(CSIZE)
        switch dataBits {
        case 5: options.c_cflag |= UInt(CS5)
        case 6: options.c_cflag |= UInt(CS6)
        case 7: options.c_cflag |= UInt(CS7)
        default: options.c_cflag |= UInt(CS8)
        }

        if stopBits == 2 {
            options.c_cflag |= UInt(CSTOPB)
        } else {
            options.c_cflag &= ~UInt(CSTOPB)
        }

        switch parity {
        case .none: options.c_cflag &= ~UInt(PARENB)
        case .even:
            options.c_cflag |= UInt(PARENB)
            options.c_cflag &= ~UInt(PARODD)
        case .odd: options.c_cflag |= UInt(PARENB | PARODD)
        }

        options.c_cflag |= UInt(CLOCAL | CREAD)
        options.c_cflag &= ~UInt(HUPCL)
        options.c_cc.16 = 0 // VMIN
        options.c_cc.17 = 0 // VTIME
    }

    private func configureFlowControl(_ options: inout termios, flowControl: FlowControlType) {
        switch flowControl {
        case .none:
            options.c_cflag &= ~UInt(CRTSCTS)
            options.c_iflag &= ~UInt(IXON | IXOFF | IXANY)
        case .hardware: options.c_cflag |= UInt(CRTSCTS)
        case .software: options.c_iflag |= UInt(IXON | IXOFF)
        }
    }

    private func applyDTRRTS(fd: Int32, assertDTR: Bool, assertRTS: Bool) {
        var assertFlags: Int32 = 0
        var deassertFlags: Int32 = 0
        if assertDTR {
            assertFlags |= TIOCM_DTR
        } else {
            deassertFlags |= TIOCM_DTR
        }
        if assertRTS {
            assertFlags |= TIOCM_RTS
        } else {
            deassertFlags |= TIOCM_RTS
        }
        if assertFlags != 0 {
            _ = ioctl(fd, TIOCMBIS, &assertFlags)
        }
        if deassertFlags != 0 {
            _ = ioctl(fd, TIOCMBIC, &deassertFlags)
        }
    }
}

// MARK: - SerialPortError

enum SerialPortError: Error, Sendable, LocalizedError {
    case failedToOpen(path: String, errno: Int32)
    case failedToGetExclusive(path: String)
    case portNotOpen
    case writeFailed(errno: Int32)
    case readFailed(errno: Int32)
    case ioctlFailed(errno: Int32)

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case let .failedToOpen(path, code):
            "Failed to open \(path): \(String(cString: strerror(code))) (errno \(code))"
        case let .failedToGetExclusive(path):
            "Port \(path) is in use by another application"
        case .portNotOpen:
            "Serial port is not open"
        case let .writeFailed(code):
            "Write failed: \(String(cString: strerror(code)))"
        case let .readFailed(code):
            "Read failed: \(String(cString: strerror(code)))"
        case let .ioctlFailed(code):
            "ioctl failed: \(String(cString: strerror(code)))"
        }
    }
}
