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

// MARK: - FlexibleInt (handles Int or numeric String from API)
struct FlexibleInt: Codable, Hashable, Sendable {
    let value: Int
    init(_ v: Int) { value = v }
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let i = try? c.decode(Int.self) { value = i }
        else if let s = try? c.decode(String.self), let i = Int(s) { value = i }
        else if let d = try? c.decode(Double.self) { value = Int(d) }
        else { value = 0 }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(value)
    }
}

// MARK: - Ear Tag Formatter
/// Formatiert eine Ohrmarkennummer in lesbare Blöcke (z. B. "09 587 12345"),
/// identisch zur Server-Funktion formatEarTag() in includes/functions.php.
enum EarTagFormatter {
    static func format(_ raw: String?) -> String {
        let clean = (raw ?? "").replacingOccurrences(of: " ", with: "")
        if clean.isEmpty { return "" }
        let chars = Array(clean)
        let part1 = String(chars.prefix(2))
        let part2 = chars.count > 2 ? String(chars[2..<min(5, chars.count)]) : ""
        let part3 = chars.count > 5 ? String(chars[5...]) : ""
        var out = part1
        if !part2.isEmpty { out += " " + part2 }
        if !part3.isEmpty { out += " " + part3 }
        return out
    }
}

// MARK: - Behandlungsarten
/// Katalog der Behandlungsarten, identisch zu treatmentTypes() in includes/functions.php.
enum TreatmentTypeCatalog {
    static let all: [String] = ["Injektion", "drenchen", "Eutertube", "Trockenstellen", "Hemmstoff Probe", "Klauenpflege", "Sonstige"]
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
    var stillbirths: [Stillbirth]?

    var displayTag: String {
        let f = EarTagFormatter.format(ear_tag)
        return f.isEmpty ? "Unbekannt" : f
    }
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

// MARK: - PlannedTreatment (geplante Behandlung)
struct PlannedTreatment: Codable, Identifiable, Sendable {
    var id: FlexibleID
    var cattle_id: FlexibleID?
    var ear_tag: String?
    var planned_date: String?
    var medication: String?
    var dosage: String?
    var type: String?
    var notes: String?
    var status: String?
    var treatment_id: FlexibleID?
    var created_at: String?
    var done_at: String?
    var tage_ueberfaellig: FlexibleInt?

    var displayTag: String {
        let f = EarTagFormatter.format(ear_tag)
        return f.isEmpty ? "Unbekannt" : f
    }
    /// Tage überfällig (>0 = überfällig, 0 = heute fällig).
    var overdueDays: Int { tage_ueberfaellig?.value ?? 0 }
}

// MARK: - Stillbirth (Totgeburt)
struct Stillbirth: Codable, Identifiable, Sendable {
    var id: FlexibleID
    var mother_cattle_id: FlexibleID?
    var mother_ear_tag: String?
    var birth_date: String?
    var sex: String?
    var comment: String?
    var created_at: String?
}

// MARK: - Group Actions
struct GroupAnimal: Codable, Identifiable, Sendable {
    var id: FlexibleID
    var ear_tag: String?
    var rasse: String?
    var geschlecht: String?

    var displayTag: String {
        let f = EarTagFormatter.format(ear_tag)
        return f.isEmpty ? "Unbekannt" : f
    }
}

struct GroupActionResult: Codable, Sendable {
    var action: String?
    var processed: Int?
    var cattle_ids: [FlexibleID]?
}

struct PlannedCompleteResult: Codable, Sendable {
    var planned_treatment: PlannedTreatment?
    var treatment: Treatment?
}

// MARK: - Dashboard
struct DashboardResponse: Codable {
    var weiterbehandlungen: [DashboardTask]?
    var hemmstoff_faellig: [DashboardTask]?
    var hemmstoff_versendet: [DashboardTask]?
    var tu_faellig: [DashboardTask]?
    var wartezeit_aktiv: [DashboardTask]?
    var geplante_faellig: [PlannedTreatment]?
    var counts: DashboardCounts?
    var kennzahlen: DashboardKennzahlen?
}

struct DashboardKennzahlen: Codable, Sendable {
    var milchkuehe: FlexibleInt?
    var trockensteher: FlexibleInt?
    var milchkueheCount: Int { milchkuehe?.value ?? 0 }
    var trockensteherCount: Int { trockensteher?.value ?? 0 }
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

    var displayTag: String {
        let f = EarTagFormatter.format(ear_tag)
        return f.isEmpty ? "Unbekannt" : f
    }
}

struct DashboardCounts: Codable, Sendable {
    var weiterbehandlungen: Int?
    var hemmstoff_faellig: Int?
    var hemmstoff_versendet: Int?
    var tu_faellig: Int?
    var wartezeit_aktiv: Int?
    var geplante_faellig: Int?
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
