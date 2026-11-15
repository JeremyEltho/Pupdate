import CoreLocation
import MapKit
import SwiftUI

/// Destination search + Apple walking directions.
@MainActor
final class PlanModel: NSObject, ObservableObject, MKLocalSearchCompleterDelegate, CLLocationManagerDelegate {
    @Published var query = "" { didSet { completer.queryFragment = query } }
    @Published var suggestions: [MKLocalSearchCompletion] = []
    @Published var start = CLLocationCoordinate2D(latitude: 33.41955, longitude: -111.93455) // Hayden Library fallback
    @Published var startName = "Hayden Library"
    @Published var destination: MKMapItem?
    @Published var route: MKRoute?
    @Published var routing = false
    @Published var error: String?
    private let completer = MKLocalSearchCompleter()
    private let loc = CLLocationManager()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.pointOfInterest, .address]
        completer.region = MKCoordinateRegion(center: start, latitudinalMeters: 6000, longitudinalMeters: 6000)
        loc.delegate = self
        loc.requestWhenInUseAuthorization()
        loc.requestLocation()
    }

    nonisolated func completerDidUpdateResults(_ c: MKLocalSearchCompleter) {
        let r = Array(c.results.prefix(6))
        Task { @MainActor in self.suggestions = r }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {}

    nonisolated func locationManager(_ m: CLLocationManager, didUpdateLocations l: [CLLocation]) {
        guard let c = l.last?.coordinate else { return }
        Task { @MainActor in
            // Only use the real location when it is plausibly near campus; otherwise keep the demo start.
            let here = CLLocation(latitude: c.latitude, longitude: c.longitude)
            if here.distance(from: CLLocation(latitude: 33.4196, longitude: -111.9346)) < 20000 {
                self.start = c
                self.startName = "Current location"
                self.completer.region = MKCoordinateRegion(center: c, latitudinalMeters: 6000, longitudinalMeters: 6000)
            }
        }
    }

    nonisolated func locationManager(_ m: CLLocationManager, didFailWithError e: Error) {}

    func pick(_ s: MKLocalSearchCompletion) async {
        await search(MKLocalSearch.Request(completion: s))
    }

    func pick(name: String) async {
        let r = MKLocalSearch.Request()
        r.naturalLanguageQuery = name
        r.region = MKCoordinateRegion(center: start, latitudinalMeters: 8000, longitudinalMeters: 8000)
        await search(r)
    }

    private func search(_ req: MKLocalSearch.Request) async {
        error = nil
        do {
            let res = try await MKLocalSearch(request: req).start()
            guard let item = res.mapItems.first else { error = "No place found"; return }
            destination = item
            query = item.name ?? query
            suggestions = []
            await directions()
        } catch {
            self.error = "Search failed. Check your connection."
        }
    }

    func directions() async {
        guard let dest = destination else { return }
        routing = true
        defer { routing = false }
        let req = MKDirections.Request()
        req.source = MKMapItem(placemark: MKPlacemark(coordinate: start))
        req.destination = dest
        req.transportType = .walking
        do {
            route = try await MKDirections(request: req).calculate().routes.first
            if route == nil { error = "No walking route found" }
        } catch {
            route = nil
            self.error = "Couldn't get walking directions."
        }
    }

    /// Route polyline as [[lat, lng]], thinned to keep the payload small.
    var points: [[Double]] {
        guard let poly = route?.polyline else { return [] }
        var coords = [CLLocationCoordinate2D](repeating: .init(), count: poly.pointCount)
        poly.getCoordinates(&coords, range: NSRange(location: 0, length: poly.pointCount))
        let step = max(1, coords.count / 120)
        var out = stride(from: 0, to: coords.count, by: step).map { [$0 == 0 ? coords[0].latitude : coords[$0].latitude, coords[$0].longitude] }
        if let last = coords.last { out.append([last.latitude, last.longitude]) }
        return out
    }
}

struct PlanView: View {
    @ObservedObject var store: WalkerStore
    let onClose: () -> Void
    var preset: String?
    @StateObject private var plan = PlanModel()
    @State private var camera: MapCameraPosition = .automatic
    @State private var demo = true
    @State private var starting = false
    @FocusState private var focused: Bool

