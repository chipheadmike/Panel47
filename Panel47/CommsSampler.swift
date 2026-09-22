import Combine
import CoreWLAN
import Darwin
import Foundation

/// Reads network facts from the operating system. Like the process list, the
/// listening-port scan only sees sockets owned by the current user unless the
/// app runs as root.
enum CommsSampler {
    // MARK: Listening ports

    static func readListeningSockets() -> [ListeningSocket] {
        let bytesNeeded = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard bytesNeeded > 0 else { return [] }

        var pids = [pid_t](repeating: 0, count: Int(bytesNeeded) / MemoryLayout<pid_t>.size + 64)
        let bytesFilled = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard bytesFilled > 0 else { return [] }

        var found: [ListeningSocket] = []
        for pid in pids.prefix(Int(bytesFilled) / MemoryLayout<pid_t>.size) where pid > 0 {
            found.append(contentsOf: listeningSockets(of: pid))
        }
        return found
    }

    static func listeningSockets(of pid: pid_t) -> [ListeningSocket] {
        let listSize = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard listSize > 0 else { return [] }

        var descriptors = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(listSize) / MemoryLayout<proc_fdinfo>.stride + 8)
        let filled = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &descriptors, Int32(descriptors.count * MemoryLayout<proc_fdinfo>.stride))
        guard filled > 0 else { return [] }

        var sockets: [ListeningSocket] = []
        var identity: (name: String, uid: UInt32)?

        for descriptor in descriptors.prefix(Int(filled) / MemoryLayout<proc_fdinfo>.stride)
        where descriptor.proc_fdtype == UInt32(PROX_FDTYPE_SOCKET) {
            var info = socket_fdinfo()
            let size = Int32(MemoryLayout<socket_fdinfo>.size)
            guard proc_pidfdinfo(pid, descriptor.proc_fd, PROC_PIDFDSOCKETINFO, &info, size) == size,
                  info.psi.soi_kind == Int32(SOCKINFO_TCP),
                  info.psi.soi_proto.pri_tcp.tcpsi_state == Int32(TSI_S_LISTEN) else { continue }

            let local = info.psi.soi_proto.pri_tcp.tcpsi_ini
            let port = UInt16(bigEndian: UInt16(truncatingIfNeeded: local.insi_lport))
            guard port > 0 else { continue }

            if identity == nil { identity = Self.identity(of: pid) }
            guard let identity else { continue }

            let bytes: [UInt8]
            if local.insi_vflag & UInt8(INI_IPV6) != 0 {
                bytes = withUnsafeBytes(of: local.insi_laddr.ina_6) { Array($0) }
            } else {
                bytes = withUnsafeBytes(of: local.insi_laddr.ina_46.i46a_addr4) { Array($0) }
            }
            sockets.append(ListeningSocket(pid: pid, name: identity.name, uid: identity.uid, port: port, scope: PortScope.classify(bytes)))
        }
        return sockets
    }

    private static func identity(of pid: pid_t) -> (name: String, uid: UInt32)? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }

        var buffer = [CChar](repeating: 0, count: 256)
        proc_name(pid, &buffer, UInt32(buffer.count))
        let name = String(cString: buffer)
        return (name.isEmpty ? "PID \(pid)" : name, info.pbi_uid)
    }

    // MARK: Link

    static func readLink() -> LinkInfo {
        let route = RouteParser.parse(run("/sbin/route", ["-n", "get", "default"]) ?? "")

        var link = LinkInfo(interface: route.interface, address: nil, gateway: route.gateway, isWiFi: false, signalDBm: nil, linkRateMbps: nil)
        if let name = route.interface {
            link.address = ipv4Address(of: name)
            if let wifi = CWWiFiClient.shared().interface(), wifi.interfaceName == name {
                link.isWiFi = true
                // rssiValue is 0 when not associated with a network.
                let rssi = wifi.rssiValue()
                link.signalDBm = rssi < 0 ? rssi : nil
                let rate = wifi.transmitRate()
                link.linkRateMbps = rate > 0 ? rate : nil
            }
        }
        return link
    }

    static func ipv4Address(of interface: String) -> String? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let current = cursor {
            let entry = current.pointee
            if String(cString: entry.ifa_name) == interface,
               let address = entry.ifa_addr,
               address.pointee.sa_family == UInt8(AF_INET) {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                    return String(cString: host)
                }
            }
            cursor = entry.ifa_next
        }
        return nil
    }

    // MARK: Ping

    /// One ICMP echo. Calls back on a background queue with the round trip in
    /// milliseconds, or nil if it was lost.
    static func ping(_ host: String, completion: @escaping (Double?) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            // -c 1: one packet. -t 2: give up after two seconds.
            completion(run("/sbin/ping", ["-c", "1", "-t", "2", host]).flatMap(PingParser.roundTripMilliseconds))
        }
    }

    private static func run(_ path: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        // Read before waiting so a full pipe can't block the child.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }
}

