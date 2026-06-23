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

    // MARK: - Core

    private func get<T: Decodable>(path: String, query: [URLQueryItem]) async throws -> T {
        guard var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw APIError.badURL
        }
        components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else { throw APIError.badURL }

        do {
            let (data, response) = try await session.data(from: url)
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