    private let quick = ["Tooker House", "Vista del Sol", "Memorial Union", "Tempe Town Lake"]

    var body: some View {
        ZStack(alignment: .top) {
            Map(position: $camera) {
                Annotation("Start", coordinate: plan.start, anchor: .center) {
                    ZStack {
                        Circle().fill(.white).frame(width: 26, height: 26)
                        Circle().fill(Palette.sky).frame(width: 18, height: 18)
                    }
                    .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
                }
                if let r = plan.route {
                    MapPolyline(r.polyline).stroke(Color(hex: 0x3a2a00).opacity(0.5), style: StrokeStyle(lineWidth: 11, lineCap: .round, lineJoin: .round))
                    MapPolyline(r.polyline).stroke(Palette.gold, style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                }
                if let d = plan.destination {
                    Annotation(d.name ?? "", coordinate: d.placemark.coordinate, anchor: .bottom) {
                        Sprite.house.image.resizable().scaledToFit().frame(width: 46, height: 46)
                            .shadow(color: .black.opacity(0.4), radius: 5, y: 4)
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic, emphasis: .muted, pointsOfInterest: .excludingAll))
            .mapControlVisibility(.hidden)
            .ignoresSafeArea()
            .onAppear { camera = .camera(MapCamera(centerCoordinate: plan.start, distance: 2200, heading: 0, pitch: 50)) }
            .onChange(of: plan.route) { _, r in
                guard let r else { return }
                // Frame the route in the band between the search bar and the trip sheet.
                let b = r.polyline.boundingMapRect
                let w = max(b.width, b.height * 0.6), h = max(b.height, b.width * 0.6)
                let framed = MKMapRect(x: b.midX - w * 0.85, y: b.minY - h * 0.45, width: w * 1.7, height: h * 2.6)
                withAnimation(.easeInOut(duration: 1.2)) { camera = .rect(framed) }
            }

            // Top: back + search.
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Button(action: onClose) {
                        Image(systemName: "chevron.left").font(.system(size: 16, weight: .heavy)).foregroundStyle(Palette.text)
                            .frame(width: 46, height: 46)
                            .background(Circle().fill(Palette.card))
                            .overlay(Circle().strokeBorder(Palette.lineTop))
                    }
                    .accessibilityLabel("Back")
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").font(.system(size: 16, weight: .bold)).foregroundStyle(Palette.gold)
                        TextField("", text: $plan.query, prompt: Text("Where to tonight?").foregroundStyle(Palette.muted))
                            .font(Typeface.semi(17)).foregroundStyle(Palette.text)
                            .focused($focused).submitLabel(.search)
                            .onSubmit { Task { await plan.pick(name: plan.query) } }
                        if !plan.query.isEmpty {
                            Button { plan.query = ""; plan.route = nil; plan.destination = nil } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.muted)
                            }
                        }
                    }
                    .padding(.horizontal, 16).frame(height: 52)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Palette.card))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(focused ? Palette.gold : Palette.lineTop, lineWidth: focused ? 1.5 : 1))
                    .shadow(color: .black.opacity(0.45), radius: 16, y: 8)
                }
                if focused && !plan.suggestions.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(plan.suggestions.enumerated()), id: \.offset) { i, s in
                            Button {
                                focused = false
                                Task { await plan.pick(s) }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "mappin.circle.fill").font(.system(size: 22)).foregroundStyle(Palette.gold)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(s.title).font(Typeface.semi(16)).foregroundStyle(Palette.text).lineLimit(1)
                                        if !s.subtitle.isEmpty { Text(s.subtitle).font(Typeface.body(13)).foregroundStyle(Palette.muted).lineLimit(1) }
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 16).padding(.vertical, 11)
                            }
                            if i < plan.suggestions.count - 1 { Divider().overlay(Palette.line) }
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Palette.card))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Palette.lineTop))
                    .shadow(color: .black.opacity(0.45), radius: 16, y: 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                } else if plan.destination == nil {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(quick, id: \.self) { q in
                                Button { Task { await plan.pick(name: q) } } label: {
                                    HStack(spacing: 6) {
                                        Sprite.house.image.resizable().scaledToFit().frame(width: 20, height: 20)
                                        Text(q).font(Typeface.semi(14)).foregroundStyle(Palette.text)
                                    }
                                    .padding(.horizontal, 12).padding(.vertical, 9)
                                    .background(Capsule().fill(Palette.card))
                                    .overlay(Capsule().strokeBorder(Palette.lineTop))
                                }
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                }
            }
            .padding(.horizontal, 16).padding(.top, 8)
            .animation(.easeInOut(duration: 0.2), value: focused)

            // Bottom sheet: the trip and the start button.
            VStack {
                Spacer()
                if let d = plan.destination {
                    TripSheet(name: d.name ?? "Destination", address: d.placemark.title, route: plan.route, routing: plan.routing,
                              demo: $demo, starting: starting, buddyForm: store.user?.buddy.form ?? "sprout",
                              buddyName: store.user?.buddy.name ?? "Levin") {
                        Task {
                            starting = true
                            await store.startPlanned(points: plan.points, from: plan.startName, to: d.name ?? "Destination", demo: demo)
                            starting = false
                            onClose()
                        }
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if let e = plan.error {
                    Banner(text: e, alert: true).padding(16)
                }
            }
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: plan.destination)
        }
        .background(Palette.bg)
        .task {
            if let preset { await plan.pick(name: preset) } else { focused = true }
        }
    }
}

