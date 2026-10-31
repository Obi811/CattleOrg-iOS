import Foundation
import os.log

private let logger = Logger(subsystem: "com.cattleorg.app", category: "CattleAPI")

enum CattleAPIError: Error, LocalizedError {
    case invalidURL
    case unauthorized
    case tokenExpired
    case rateLimited(retryAfter: Int)
    case notFound
    case serverError(String)
    case networkError(String)
    case decodingError(String)
    case noData

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Ung\u{00FC}ltige URL"
        case .unauthorized: return "Nicht autorisiert. Bitte erneut anmelden."
        case .tokenExpired: return "Sitzung abgelaufen. Bitte erneut anmelden."
        case .rateLimited(let s): return "Zu viele Anfragen. Bitte warten Sie \(s) Sekunden."
        case .notFound: return "Dieser Bereich ist noch nicht verf\u{00FC}gbar. Bitte den Server-Endpunkt erg\u{00E4}nzen."
        case .serverError(let m): return m
        case .networkError(let m): return m
        case .decodingError(let m): return "Datenverarbeitungsfehler: \(m)"
        case .noData: return "Keine Daten erhalten."
        }
    }
}

enum CattleAPI {
    static let baseURLString = "https://zuhausemail.eu/api/v1"
    static var token: String?
    static var farmId: String?

    // MARK: - Generic Request
    private static func request<T: Decodable>(
        method: String,
        path: String,
        queryItems: [URLQueryItem]? = nil,
        body: [String: Any]? = nil,
        skipAuth: Bool = false
    ) async throws -> APIDataResponse<T> {
        guard var components = URLComponents(string: baseURLString + path) else {
            throw CattleAPIError.invalidURL
        }
        if let qi = queryItems, !qi.isEmpty {
            components.queryItems = qi
        }
        guard let url = components.url else { throw CattleAPIError.invalidURL }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 30

        if !skipAuth, let t = token {
            req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization")
        }
        if !skipAuth, let fid = farmId {
            req.setValue(fid, forHTTPHeaderField: "X-Farm-Id")
        }
        if let body = body {
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }

        logger.info("\(method) \(url.absoluteString)")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch let err as URLError {
            if err.code == .notConnectedToInternet || err.code == .networkConnectionLost {
                throw CattleAPIError.networkError("Keine Internetverbindung. Bitte pr\u{00FC}fen Sie Ihre Verbindung.")
            }
            if err.code == .timedOut {
                throw CattleAPIError.networkError("Zeit\u{00FC}berschreitung. Bitte versuchen Sie es erneut.")
            }
            throw CattleAPIError.networkError(err.localizedDescription)
        } catch {
            throw CattleAPIError.networkError(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw CattleAPIError.networkError("Ung\u{00FC}ltige Serverantwort")
        }

        logger.info("Response \(http.statusCode) for \(path)")

        switch http.statusCode {
        case 200...299:
            break
        case 401:
            if let errResp = try? JSONDecoder().decode(APIDataResponse<CattleEmptyData>.self, from: data),
               errResp.error?.code == "TOKEN_EXPIRED" {
                throw CattleAPIError.tokenExpired
            }
            throw CattleAPIError.unauthorized
        case 404:
            throw CattleAPIError.notFound
        case 429:
            let ra = http.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init) ?? 30
            throw CattleAPIError.rateLimited(retryAfter: ra)
        default:
            if let errResp = try? JSONDecoder().decode(APIDataResponse<CattleEmptyData>.self, from: data),
               let msg = errResp.error?.message {
                throw CattleAPIError.serverError(msg)
            }
            throw CattleAPIError.serverError("Serverfehler (\(http.statusCode))")
        }

        if data.isEmpty {
            let emptyJSON = #"{"success":true}"#.data(using: .utf8) ?? Data()
            do {
                return try JSONDecoder().decode(APIDataResponse<T>.self, from: emptyJSON)
            } catch {
                throw CattleAPIError.noData
            }
        }

        do {
            return try JSONDecoder().decode(APIDataResponse<T>.self, from: data)
        } catch {
            logger.error("Decode error: \(error.localizedDescription)")
            throw CattleAPIError.decodingError(error.localizedDescription)
        }
    }

