import CoreLocation
import Foundation
import SwiftUI

/// Polls the walker's active walk once a second.
@MainActor
final class WalkerStore: ObservableObject {
    let me = "jordan"
    @Published var walk: Walk?
    @Published var user: UserInfo?
    @Published var routes: [RouteInfo] = []
    @Published var error: String?
    @Published var evolvedTo: String?
    @Published var happy = false
    private var loop: Task<Void, Never>?
    private var lastState: String?
    private let location = LocationTicker()

    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            if let r = try? await API.shared.routes() { self?.routes = r }
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    func stop() { loop?.cancel(); loop = nil; location.stop() }

    func refresh() async {
        do {
            let w = try await API.shared.active(me)
            if w == nil { user = try await API.shared.user(me) }
            apply(w)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func apply(_ w: Walk?) {
        // A route planned on a phone appears after launch: fetch routes again when one is unknown.
        if let rid = w?.routeId, !routes.contains(where: { $0.id == rid }) {
            Task { if let r = try? await API.shared.routes() { self.routes = r } }
        }
        let st = w?.engine.state
        if let st, st != lastState, st != "calm" { Haptics.warning() }
        lastState = st
        walk = w
        // Every active walk (demo too) runs location so the app stays alive with the screen locked
        // and keeps the Live Activity current. Only real walks send GPS fixes to the server.
        if let w, w.status == "active" { location.start(walkId: w.id, sendFixes: !w.demo) } else { location.stop() }
    }

    func pet() async {
        Haptics.tap()
        guard let w = walk else { beHappy(); return }
        do {
            let r = try await API.shared.pet(w.id)
            apply(r.walk)
            if r.events.contains(where: { $0.type == "pet_ok" }) { Haptics.success(); beHappy() }
            if let evo = r.events.first(where: { $0.evolved != nil })?.evolved {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { evolvedTo = evo }
            }
        } catch { self.error = error.localizedDescription }
    }

    func duress() async {
        guard let w = walk else { return }
        // Silent: the screen must not change in any visible way.
        if let r = try? await API.shared.duress(w.id) { walk = r.walk }
    }

    func startPlanned(points: [[Double]], from: String, to: String, demo: Bool) async {
        guard points.count > 1 else { return }
        do {
            let w = try await API.shared.startPlanned(me, points: points, from: from, to: to, demo: demo)
            routes = (try? await API.shared.routes()) ?? routes
            apply(w)
        } catch { self.error = error.localizedDescription }
    }

    func startReal(_ route: String) async {
        if let w = try? await API.shared.startWalk(me, route: route) { apply(w) }
    }

    func end() async {
        guard let w = walk else { return }
        if let v = try? await API.shared.end(w.id) { apply(v.status == "active" ? v : nil) }
    }

    private func beHappy() {
        happy = true
        Task { try? await Task.sleep(nanoseconds: 1_800_000_000); happy = false }
    }
}

/// Polls the friend's feed every 1.5 s and drives the alert takeover.
@MainActor
final class FriendStore: ObservableObject {
    let me = "maya"
    @Published var feed: Feed?
    @Published var routes: [RouteInfo] = []
    @Published var error: String?
    @Published var busy: String?
    private var loop: Task<Void, Never>?
    private var buzz: Task<Void, Never>?

    var alert: AlertInfo? { feed?.openAlerts.first }

    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            if let r = try? await API.shared.routes() { self?.routes = r }
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
        }
    }

    func stop() { loop?.cancel(); loop = nil; buzz?.cancel(); buzz = nil }

    func refresh() async {
        do {
            let f = try await API.shared.feed(me)
            if let rid = f.walks.first?.routeId, !routes.contains(where: { $0.id == rid }) {
                routes = (try? await API.shared.routes()) ?? routes
            }
            let hadAlert = alert != nil
            feed = f
            error = nil
            if alert != nil && !hadAlert { startBuzz() }
            if alert == nil { buzz?.cancel(); buzz = nil }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func startBuzz() {
        buzz?.cancel()
        buzz = Task {
            while !Task.isCancelled {
                Haptics.warning()
                try? await Task.sleep(nanoseconds: 900_000_000)
            }
        }
    }

    func act(_ key: String, _ fn: @escaping () async throws -> Void) async {
        busy = key
        do { try await fn(); error = nil } catch { self.error = error.localizedDescription }
        busy = nil
        await refresh()
    }

    func close(_ a: AlertInfo) async {
        await act("close") { _ = try await API.shared.closeAlert(a.id, friend: self.me) }
        Haptics.success()
    }
}

/// Real (non-demo) walks: GPS fixes plus a 20 s heartbeat even without a fix.
final class LocationTicker: NSObject, CLLocationManagerDelegate {
    private let mgr = CLLocationManager()
    private var walkId: String?
    private var sendFixes = true
    private var heartbeat: Timer?

    override init() {
        super.init()
        mgr.delegate = self
        mgr.desiredAccuracy = kCLLocationAccuracyBest
        mgr.distanceFilter = 5
        mgr.pausesLocationUpdatesAutomatically = false
        mgr.activityType = .fitness
    }

    func start(walkId id: String, sendFixes: Bool) {
        guard walkId != id else { return }
        walkId = id
        self.sendFixes = sendFixes
        mgr.requestWhenInUseAuthorization()
        mgr.allowsBackgroundLocationUpdates = true
        mgr.showsBackgroundLocationIndicator = true
        mgr.startUpdatingLocation()
        heartbeat?.invalidate()
        heartbeat = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            guard let self, self.sendFixes, let id = self.walkId else { return }
            Task { try? await API.shared.tick(id) }
        }
    }

    func stop() {
        walkId = nil
        mgr.stopUpdatingLocation()
        heartbeat?.invalidate()
        heartbeat = nil
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard sendFixes, let id = walkId, let l = locations.last else { return }
        Task { try? await API.shared.tick(id, lat: l.coordinate.latitude, lng: l.coordinate.longitude, accuracy: l.horizontalAccuracy) }
    }
}
