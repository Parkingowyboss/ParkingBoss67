import CoreLocation
import Foundation

enum APIError: LocalizedError {
    case badURL
    case http(Int)
    case decoding(Error)
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .badURL: return "Nieprawidłowy adres URL"
        case .http(let code): return "Błąd serwera (\(code))"
        case .decoding: return "Nie udało się odczytać danych"
        case .transport: return "Brak połączenia z serwerem"
        }
    }
}

/// Thin async client for the ParkingBoss backend.
struct APIClient {
    static let shared = APIClient()

    /// Override via build setting / launch arg for device testing.
    let baseURL: URL
    private let session: URLSession

    init(baseURL: URL = APIClient.defaultBaseURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    static var defaultBaseURL: URL {
        if let raw = ProcessInfo.processInfo.environment["PARKINGBOSS_API"],
           let url = URL(string: raw) {
            return url
        }
        // Simulator talks to the host machine on localhost.
        return URL(string: "http://localhost:3000")!
    }

    func nearby(
        center: CLLocationCoordinate2D,
        radius: Double,
        types: [LocationType]? = nil,
        limit: Int = 200
    ) async throws -> [Location] {
        var items = [
            URLQueryItem(name: "lat", value: String(center.latitude)),
            URLQueryItem(name: "lng", value: String(center.longitude)),
            URLQueryItem(name: "radius", value: String(Int(radius))),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        if let types, !types.isEmpty {
            items.append(URLQueryItem(name: "type", value: types.map(\.rawValue).joined(separator: ",")))
        }
        let response: LocationListResponse = try await get(path: "/locations", query: items)
        return response.items
    }

    func search(query: String, limit: Int = 20) async throws -> [Location] {
        let items = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        let response: LocationListResponse = try await get(path: "/locations/search", query: items)
        return response.items
    }

    func detail(id: String) async throws -> Location {
        try await get(path: "/locations/\(id)", query: [])
    }

    // MARK: - Individual stalls

    /// Stalls inside a map rectangle. `bbox` is (minLng, minLat, maxLng, maxLat).
    func spaces(
        bbox: (minLng: Double, minLat: Double, maxLng: Double, maxLat: Double),
        statuses: [SpaceStatus]? = nil,
        limit: Int = 2000
    ) async throws -> [ParkingSpace] {
        var items = [
            URLQueryItem(name: "bbox", value: "\(bbox.minLng),\(bbox.minLat),\(bbox.maxLng),\(bbox.maxLat)"),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        if let statuses, !statuses.isEmpty {
            items.append(URLQueryItem(name: "status", value: statuses.map(\.rawValue).joined(separator: ",")))
        }
        let response: SpaceListResponse = try await get(path: "/spaces", query: items)
        return response.items
    }

    /// Submit a crowd-sourced occupancy report; returns the updated stall.
    func report(spaceId: String, status: SpaceStatus, clientId: String) async throws -> ParkingSpace {
        try await post(path: "/spaces/\(spaceId)/report", body: [
            "status": status.rawValue,
            "clientId": clientId,
        ])
    }

    // MARK: - Core

    private func get<T: Decodable>(path: String, query: [URLQueryItem]) async throws -> T {
        guard var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw APIError.badURL
        }
        components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else { throw APIError.badURL }

        return try await send(request: URLRequest(url: url))
    }

    private func post<T: Decodable>(path: String, body: [String: Any]) async throws -> T {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return try await send(request: request)
    }

    private func send<T: Decodable>(request: URLRequest) async throws -> T {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw APIError.http(-1) }
            guard (200..<300).contains(http.statusCode) else { throw APIError.http(http.statusCode) }
            do {
                return try JSONDecoder().decode(T.self, from: data)
            } catch {
                throw APIError.decoding(error)
            }
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.transport(error)
        }
    }
}
