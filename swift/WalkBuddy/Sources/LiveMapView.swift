import MapKit
import SwiftUI

/// Real Apple Map: route, walked trail, the walker's live marker (carrying the buddy) and home.
struct LiveMapView: View {
    var route: [[Double]]?
    var trail: [[Double]] = []
    var pos: [Double]?
    var form: String = "sprout"
    var offRoute = false
    var alert = false
    var follow = true
    @State private var camera: MapCameraPosition = .automatic
    @State private var pulse = false

    private func c(_ p: [Double]) -> CLLocationCoordinate2D { .init(latitude: p[0], longitude: p[1]) }

    var body: some View {
        let dot = alert ? Palette.alert : offRoute ? Palette.warn : Palette.gold
        Map(position: $camera, interactionModes: [.pan, .zoom, .rotate, .pitch]) {
            if let route, route.count > 1 {
                MapPolyline(coordinates: route.map(c))
                    .stroke(Color(hex: 0x7aa2ff).opacity(0.55), style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round))
            }
            if trail.count > 1 {
                MapPolyline(coordinates: trail.map(c))
                    .stroke(offRoute ? Palette.warn : Palette.gold, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            }
            if let last = route?.last {
                Annotation("Home", coordinate: c(last), anchor: .bottom) {
                    Sprite.house.image.resizable().scaledToFit().frame(width: 38, height: 38)
                        .shadow(color: .black.opacity(0.4), radius: 4, y: 3)
                }
            }
            if let pos, pos.count == 2 {
                Annotation("", coordinate: c(pos), anchor: .center) {
                    ZStack {
                        Circle().fill(dot.opacity(0.28)).frame(width: pulse ? 64 : 38, height: pulse ? 64 : 38)
                        Circle().fill(.white).frame(width: 40, height: 40).shadow(color: .black.opacity(0.35), radius: 5, y: 3)
                        Circle().fill(dot).frame(width: 34, height: 34)
                        formSprite(form).image.resizable().scaledToFit().frame(width: 28, height: 28)
                    }
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
        .mapControlVisibility(.hidden)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { pulse = true }
            recenter(animated: false)
        }
        .onChange(of: pos) { _, _ in if follow { recenter(animated: true) } }
    }

    private func recenter(animated: Bool) {
        guard let p = pos ?? route?.first, p.count == 2 else { return }
        let cam = MapCameraPosition.camera(MapCamera(centerCoordinate: c(p), distance: 700, heading: 20, pitch: 55))
        if animated { withAnimation(.easeInOut(duration: 0.9)) { camera = cam } } else { camera = cam }
    }
}