    private static func get<T: Decodable>(path: String, query: [URLQueryItem]? = nil) async throws -> T {
        let resp: APIDataResponse<T> = try await request(method: "GET", path: path, queryItems: query)
        guard let d = resp.data else { throw CattleAPIError.noData }
        return d
    }

    private static func getWithMeta<T: Decodable>(path: String, query: [URLQueryItem]? = nil) async throws -> (data: T, meta: ResponseMeta?) {
        let resp: APIDataResponse<T> = try await request(method: "GET", path: path, queryItems: query)
        guard let d = resp.data else { throw CattleAPIError.noData }
        return (d, resp.meta)
    }

    private static func post<T: Decodable>(path: String, body: [String: Any]) async throws -> T {
        let resp: APIDataResponse<T> = try await request(method: "POST", path: path, body: body)
        guard let d = resp.data else { throw CattleAPIError.noData }
        return d
    }

    private static func postVoid(path: String, body: [String: Any]? = nil) async throws {
        let _: APIDataResponse<CattleEmptyData> = try await request(method: "POST", path: path, body: body)
    }

    private static func putVoid(path: String, query: [URLQueryItem]? = nil, body: [String: Any]) async throws {
        let _: APIDataResponse<CattleEmptyData> = try await request(method: "PUT", path: path, queryItems: query, body: body)
    }

    private static func deleteReq(path: String, query: [URLQueryItem]? = nil) async throws {
        let _: APIDataResponse<CattleEmptyData> = try await request(method: "DELETE", path: path, queryItems: query)
    }

    // MARK: - Auth
    static func login(username: String, password: String) async throws -> LoginResponse {
        let body: [String: Any] = ["username": username, "password": password]
        let resp: APIDataResponse<LoginResponse> = try await request(method: "POST", path: "/auth/login/", body: body, skipAuth: true)
        guard let d = resp.data else {
            throw CattleAPIError.serverError(resp.error?.message ?? "Anmeldung fehlgeschlagen")
        }
        return d
    }

