import Foundation

// MARK: - FlexibleID (handles both String and Int from API)
struct FlexibleID: Codable, Hashable, Sendable, CustomStringConvertible {
    let value: String

    var description: String { value }

    init(_ value: String) { self.value = value }
    init(_ value: Int) { self.value = String(value) }
    init() { self.value = "" }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intVal = try? container.decode(Int.self) {
            value = String(intVal)
        } else if let strVal = try? container.decode(String.self) {
            value = strVal
        } else {
            value = ""
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let intVal = Int(value) {
            try container.encode(intVal)
        } else {
            try container.encode(value)
        }
    }
}

// MARK: - API Response Wrapper
struct APIDataResponse<T: Decodable>: Decodable {
    let success: Bool?
    let data: T?
    let meta: ResponseMeta?
    let error: ResponseError?
}

struct ResponseMeta: Decodable {
    var page: Int?
    var per_page: Int?
    var total: Int?
    var total_pages: Int?
}

struct ResponseError: Decodable {
    var code: String?
    var message: String?
}

struct CattleEmptyData: Decodable {}

// MARK: - User
struct User: Codable, Identifiable, Sendable {
    var id: FlexibleID
    var username: String?
    var is_admin: Bool?
}

// MARK: - Farm
struct Farm: Codable, Identifiable, Sendable {
    var id: FlexibleID
    var name: String?
    var is_demo: Bool?
    var role: String?
}

// MARK: - Login Response
struct LoginResponse: Codable {
    var token: String
    var token_type: String?
    var expires_in_days: Int?
    var user: User
    var farms: [Farm]
}

// MARK: - Wartezeit (nested object in cattle detail response)
struct Wartezeit: Codable, Sendable {
    var aktiv: Bool?
    var ende: String?
    var milch_ende: String?
    var fleisch_ende: String?
}

// MARK: - Pregnancy (nested object in cattle detail response)
struct Pregnancy: Codable, Sendable {
    var status: String?
    var last_insemination: String?
    var last_check: String?
    var expected_calving: String?
}

// MARK: - Cattle
struct Cattle: Codable, Identifiable, Sendable {
    var id: FlexibleID
    var ear_tag: String?
    var name: String?
    var birth_date: String?
    var rasse: String?
    var geschlecht: String?
    var mutter: String?
    var status: String?
    var current_stall: String?
    // Detail: nested object. List: flat wz_ende / wz_aktiv fields.
    var wartezeit: Wartezeit?
    var wz_ende: String?
    var wz_aktiv: Bool?
    var pregnancy: Pregnancy?
    var hemmstoff_probes: [InhibitorTest]?
    var treatments: [Treatment]?
    var inseminations: [Insemination]?
    var pregnancy_checks: [PregnancyCheck]?

    var displayTag: String { ear_tag ?? "Unbekannt" }
    var isWartezeitActive: Bool { wartezeit?.aktiv == true || wz_aktiv == true }
    var wartezeitEnde: String? { wartezeit?.ende ?? wz_ende }
}

// MARK: - Treatment
struct Treatment: Codable, Identifiable, Sendable {
    var id: FlexibleID
    var cattle_id: FlexibleID?
    var ear_tag: String?
    var treatment_date: String?
    var medication: String?
    var dosage: String?
    var type: String?
    var notes: String?
    var wz_milk: String?
    var wz_fleisch: String?
    var wz_ende: String?
    var wz_aktiv: Bool?
}

// MARK: - Insemination
struct Insemination: Codable, Identifiable, Sendable {
    var id: FlexibleID
    var cattle_id: FlexibleID?
    var ear_tag: String?
    var date: String?
    var bull_name: String?
    var type: String?
    var technician: String?
}

// MARK: - PregnancyCheck
struct PregnancyCheck: Codable, Identifiable, Sendable {
    var id: FlexibleID
    var cattle_id: FlexibleID?
    var ear_tag: String?
    var check_date: String?
    var result: String?
    var comment: String?
    var checked_by: String?
}

// MARK: - Medication
struct Medication: Codable, Identifiable, Sendable {
    var id: FlexibleID
    var name: String?
    var active_substance: String?
    var dosage: String?
    var wz_milk: String?
    var wz_fleisch: String?
}

