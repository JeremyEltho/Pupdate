import Foundation

struct BuddyInfo: Codable, Equatable { var name: String; var xp: Int; var form: String; var species: String? }

struct EngineSnap: Codable, Equatable {
    var state: String
    var secondsLeft: Double?
    var reason: String?
    var ignorePets: Bool?
}

struct WalkEvent: Codable, Equatable { var type: String; var xp: Int?; var evolved: String?; var kind: String?; var reason: String?; var state: String?; var late: Bool?; var afterAlert: Bool?; var realAt: String? }

struct AlertInfo: Codable, Equatable, Identifiable {
    var id: String
    var walkId: String
    var walkerId: String
    var walkerName: String
    var walkerPhone: String
    var kind: String
    var status: String
    var openedAt: String
    var pos: [Double]?
    var pettedAfter: String?
    var contactRestored: String?
    var closedBy: String?
    var summary: String?
    var summarySource: String?
}

struct FriendInfo: Codable, Equatable, Identifiable { var id: String; var name: String; var phone: String }

struct Walk: Codable, Equatable, Identifiable {
    var id: String
    var walkerId: String
    var walkerName: String
    var demo: Bool
    var streak: Int?
    var status: String
    var routeId: String?
    var engine: EngineSnap
    var speed: Double
    var pos: [Double]?
    var trail: [[Double]]
    var buddy: BuddyInfo
    var nextFormAt: Int?
    var alerts: [AlertInfo]
    var events: [WalkEvent]
    var offRoute: Bool
    var buddyLine: String?
    var buddyLineSource: String?
}

struct RouteInfo: Codable, Equatable, Identifiable {
    var id: String; var name: String; var from: String; var to: String; var points: [[Double]]; var lengthM: Double
}

struct UserInfo: Codable, Equatable { var id: String; var name: String; var buddy: BuddyInfo; var streak: Int?; var activeWalkId: String? }

struct Feed: Codable, Equatable { var walks: [Walk]; var openAlerts: [AlertInfo]; var recentAlerts: [AlertInfo] }

struct RouteAssessment: Codable { var saferId: String?; var reasons: [String: String]; var source: String }

struct PetResponse: Codable { var events: [WalkEvent]; var walk: Walk }
struct DuressResponse: Codable { var ok: Bool; var walk: Walk }

enum APIError: LocalizedError {
    case http(Int, String)
    var errorDescription: String? {
        switch self { case .http(let code, let msg): return msg.isEmpty ? "Server error \(code)" : msg }
    }
}

final class API {
    static let shared = API()

    var base: String {
        get {
            let d = UserDefaults.standard
            // Forget old temporary tunnel addresses so the permanent server is used.
            if let saved = d.string(forKey: "wb.server"), saved.contains("trycloudflare.com") || saved.contains("ngrok") {
                d.removeObject(forKey: "wb.server")
            }
            return d.string(forKey: "wb.server")
                ?? (Bundle.main.object(forInfoDictionaryKey: "WBDefaultServer") as? String) ?? "http://localhost:8100"
        }
        set {
            let v = newValue.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            UserDefaults.standard.set(v, forKey: "wb.server")
        }
    }

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    private let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 8
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: c)
    }()

    func get<T: Decodable>(_ path: String) async throws -> T { try await send(path, method: "GET", body: nil) }

    func post<T: Decodable>(_ path: String, _ body: [String: Any] = [:]) async throws -> T {
        try await send(path, method: "POST", body: body)
    }

    func send<T: Decodable>(_ path: String, method: String, body: [String: Any]?) async throws -> T {
        guard let url = URL(string: base + path) else { throw APIError.http(0, "Bad server address") }
        var req = URLRequest(url: url)
        req.httpMethod = method
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, resp) = try await session.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["detail"] as? String
            throw APIError.http(code, detail ?? "")
        }
        return try decoder.decode(T.self, from: data)
    }

    // Typed calls
    func health() async throws -> [String: Bool] { try await get("/health") }
    func routes() async throws -> [RouteInfo] { try await get("/routes") }
    func user(_ id: String) async throws -> UserInfo { try await get("/users/\(id)") }
    func active(_ id: String) async throws -> Walk? { try await get("/users/\(id)/active") }
    func pet(_ wid: String) async throws -> PetResponse { try await post("/walks/\(wid)/pet") }
    func duress(_ wid: String) async throws -> DuressResponse { try await post("/walks/\(wid)/duress") }
    func feed(_ fid: String) async throws -> Feed { try await get("/friends/\(fid)/feed") }
    func closeAlert(_ aid: String, friend: String) async throws -> AlertInfo { try await post("/alerts/\(aid)/close", ["friend_id": friend]) }
    func startWalk(_ walker: String, route: String) async throws -> Walk {
        var body: [String: Any] = ["walker_id": walker, "route_id": route, "demo": false]
        body.merge(API.walkSettings) { a, _ in a }
        return try await post("/walks", body)
    }
    /// Walker settings sent with every new walk (see SettingsView).
    static var walkSettings: [String: Any] {
        let d = UserDefaults.standard
        let every = d.object(forKey: "wb.checkinEvery") as? Int ?? 0
        return [
            "checkin_every_s": every > 0 ? every : NSNull(),
            "watch_route": d.object(forKey: "wb.watchRoute") as? Bool ?? true,
            "watch_speed": d.object(forKey: "wb.watchSpeed") as? Bool ?? true,
        ]
    }

    func startPlanned(_ walker: String, points: [[Double]], from: String, to: String, demo: Bool) async throws -> Walk {
        var body: [String: Any] = ["walker_id": walker, "points": points, "from_name": from, "to_name": to, "demo": demo]
        body.merge(API.walkSettings) { a, _ in a }
        return try await post("/walks", body)
    }
    func assessRoutes(_ routes: [[String: Any]], hour: Int) async throws -> RouteAssessment {
        try await post("/routes/assess", ["routes": routes, "hour": hour])
    }
    func tick(_ wid: String, lat: Double? = nil, lng: Double? = nil, accuracy: Double? = nil) async throws {
        var b: [String: Any] = [:]
        if let lat, let lng { b["lat"] = lat; b["lng"] = lng }
        if let accuracy { b["accuracy"] = accuracy }
        let _: [String: AnyCodable] = try await post("/walks/\(wid)/tick", b)
    }
    func customize(_ uid: String, name: String?, species: String?) async throws -> BuddyInfo {
        var b: [String: Any] = [:]
        if let name { b["name"] = name }
        if let species { b["species"] = species }
        return try await post("/users/\(uid)/buddy", b)
    }
    func circle(_ uid: String) async throws -> [FriendInfo] { try await get("/users/\(uid)/circle") }
    func addFriend(_ uid: String, name: String, phone: String) async throws -> FriendInfo {
        try await post("/users/\(uid)/circle", ["name": name, "phone": phone])
    }
    func removeFriend(_ uid: String, _ fid: String) async throws {
        let _: AnyCodable = try await send("/users/\(uid)/circle/\(fid)", method: "DELETE", body: nil)
    }
    func end(_ wid: String) async throws -> Walk { try await post("/walks/\(wid)/end") }
    func demo(_ action: String, _ body: [String: Any] = [:]) async throws {
        let _: AnyCodable = try await post("/demo/\(action)", body)
    }
}

/// Decodes and ignores any JSON value.
struct AnyCodable: Codable {
    init(from decoder: Decoder) throws {}
    func encode(to encoder: Encoder) throws {}
}