/// Refreshes ports and link details every couple of seconds and pings on a
/// steady beat, but only while the panel is on screen. All the slow reads
/// happen off the main thread.
final class CommsModel: ObservableObject {
    static let historyLength = 30

    @Published private(set) var ports: [ListeningPort] = []
    @Published private(set) var link = LinkInfo(interface: nil, address: nil, gateway: nil, isWiFi: false, signalDBm: nil, linkRateMbps: nil)
    /// One entry per ping, oldest first; nil is a lost packet.
    @Published private(set) var latencyHistory: [Double?] = []
    @Published private(set) var target: PingTarget = .cloudflare
    /// The `ListeningPort.id` whose TERMINATE button has been pressed once.
    @Published private(set) var armedID: String?
    @Published private(set) var notice: String?

    private let socketReader: () -> [ListeningSocket]
    private let linkReader: () -> LinkInfo
    private let pinger: (String, @escaping (Double?) -> Void) -> Void
    private let signaler: (Int32, Int32) -> Int32
    private let ownUID: UInt32
    private let ownPID: Int32

    private let queue = DispatchQueue(label: "panel47.comms", qos: .utility)
    private var timer: Timer?
    private var pingInFlight = false
    /// Bumped on stop/target change so a late ping reply is ignored.
    private var pingGeneration = 0
    private var tickCount = 0

    init(
        socketReader: @escaping () -> [ListeningSocket] = CommsSampler.readListeningSockets,
        linkReader: @escaping () -> LinkInfo = CommsSampler.readLink,
        pinger: @escaping (String, @escaping (Double?) -> Void) -> Void = CommsSampler.ping,
        signaler: @escaping (Int32, Int32) -> Int32 = { kill($0, $1) },
        ownUID: UInt32 = getuid(),
        ownPID: Int32 = ProcessInfo.processInfo.processIdentifier
    ) {
        self.socketReader = socketReader
        self.linkReader = linkReader
        self.pinger = pinger
        self.signaler = signaler
        self.ownUID = ownUID
        self.ownPID = ownPID
    }

    func start() {
        guard timer == nil else { return }
        tickCount = 0
        tick()
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        armedID = nil
        pingGeneration += 1
        pingInFlight = false
    }

    private func tick() {
        // Link details change rarely; ports every tick, link every third.
        let refreshLink = tickCount % 3 == 0
        tickCount += 1

        queue.async { [weak self] in
            guard let self else { return }
            let sockets = self.socketReader()
            let link = refreshLink ? self.linkReader() : nil
            DispatchQueue.main.async {
                self.applyPorts(sockets)
                if let link { self.applyLink(link) }
            }
        }
        pingOnce()
    }

    private func pingOnce() {
        guard !pingInFlight, let host = target.host(gateway: link.gateway) else { return }
        pingInFlight = true
        let generation = pingGeneration
        pinger(host) { [weak self] rtt in
            DispatchQueue.main.async {
                guard let self, generation == self.pingGeneration else { return }
                self.pingInFlight = false
                self.applyPing(rtt)
            }
        }
    }

    // MARK: - Applying readings (main thread)

    func applyPorts(_ sockets: [ListeningSocket]) {
        ports = PortMath.ports(from: sockets, ownUID: ownUID, ownPID: ownPID)
        // The armed port stopped listening, so there is nothing left to confirm.
        if let armed = armedID, !ports.contains(where: { $0.id == armed }) {
            armedID = nil
        }
    }

    func applyLink(_ newLink: LinkInfo) {
        link = newLink
    }

    func applyPing(_ roundTrip: Double?) {
        latencyHistory.append(roundTrip)
        if latencyHistory.count > Self.historyLength {
            latencyHistory.removeFirst(latencyHistory.count - Self.historyLength)
        }
    }

    func setTarget(_ newTarget: PingTarget) {
        guard newTarget != target else { return }
        target = newTarget
        latencyHistory = []
        pingGeneration += 1
        pingInFlight = false
        if timer != nil { pingOnce() }
    }

    // MARK: - Termination

    func arm(_ id: String) {
        guard ports.first(where: { $0.id == id })?.canTerminate == true else { return }
        notice = nil
        armedID = id
    }

    func cancel() {
        armedID = nil
    }

    /// Sends SIGTERM to the process that owns the armed port.
    func confirmTerminate(_ id: String) {
        guard armedID == id,
              let entry = ports.first(where: { $0.id == id }),
              entry.canTerminate else { return }
        armedID = nil

        let result = signaler(entry.pid, SIGTERM)
        let failure = errno
        if result == 0 {
            notice = "TERMINATION SIGNAL SENT TO \(entry.name.uppercased()) ON PORT \(entry.port)"
        } else {
            notice = "COULD NOT TERMINATE \(entry.name.uppercased()): \(String(cString: strerror(failure)).uppercased())"
        }
    }
}