    static func logout() async {
        do {
            try await postVoid(path: "/auth/logout/")
        } catch {
            logger.warning("Logout request failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Farms
    static func fetchFarms() async throws -> [Farm] {
        try await get(path: "/farm/")
    }

    // MARK: - Cattle
    static func fetchCattle(
        page: Int = 1,
        perPage: Int = 50,
        search: String? = nil,
        status: String? = nil,
        geschlecht: String? = nil,
        stall: String? = nil,
        wartezeitOnly: Bool = false,
        traechtigOnly: Bool = false,
        rasse: String? = nil,
        minAgeMonths: Int? = nil,
        maxAgeMonths: Int? = nil,
        trockensteherOnly: Bool = false,
        milchkuhOnly: Bool = false
    ) async throws -> (cattle: [Cattle], meta: ResponseMeta?) {
        var q = [URLQueryItem(name: "page", value: String(page)),
                 URLQueryItem(name: "per_page", value: String(perPage))]
        if let s = search, !s.isEmpty { q.append(.init(name: "q", value: s)) }
        if let st = status, !st.isEmpty, st.lowercased() != "alle" { q.append(.init(name: "status", value: st)) }
        if let g = geschlecht, !g.isEmpty { q.append(.init(name: "geschlecht", value: g)) }
        if let stl = stall, !stl.isEmpty { q.append(.init(name: "stall", value: stl)) }
        if wartezeitOnly { q.append(.init(name: "wartezeit", value: "1")) }
        if traechtigOnly { q.append(.init(name: "traechtig", value: "1")) }
        if let r = rasse, !r.isEmpty { q.append(.init(name: "rasse", value: r)) }
        if let minA = minAgeMonths { q.append(.init(name: "min_age", value: String(minA))) }
        if let maxA = maxAgeMonths { q.append(.init(name: "max_age", value: String(maxA))) }
        if trockensteherOnly { q.append(.init(name: "trockensteher", value: "1")) }
        if milchkuhOnly { q.append(.init(name: "milchkuh", value: "1")) }
        let result: (data: [Cattle], meta: ResponseMeta?) = try await getWithMeta(path: "/cattle/", query: q)
        return (result.data, result.meta)
    }

    static func fetchCattleDetail(id: String) async throws -> Cattle {
        try await get(path: "/cattle/", query: [URLQueryItem(name: "id", value: id)])
    }

    static func createCattle(_ body: [String: Any]) async throws -> Cattle {
        try await post(path: "/cattle/", body: body)
    }

    // MARK: - Treatments
    static func fetchTreatments(cattleId: String? = nil) async throws -> [Treatment] {
        var q: [URLQueryItem]?
        if let cid = cattleId { q = [URLQueryItem(name: "cattle_id", value: cid)] }
        return try await get(path: "/treatments/", query: q)
    }

    static func createTreatment(_ body: [String: Any]) async throws -> Treatment {
        try await post(path: "/treatments/", body: body)
    }

    // MARK: - Medications
    static func fetchMedications() async throws -> [Medication] {
        try await get(path: "/medications/")
    }

    // MARK: - Inseminations
    static func fetchInseminations(cattleId: String? = nil) async throws -> [Insemination] {
        var q: [URLQueryItem]?
        if let cid = cattleId { q = [URLQueryItem(name: "cattle_id", value: cid)] }
        return try await get(path: "/inseminations/", query: q)
    }

    static func createInsemination(_ body: [String: Any]) async throws -> Insemination {
        try await post(path: "/inseminations/", body: body)
    }

    // MARK: - Pregnancy Checks
    static func fetchPregnancyChecks(cattleId: String? = nil) async throws -> [PregnancyCheck] {
        var q: [URLQueryItem]?
        if let cid = cattleId { q = [URLQueryItem(name: "cattle_id", value: cid)] }
        return try await get(path: "/pregnancy/", query: q)
    }

    static func createPregnancyCheck(_ body: [String: Any]) async throws -> PregnancyCheck {
        try await post(path: "/pregnancy/", body: body)
    }

    // MARK: - Stalls
    static func fetchStalls() async throws -> [Stall] {
        try await get(path: "/stalls/")
    }

    // MARK: - Breeds (Rassen)
    static func fetchBreeds() async throws -> [String] {
        try await get(path: "/cattle/breeds/")
    }

    // MARK: - Planned Treatments (geplante Behandlungen)
    // Server-Endpunkt /api/v1/planned-treatments/ (ab V0.10; vorher 404 -> "bald verfügbar")
    static func fetchPlannedTreatments(
        cattleId: String? = nil,
        status: String? = nil,
        from: String? = nil,
        to: String? = nil,
        page: Int = 1,
        perPage: Int = 100
    ) async throws -> (items: [PlannedTreatment], meta: ResponseMeta?) {
        var q = [URLQueryItem(name: "page", value: String(page)),
                 URLQueryItem(name: "per_page", value: String(perPage))]
        if let c = cattleId, !c.isEmpty { q.append(.init(name: "cattle_id", value: c)) }
        if let s = status, !s.isEmpty { q.append(.init(name: "status", value: s)) }
        if let f = from, !f.isEmpty { q.append(.init(name: "from", value: f)) }
        if let t = to, !t.isEmpty { q.append(.init(name: "to", value: t)) }
        let result: (data: [PlannedTreatment], meta: ResponseMeta?) = try await getWithMeta(path: "/planned-treatments/", query: q)
        return (result.data, result.meta)
    }

    static func createPlannedTreatment(_ body: [String: Any]) async throws -> PlannedTreatment {
        try await post(path: "/planned-treatments/", body: body)
    }

    static func updatePlannedTreatment(id: String, body: [String: Any]) async throws {
        try await putVoid(path: "/planned-treatments/", query: [URLQueryItem(name: "id", value: id)], body: body)
    }

    static func deletePlannedTreatment(id: String) async throws {
        try await deleteReq(path: "/planned-treatments/", query: [URLQueryItem(name: "id", value: id)])
    }

    /// Markiert eine geplante Behandlung als erledigt (erzeugt eine Behandlung).
    static func completePlannedTreatment(id: String, treatmentDate: String? = nil) async throws {
        var body: [String: Any] = [:]
        if let d = treatmentDate, !d.isEmpty { body["treatment_date"] = d }
        let _: APIDataResponse<PlannedCompleteResult> = try await request(
            method: "POST",
            path: "/planned-treatments/complete/",
            queryItems: [URLQueryItem(name: "id", value: id)],
            body: body
        )
    }

    // MARK: - Stillbirths (Totgeburten)
    // Server-Endpunkt /api/v1/stillbirths/ (ab V0.10; vorher 404 -> "bald verfügbar")
    static func fetchStillbirths(cattleId: String) async throws -> [Stillbirth] {
        try await get(path: "/stillbirths/", query: [URLQueryItem(name: "cattle_id", value: cattleId)])
    }

    static func createStillbirth(_ body: [String: Any]) async throws -> Stillbirth {
        try await post(path: "/stillbirths/", body: body)
    }

    static func deleteStillbirth(id: String) async throws {
        try await deleteReq(path: "/stillbirths/", query: [URLQueryItem(name: "id", value: id)])
    }

    // MARK: - Group Actions (Gruppenaktionen pro Box)
    // Server-Endpunkt /api/v1/group-actions/ (ab V0.10; vorher 404 -> "bald verfügbar")
    static func fetchGroupAnimals(stall: String) async throws -> [GroupAnimal] {
        try await get(path: "/group-actions/", query: [URLQueryItem(name: "stall", value: stall)])
    }

    static func performGroupAction(_ body: [String: Any]) async throws -> GroupActionResult {
        try await post(path: "/group-actions/", body: body)
    }

    // MARK: - TODO: Server-Endpunkt /api/v1/dashboard/ noch nicht implementiert
    static func fetchDashboard() async throws -> DashboardResponse {
        try await get(path: "/dashboard/")
    }

    // TODO: Server-Endpunkt /api/v1/user/ noch nicht implementiert
    static func fetchUserProfile() async throws -> User {
        try await get(path: "/user/")
    }

    // TODO: Server-Endpunkt /api/v1/cattle/abgang/ noch nicht implementiert
    static func reportDeparture(_ body: [String: Any]) async throws {
        try await postVoid(path: "/cattle/abgang/", body: body)
    }

    // TODO: Server-Endpunkt /api/v1/inhibitor-tests/ noch nicht implementiert
    static func fetchInhibitorTests(cattleId: String? = nil, status: String? = nil) async throws -> [InhibitorTest] {
        var q: [URLQueryItem] = []
        if let cid = cattleId { q.append(.init(name: "cattle_id", value: cid)) }
        if let s = status { q.append(.init(name: "status", value: s)) }
        return try await get(path: "/inhibitor-tests/", query: q.isEmpty ? nil : q)
    }

    // TODO: Server-Endpunkt /api/v1/inhibitor-tests/ POST noch nicht implementiert
    static func createInhibitorTest(_ body: [String: Any]) async throws -> InhibitorTest {
        try await post(path: "/inhibitor-tests/", body: body)
    }

    // TODO: Server-Endpunkt /api/v1/inhibitor-tests/ PUT noch nicht implementiert
    static func updateInhibitorTest(id: String, statusValue: String) async throws {
        try await putVoid(path: "/inhibitor-tests/", query: [URLQueryItem(name: "id", value: id)], body: ["status": statusValue])
    }

    // TODO: Server-Endpunkt /api/v1/user/password/ noch nicht implementiert
    static func changePassword(currentPassword: String, newPassword: String) async throws {
        try await putVoid(path: "/user/password/", body: ["current_password": currentPassword, "new_password": newPassword])
    }

    // TODO: Server-Endpunkt /api/v1/device-tokens/ POST noch nicht implementiert
    static func registerDeviceToken(_ body: [String: Any]) async throws {
        try await postVoid(path: "/device-tokens/", body: body)
    }

    // TODO: Server-Endpunkt /api/v1/device-tokens/ DELETE noch nicht implementiert
    static func deleteDeviceToken(tokenValue: String) async throws {
        try await deleteReq(path: "/device-tokens/", query: [URLQueryItem(name: "token", value: tokenValue)])
    }
}