// MARK: - InhibitorTest
struct InhibitorTest: Codable, Identifiable, Sendable {
    var id: FlexibleID
    var cattle_id: FlexibleID?
    var ear_tag: String?
    var probe_date: String?
    var nummer: String?
    var status: String?
}

// MARK: - Stall
struct Stall: Codable, Identifiable, Sendable {
    var id: FlexibleID
    var name: String?
}

// MARK: - Dashboard
struct DashboardResponse: Codable {
    var weiterbehandlungen: [DashboardTask]?
    var hemmstoff_faellig: [DashboardTask]?
    var hemmstoff_versendet: [DashboardTask]?
    var tu_faellig: [DashboardTask]?
    var wartezeit_aktiv: [DashboardTask]?
    var counts: DashboardCounts?
}

struct DashboardTask: Codable, Identifiable, Sendable {
    // Stable identifier; the server lists do NOT all include an `id` field
    // (several key only by cattle_id), so decoding must tolerate its absence.
    var id: String
    var cattle_id: FlexibleID?
    var ear_tag: String?
    var name: String?
    var medication: String?
    var dosage: String?
    var type: String?
    var notes: String?
    var nummer: String?
    var treatment_date: String?
    var probe_date: String?
    var last_insemination: String?
    var wartezeit_ende: String?
    var wz_ende: String?

    enum CodingKeys: String, CodingKey {
        case id, cattle_id, ear_tag, name, medication, dosage, type, notes
        case nummer, treatment_date, probe_date, last_insemination, wartezeit_ende, wz_ende
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rawId = try c.decodeIfPresent(FlexibleID.self, forKey: .id)
        let cid = try c.decodeIfPresent(FlexibleID.self, forKey: .cattle_id)
        self.cattle_id = cid
        self.ear_tag = try c.decodeIfPresent(String.self, forKey: .ear_tag)
        self.name = try c.decodeIfPresent(String.self, forKey: .name)
        self.medication = try c.decodeIfPresent(String.self, forKey: .medication)
        self.dosage = try c.decodeIfPresent(String.self, forKey: .dosage)
        self.type = try c.decodeIfPresent(String.self, forKey: .type)
        self.notes = try c.decodeIfPresent(String.self, forKey: .notes)
        self.nummer = try c.decodeIfPresent(String.self, forKey: .nummer)
        self.treatment_date = try c.decodeIfPresent(String.self, forKey: .treatment_date)
        self.probe_date = try c.decodeIfPresent(String.self, forKey: .probe_date)
        self.last_insemination = try c.decodeIfPresent(String.self, forKey: .last_insemination)
        self.wartezeit_ende = try c.decodeIfPresent(String.self, forKey: .wartezeit_ende)
        self.wz_ende = try c.decodeIfPresent(String.self, forKey: .wz_ende)
        if let r = rawId?.value, !r.isEmpty {
            self.id = "r-\(r)"
        } else if let cv = cid?.value, !cv.isEmpty {
            self.id = "c-\(cv)"
        } else {
            self.id = UUID().uuidString
        }
    }

    var displayDate: String? {
        treatment_date ?? wartezeit_ende ?? wz_ende ?? probe_date ?? last_insemination
    }
}

struct DashboardCounts: Codable, Sendable {
    var weiterbehandlungen: Int?
    var hemmstoff_faellig: Int?
    var hemmstoff_versendet: Int?
    var tu_faellig: Int?
    var wartezeit_aktiv: Int?
    var gesamt: Int?
}

// MARK: - Date Helper
enum DateHelper {
    private static let displayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd.MM.yyyy"
        f.locale = Locale(identifier: "de_DE")
        return f
    }()

    private static let parsers: [DateFormatter] = {
        ["yyyy-MM-dd", "yyyy-MM-dd HH:mm:ss"].map { fmt in
            let f = DateFormatter()
            f.dateFormat = fmt
            f.locale = Locale(identifier: "en_US_POSIX")
            return f
        }
    }()

    static func format(_ dateString: String?) -> String {
        guard let str = dateString, !str.isEmpty else { return "\u{2013}" }
        for parser in parsers {
            if let date = parser.date(from: str) {
                return displayFormatter.string(from: date)
            }
        }
        return str
    }

    static func parse(_ dateString: String?) -> Date? {
        guard let str = dateString else { return nil }
        for parser in parsers {
            if let date = parser.date(from: str) { return date }
        }
        return nil
    }

    static func apiString(from date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }
}
