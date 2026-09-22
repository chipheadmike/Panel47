import Darwin
import Foundation
import Testing
@testable import Panel47

struct PortMathTests {
    private func socket(_ pid: Int32, _ name: String, _ port: UInt16, _ scope: PortScope = .allInterfaces, uid: UInt32 = 501) -> ListeningSocket {
        ListeningSocket(pid: pid, name: name, uid: uid, port: port, scope: scope)
    }

    @Test func addressesAreClassified() {
        #expect(PortScope.classify([0, 0, 0, 0]) == .allInterfaces)
        #expect(PortScope.classify([UInt8](repeating: 0, count: 16)) == .allInterfaces)
        #expect(PortScope.classify([127, 0, 0, 1]) == .loopbackOnly)
        #expect(PortScope.classify([UInt8](repeating: 0, count: 15) + [1]) == .loopbackOnly)
        #expect(PortScope.classify([192, 168, 8, 204]) == .specific)
    }

    @Test func aWorkerPoolOnOnePortCollapsesToItsParent() {
        let sockets = [socket(1145, "httpd", 80), socket(901, "httpd", 80), socket(1142, "httpd", 80)]
        let ports = PortMath.ports(from: sockets, ownUID: 501, ownPID: 9999)
        #expect(ports.count == 1)
        #expect(ports[0].pid == 901)
        #expect(ports[0].processCount == 3)
    }

    @Test func listeningOnIPv4AndIPv6ShowsTheWiderScope() {
        let sockets = [socket(5, "node", 3000, .loopbackOnly), socket(5, "node", 3000, .allInterfaces)]
        let ports = PortMath.ports(from: sockets, ownUID: 501, ownPID: 9999)
        #expect(ports.count == 1)
        #expect(ports[0].scope == .allInterfaces)
        #expect(ports[0].processCount == 1)
    }

    @Test func differentProgramsOnTheSamePortStaySeparate() {
        let sockets = [socket(5, "node", 8080, .loopbackOnly), socket(6, "java", 8080, .allInterfaces)]
        let ports = PortMath.ports(from: sockets, ownUID: 501, ownPID: 9999)
        #expect(ports.count == 2)
        #expect(Set(ports.map(\.id)).count == 2)
    }

    @Test func portsAreSortedByNumber() {
        let ports = PortMath.ports(from: [socket(1, "b", 9000), socket(2, "a", 80), socket(3, "c", 3000)], ownUID: 501, ownPID: 9999)
        #expect(ports.map(\.port) == [80, 3000, 9000])
    }

    @Test func terminationRulesApplyToPortOwners() {
        let ports = PortMath.ports(
            from: [socket(500, "mine", 1), socket(1, "launchd", 2), socket(9999, "panel47", 3), socket(700, "theirs", 4, uid: 0)],
            ownUID: 501, ownPID: 9999
        )
        #expect(ports.map(\.canTerminate) == [true, false, false, false])
    }
}

struct CommsParserTests {
    @Test func pingTimeIsParsedFromRealOutput() {
        let output = """
        PING 1.1.1.1 (1.1.1.1): 56 data bytes
        64 bytes from 1.1.1.1: icmp_seq=0 ttl=57 time=12.345 ms

        --- 1.1.1.1 ping statistics ---
        1 packets transmitted, 1 packets received, 0.0% packet loss
        """
        #expect(PingParser.roundTripMilliseconds(output) == 12.345)
        #expect(PingParser.roundTripMilliseconds("64 bytes from 192.168.8.1: icmp_seq=0 ttl=64 time=0.9 ms") == 0.9)
    }

    @Test func aLostPacketHasNoRoundTrip() {
        let output = "PING 10.255.255.1: 56 data bytes\n\n--- ping statistics ---\n1 packets transmitted, 0 packets received, 100.0% packet loss"
        #expect(PingParser.roundTripMilliseconds(output) == nil)
        #expect(PingParser.roundTripMilliseconds("") == nil)
    }

