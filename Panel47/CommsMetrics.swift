import Foundation

/// How widely a listening socket can be reached.
enum PortScope: Equatable {
    /// Bound to every interface (`*:80`): reachable from other machines.
    case allInterfaces
    /// Bound to 127.0.0.1 / ::1: only this Mac can connect.
    case loopbackOnly
    /// Bound to one specific address.
    case specific

    /// Classifies a raw IPv4 (4 bytes) or IPv6 (16 bytes) address.
    static func classify(_ bytes: [UInt8]) -> PortScope {
        if bytes.allSatisfy({ $0 == 0 }) { return .allInterfaces }
        if bytes.count == 4, bytes[0] == 127 { return .loopbackOnly }
        if bytes.count == 16, bytes.dropLast().allSatisfy({ $0 == 0 }), bytes.last == 1 { return .loopbackOnly }
        return .specific
    }

    /// The most exposed of two scopes, for a socket listening on both IPv4 and IPv6.
    func widest(with other: PortScope) -> PortScope {
        func rank(_ scope: PortScope) -> Int {
            switch scope {
            case .loopbackOnly: return 0
            case .specific: return 1
            case .allInterfaces: return 2
            }
        }
        return rank(self) >= rank(other) ? self : other
    }
}

/// One raw TCP listener found on a process.
struct ListeningSocket: Equatable {
    let pid: Int32
    let name: String
    let uid: UInt32
    let port: UInt16
    let scope: PortScope
}

/// A listening port, ready to display. Several processes sharing one socket
/// (a web server and its workers) collapse into a single entry.
struct ListeningPort: Equatable, Identifiable {
    var id: String { "\(port)-\(name)" }
    let port: UInt16
    let name: String
    let scope: PortScope
    /// The lowest pid among the sharers — for a server, its parent.
    let pid: Int32
    let processCount: Int
    let canTerminate: Bool
}

enum PortMath {
    static func ports(from sockets: [ListeningSocket], ownUID: UInt32, ownPID: Int32) -> [ListeningPort] {
        struct Key: Hashable { let port: UInt16; let name: String }
        var grouped: [Key: [ListeningSocket]] = [:]
        for socket in sockets {
            grouped[Key(port: socket.port, name: socket.name), default: []].append(socket)
        }

        return grouped.map { key, group in
            let pids = Set(group.map(\.pid))
            let lowest = group.filter { $0.pid == pids.min() }
            return ListeningPort(
                port: key.port,
                name: key.name,
                scope: group.dropFirst().reduce(group[0].scope) { $0.widest(with: $1.scope) },
                pid: pids.min() ?? 0,
                processCount: pids.count,
                canTerminate: lowest.first.map {
                    TerminationRules.canTerminate(pid: $0.pid, uid: $0.uid, ownUID: ownUID, ownPID: ownPID)
                } ?? false
            )
        }
        .sorted { ($0.port, $0.name) < ($1.port, $1.name) }
    }
}

// MARK: - Latency

enum PingParser {
    /// Round-trip time in milliseconds from `ping` output, or nil if the
    /// packet was lost.
    static func roundTripMilliseconds(_ output: String) -> Double? {
        guard let range = output.range(of: #"time[=<]\s*([0-9]+(?:\.[0-9]+)?)\s*ms"#, options: .regularExpression) else {
            return nil
        }
        let match = output[range]
        guard let numberRange = match.range(of: #"[0-9]+(?:\.[0-9]+)?"#, options: .regularExpression) else { return nil }
        return Double(match[numberRange])
    }
}

struct LatencyStats: Equatable {
    let last: Double?
    let average: Double?
    let lossFraction: Double

    /// `samples` holds one entry per ping; nil means the packet was lost.
    init(samples: [Double?]) {
        let answered = samples.compactMap { $0 }
        last = samples.last ?? nil
        average = answered.isEmpty ? nil : answered.reduce(0, +) / Double(answered.count)
        lossFraction = samples.isEmpty ? 0 : Double(samples.count - answered.count) / Double(samples.count)
    }
}

enum LatencyLevel {
    /// Under 50 ms is fine, under 150 ms is noticeable, beyond that is poor.
    static func level(forMilliseconds ms: Double) -> GaugeLevel {
        if ms >= 150 { return .critical }
        if ms >= 50 { return .warning }
        return .normal
    }
}

// MARK: - Link

struct RouteInfo: Equatable {
    var gateway: String?
    var interface: String?
}

enum RouteParser {
    /// Parses `route -n get default`.
    static func parse(_ output: String) -> RouteInfo {
        var info = RouteInfo()
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            switch parts[0] {
            case "gateway": info.gateway = parts[1]
            case "interface": info.interface = parts[1]
            default: break
            }
        }
        return info
    }
}

struct LinkInfo: Equatable {
    var interface: String?
    var address: String?
    var gateway: String?
    var isWiFi: Bool
    /// Received signal strength in dBm; nil unless on Wi-Fi and associated.
    var signalDBm: Int?
    var linkRateMbps: Double?
}

enum SignalQuality {
    /// Maps -90 dBm (unusable) … -30 dBm (right next to the router) onto 0…1.
    static func fraction(dBm: Int) -> Double {
        min(1, max(0, Double(dBm + 90) / 60))
    }

    static func label(dBm: Int) -> String {
        switch dBm {
        case (-55)...: return "EXCELLENT"
        case (-67)...: return "GOOD"
        case (-75)...: return "FAIR"
        default: return "POOR"
        }
    }
}

enum PingTarget: Equatable, CaseIterable {
    case cloudflare, google, gateway

    var title: String {
        switch self {
        case .cloudflare: return "1.1.1.1"
        case .google: return "8.8.8.8"
        case .gateway: return "GATEWAY"
        }
    }

    /// The address to ping, given the current default gateway.
    func host(gateway: String?) -> String? {
        switch self {
        case .cloudflare: return "1.1.1.1"
        case .google: return "8.8.8.8"
        case .gateway: return gateway
        }
    }
}
