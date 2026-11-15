import CoreLocation
import MapKit
import SwiftUI

enum RouteChoice: String { case safe, quick }

/// Share of a route's distance on main named streets or campus malls, minus a small cost per turn,
/// minus a penalty for paths, alleys, trails and parking lots. A heuristic: no crime or lighting data.
func safetyScore(_ r: MKRoute) -> Double {
    let main = ["Dr", "Ave", "Blvd", "St", "Rd", "Pkwy", "Way", "Mall", "Street", "Avenue", "Drive", "Road"]
    let risky = ["path", "trail", "alley", "parking", "lot", "walkway", "footpath", "service"]
    var mainDist = 0.0, riskyDist = 0.0
    for step in r.steps {
        let text = step.instructions
        let words = text.split(separator: " ").map(String.init)
        if words.contains(where: { main.contains($0.trimmingCharacters(in: .punctuationCharacters)) }) { mainDist += step.distance }
        if risky.contains(where: { text.lowercased().contains($0) }) { riskyDist += step.distance }
    }
    let total = max(r.distance, 1)
    let turns = Double(max(0, r.steps.count - 2))
    return mainDist / total - riskyDist / total - turns * 0.03
}

/// Destination search + Apple walking directions.
@MainActor
final class PlanModel: NSObject, ObservableObject, MKLocalSearchCompleterDelegate, CLLocationManagerDelegate {
    @Published var query = "" { didSet { completer.queryFragment = query } }
    @Published var suggestions: [MKLocalSearchCompletion] = []
    @Published var start = CLLocationCoordinate2D(latitude: 33.41955, longitude: -111.93455) // Hayden Library fallback
    @Published var startName = "Hayden Library"
    @Published var destination: MKMapItem?
    @Published var routes: [MKRoute] = []
    @Published var choice: RouteChoice = RouteChoice(rawValue: UserDefaults.standard.string(forKey: "wb.routePref") ?? "safe") ?? .safe
    @Published var routing = false

    /// Quickest: least walking time.
    var quickest: MKRoute? { routes.min { $0.expectedTravelTime < $1.expectedTravelTime } }
    /// Safer (heuristic, no crime data): most of the distance on main named streets, fewest turns.
    var safest: MKRoute? { routes.max { safetyScore($0) < safetyScore($1) } }
    var sameRoute: Bool { quickest.map { q in safest.map { $0 === q } ?? true } ?? true }
    var route: MKRoute? { choice == .safe ? safest : quickest }
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
        req.requestsAlternateRoutes = true
        do {
            routes = try await MKDirections(request: req).calculate().routes
            if routes.isEmpty { error = "No walking route found" }
        } catch {
            routes = []
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
    @State private var demo = UserDefaults.standard.object(forKey: "wb.demoDefault") as? Bool ?? true
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
                if !plan.sameRoute, let other = plan.choice == .safe ? plan.quickest : plan.safest {
                    MapPolyline(other.polyline).stroke((plan.choice == .safe ? Palette.gold : Palette.ok).opacity(0.45),
                                                       style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round, dash: [2, 9]))
                }
                if let r = plan.route {
                    let tint = plan.choice == .safe ? Palette.ok : Palette.gold
                    MapPolyline(r.polyline).stroke(.black.opacity(0.45), style: StrokeStyle(lineWidth: 12, lineCap: .round, lineJoin: .round))
                    MapPolyline(r.polyline).stroke(tint, style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
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
            .onChange(of: plan.routes) { _, _ in
                guard let r = plan.route else { return }
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
                            Button { plan.query = ""; plan.routes = []; plan.destination = nil } label: {
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
                    TripSheet(name: d.name ?? "Destination", address: d.placemark.title, plan: plan, route: plan.route, routing: plan.routing,
                              demo: $demo, starting: starting, buddyForm: store.user?.buddy.form ?? "sprout", buddySpecies: store.user?.buddy.species,
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
    @ObservedObject var plan: PlanModel
    let route: MKRoute?
    let routing: Bool
    @Binding var demo: Bool
    let starting: Bool
    let buddyForm: String
    var buddySpecies: String? = "chick"
    let buddyName: String
    let go: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Capsule().fill(Palette.line).frame(width: 40, height: 5).frame(maxWidth: .infinity)
            HStack(alignment: .top, spacing: 14) {
                petSprite(buddySpecies, buddyForm).image.resizable().scaledToFit().frame(width: 64, height: 64)
                    .background(Circle().fill(Palette.gold.opacity(0.14)))
                VStack(alignment: .leading, spacing: 3) {
                    Text(name).font(Typeface.display(26)).foregroundStyle(Palette.text).lineLimit(2)
                    if let address { Text(address).font(Typeface.body(14)).foregroundStyle(Palette.muted).lineLimit(1) }
                }
            }
            if plan.routes.isEmpty {
                HStack(spacing: 10) {
                    ProgressView().tint(Palette.gold)
                    Text(routing ? "Finding walking routes..." : "No route yet").font(Typeface.body(14)).foregroundStyle(Palette.muted)
                }
            } else if plan.sameRoute, let r = plan.route {
                RouteOption(kind: .safe, route: r, selected: true, note: "Quickest route is also the safer one") {}
            } else {
                VStack(spacing: 10) {
                    if let s = plan.safest {
                        RouteOption(kind: .safe, route: s, selected: plan.choice == .safe, note: "Main streets, fewer turns") {
                            withAnimation(.spring(response: 0.35)) { plan.choice = .safe }
                        }
                    }
                    if let q = plan.quickest {
                        RouteOption(kind: .quick, route: q, selected: plan.choice == .quick, note: "Fastest way there") {
                            withAnimation(.spring(response: 0.35)) { plan.choice = .quick }
                        }
                    }
                }
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

func formatDistance(_ m: Double) -> String { m >= 1000 ? String(format: "%.1f km", m / 1000) : "\(Int(m)) m" }


private struct RouteOption: View {
    let kind: RouteChoice
    let route: MKRoute
    let selected: Bool
    let note: String
    let pick: () -> Void
    var body: some View {
        let tint = kind == .safe ? Palette.ok : Palette.gold
        Button(action: pick) {
            HStack(spacing: 12) {
                Image(systemName: kind == .safe ? "shield.lefthalf.filled" : "bolt.fill")
                    .font(.system(size: 17, weight: .bold)).foregroundStyle(kind == .safe ? Color(hex: 0x032417) : Palette.ink)
                    .frame(width: 40, height: 40).background(Circle().fill(tint))
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind == .safe ? "Safer route" : "Quickest route").font(Typeface.displayBold(17)).foregroundStyle(Palette.text)
                    Text(note).font(Typeface.body(13)).foregroundStyle(Palette.muted).lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(Int((route.expectedTravelTime / 60).rounded())) min").font(Typeface.display(19)).foregroundStyle(Palette.text).monospacedDigit()
                    Text(formatDistance(route.distance)).font(Typeface.body(12)).foregroundStyle(Palette.muted)
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(selected ? tint.opacity(0.12) : Color(hex: 0x0f1433)))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(selected ? tint : Palette.line, lineWidth: selected ? 2 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(kind == .safe ? "Safer route" : "Quickest route")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