    @Test func routeOutputYieldsGatewayAndInterface() {
        let output = """
           route to: default
        destination: default
               mask: default
            gateway: 192.168.8.1
          interface: en4
              flags: <UP,GATEWAY,DONE,STATIC,PRCLONING,GLOBAL>
        """
        let info = RouteParser.parse(output)
        #expect(info.gateway == "192.168.8.1")
        #expect(info.interface == "en4")
        #expect(RouteParser.parse("route: writing to routing socket: not in table") == RouteInfo())
    }

    @Test func latencyStatsCountLostPackets() {
        let stats = LatencyStats(samples: [10, nil, 30, 20])
        #expect(stats.last == 20)
        #expect(stats.average == 20)
        #expect(stats.lossFraction == 0.25)
        #expect(LatencyStats(samples: [5, nil]).last == nil)
        #expect(LatencyStats(samples: []).average == nil)
    }

    @Test func latencyLevelsFollowThresholds() {
        #expect(LatencyLevel.level(forMilliseconds: 12) == .normal)
        #expect(LatencyLevel.level(forMilliseconds: 50) == .warning)
        #expect(LatencyLevel.level(forMilliseconds: 150) == .critical)
    }

    @Test func signalStrengthMapsToQuality() {
        #expect(SignalQuality.fraction(dBm: -90) == 0)
        #expect(SignalQuality.fraction(dBm: -30) == 1)
        #expect(SignalQuality.fraction(dBm: -120) == 0)
        #expect(SignalQuality.label(dBm: -50) == "EXCELLENT")
        #expect(SignalQuality.label(dBm: -60) == "GOOD")
        #expect(SignalQuality.label(dBm: -70) == "FAIR")
        #expect(SignalQuality.label(dBm: -85) == "POOR")
    }

    @Test func gatewayTargetNeedsAKnownGateway() {
        #expect(PingTarget.gateway.host(gateway: nil) == nil)
        #expect(PingTarget.gateway.host(gateway: "192.168.8.1") == "192.168.8.1")
        #expect(PingTarget.cloudflare.host(gateway: nil) == "1.1.1.1")
    }
}

@MainActor
struct CommsModelTests {
    private func model(signal: @escaping (Int32, Int32) -> Int32 = { _, _ in 0 }) -> CommsModel {
        let model = CommsModel(signaler: signal, ownUID: 501, ownPID: 9999)
        model.applyPorts([
            ListeningSocket(pid: 300, name: "node", uid: 501, port: 3000, scope: .loopbackOnly),
            ListeningSocket(pid: 1, name: "launchd", uid: 501, port: 22, scope: .allInterfaces),
        ])
        return model
    }

    @Test func terminationNeedsArmingFirst() throws {
        var signals: [(Int32, Int32)] = []
        let model = model { signals.append(($0, $1)); return 0 }
        let id = try #require(model.ports.first { $0.port == 3000 }?.id)

        model.confirmTerminate(id)
        #expect(signals.isEmpty)

        model.arm(id)
        model.confirmTerminate(id)
        #expect(signals.count == 1)
        #expect(signals[0].0 == 300 && signals[0].1 == SIGTERM)
        #expect(model.armedID == nil)
        #expect(model.notice == "TERMINATION SIGNAL SENT TO NODE ON PORT 3000")
    }

    @Test func protectedOwnersCannotBeArmed() throws {
        var signals = 0
        let model = model { _, _ in signals += 1; return 0 }
        let id = try #require(model.ports.first { $0.port == 22 }?.id)
        model.arm(id)
        #expect(model.armedID == nil)
        model.confirmTerminate(id)
        #expect(signals == 0)
    }

    @Test func aPortThatStopsListeningIsDisarmed() throws {
        let model = model()
        let id = try #require(model.ports.first { $0.port == 3000 }?.id)
        model.arm(id)
        model.applyPorts([])
        #expect(model.armedID == nil)
    }

    @Test func aFailedSignalIsReported() throws {
        let model = model { _, _ in -1 }
        let id = try #require(model.ports.first { $0.port == 3000 }?.id)
        model.arm(id)
        model.confirmTerminate(id)
        #expect(model.notice?.hasPrefix("COULD NOT TERMINATE NODE") == true)
    }