private struct TripSheet: View {
    let name: String
    let address: String?
    let route: MKRoute?
    let routing: Bool
    @Binding var demo: Bool
    let starting: Bool
    let buddyForm: String
    let buddyName: String
    let go: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Capsule().fill(Palette.line).frame(width: 40, height: 5).frame(maxWidth: .infinity)
            HStack(alignment: .top, spacing: 14) {
                formSprite(buddyForm).image.resizable().scaledToFit().frame(width: 64, height: 64)
                    .background(Circle().fill(Palette.gold.opacity(0.14)))
                VStack(alignment: .leading, spacing: 3) {
                    Text(name).font(Typeface.display(26)).foregroundStyle(Palette.text).lineLimit(2)
                    if let address { Text(address).font(Typeface.body(14)).foregroundStyle(Palette.muted).lineLimit(1) }
                }
            }
            HStack(spacing: 10) {
                TripStat(icon: "figure.walk", value: route.map { formatDistance($0.distance) } ?? (routing ? "..." : "--"), label: "distance")
                TripStat(icon: "clock.fill", value: route.map { "\(Int(($0.expectedTravelTime / 60).rounded())) min" } ?? (routing ? "..." : "--"), label: "walk")
                TripStat(icon: "shield.lefthalf.filled", value: "2", label: "watching")
            }
            Toggle(isOn: $demo) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Demo walk").font(Typeface.semi(16)).foregroundStyle(Palette.text)
                    Text("Simulates the walk at 2x instead of using your GPS").font(Typeface.body(13)).foregroundStyle(Palette.muted)
                }
            }
            .tint(Palette.gold)
            GameButton(title: "Walk with \(buddyName)", busy: starting || routing, action: go)
                .disabled(route == nil)
        }
        .padding(20)
        .padding(.bottom, 8)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30, style: .continuous)
                .fill(LinearGradient(colors: [Palette.card2, Palette.card], startPoint: .top, endPoint: .bottom))
                .ignoresSafeArea(edges: .bottom)
        )
        .overlay(
            UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30, style: .continuous)
                .strokeBorder(Palette.lineTop, lineWidth: 1).ignoresSafeArea(edges: .bottom)
        )
        .shadow(color: .black.opacity(0.5), radius: 24, y: -6)
    }
}

private struct TripStat: View {
    let icon: String
    let value: String
    let label: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: icon).font(.system(size: 14, weight: .bold)).foregroundStyle(Palette.gold)
            Text(value).font(Typeface.display(19)).foregroundStyle(Palette.text).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(Typeface.body(12)).foregroundStyle(Palette.muted).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(hex: 0x0f1433)))
    }
}

func formatDistance(_ m: Double) -> String { m >= 1000 ? String(format: "%.1f km", m / 1000) : "\(Int(m)) m" }