    @Test func pingHistoryIsCappedAndClearedWhenTheTargetChanges() {
        let model = model()
        for i in 0..<(CommsModel.historyLength + 5) { model.applyPing(Double(i)) }
        #expect(model.latencyHistory.count == CommsModel.historyLength)
        #expect(model.latencyHistory.last == Double(CommsModel.historyLength + 4))
        model.setTarget(.google)
        #expect(model.latencyHistory.isEmpty)
    }
}

/// These open real sockets in this process and check the scanner sees them.
struct LiveCommsTests {
    /// Listens on an ephemeral port on the given IPv4 address; returns the fd and port.
    private func listen(on address: UInt32) throws -> (fd: Int32, port: UInt16) {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        try #require(fd >= 0)

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr.s_addr = address.bigEndian

        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        try #require(bound == 0)
        try #require(Darwin.listen(fd, 1) == 0)

        var actual = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &actual) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
        }
        return (fd, UInt16(bigEndian: actual.sin_port))
    }

    @Test func aRealLoopbackListenerIsFoundWithTheRightPortAndScope() throws {
        let (fd, port) = try listen(on: INADDR_LOOPBACK)
        defer { close(fd) }

        let me = ProcessInfo.processInfo.processIdentifier
        let found = CommsSampler.listeningSockets(of: me).first { $0.port == port }
        let socket = try #require(found)
        #expect(socket.pid == me)
        #expect(socket.scope == .loopbackOnly)
        #expect(socket.uid == getuid())
    }

    @Test func aRealWildcardListenerIsFoundAsAllInterfaces() throws {
        let (fd, port) = try listen(on: INADDR_ANY)
        defer { close(fd) }

        let found = CommsSampler.listeningSockets(of: ProcessInfo.processInfo.processIdentifier).first { $0.port == port }
        #expect(try #require(found).scope == .allInterfaces)
    }

    @Test func aClosedListenerDisappears() throws {
        let (fd, port) = try listen(on: INADDR_LOOPBACK)
        close(fd)
        #expect(!CommsSampler.listeningSockets(of: ProcessInfo.processInfo.processIdentifier).contains { $0.port == port })
    }

    @Test func theFullScanIncludesThisProcess() throws {
        let (fd, port) = try listen(on: INADDR_LOOPBACK)
        defer { close(fd) }
        #expect(CommsSampler.readListeningSockets().contains { $0.port == port })
    }

    @Test func theDefaultRouteAndAddressAreReadable() {
        let link = CommsSampler.readLink()
        // Offline is legitimate; when a route exists, its address must be a dotted quad.
        if let interface = link.interface {
            #expect(link.gateway != nil)
            if let address = CommsSampler.ipv4Address(of: interface) {
                #expect(address.split(separator: ".").count == 4)
            }
        }
    }

    @Test func terminatingARealListeningProcessEndToEnd() async throws {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        child.arguments = ["python3", "-c", "import socket,time; s=socket.socket(); s.bind(('127.0.0.1',0)); s.listen(1); print(s.getsockname()[1], flush=True); time.sleep(60)"]
        let out = Pipe()
        child.standardOutput = out
        try child.run()
        defer { if child.isRunning { child.terminate() } }

        // Wait for the child to report the port it is listening on.
        let line = String(data: out.fileHandleForReading.availableData, encoding: .utf8) ?? ""
        let port = try #require(UInt16(line.trimmingCharacters(in: .whitespacesAndNewlines)))

        let model = await MainActor.run { CommsModel() }
        try await MainActor.run {
            model.applyPorts(CommsSampler.readListeningSockets())
            let entry = try #require(model.ports.first { $0.port == port })
            #expect(entry.scope == .loopbackOnly)
            #expect(entry.canTerminate)

            model.confirmTerminate(entry.id) // not armed: must do nothing
            #expect(child.isRunning)
            model.arm(entry.id)
            model.confirmTerminate(entry.id)
        }
        child.waitUntilExit()
        #expect(child.terminationReason == .uncaughtSignal)
        #expect(child.terminationStatus == SIGTERM)
    }

    @Test func aLoopbackPingReturnsQuickly() async throws {
        let rtt = await withCheckedContinuation { continuation in
            CommsSampler.ping("127.0.0.1") { continuation.resume(returning: $0) }
        }
        let value = try #require(rtt)
        #expect(value >= 0 && value < 50)
    }
}
