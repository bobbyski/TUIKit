import Foundation
import TUIKit

// MARK: - Contact Book model (global, JSON-backed)

/// One editable contact. `@Bound` projects a `$` binding per field, so the
/// Contact Book form binds with `field.bind(person.$name)`.
///
/// It's a `class` (reference type) on purpose: a binding is a two-way link, and
/// `save()` writes back through it, so the model must be shared by reference —
/// a `struct` copy wouldn't see the control's edits.
@MainActor
final class Person {
    @Bound var name = ""
    @Bound var birthday: Date = Date()   // edited with a DatePicker (calendar control)
    @Bound var address = ""
    @Bound var notes = ""
}

/// JSON transport (Codable); `Person` is a bindable class, so we decode into
/// this and map across. `birthday` is an ISO `yyyy-MM-dd` string here and a
/// `Date` on `Person`; the `deathday` key in the seed JSON is simply ignored.
private struct PersonData: Codable {
    var name: String
    var birthday: String
    var address: String
    var notes: String
}

/// The one, global contact list. It lives for the whole run, so closing and
/// reopening a Contact Book window shows edits made earlier (no on-disk
/// persistence between runs — as specified).
@MainActor
final class ContactStore {
    static let shared = ContactStore()

    private(set) var people: [Person] = []
    private var loaded = false

    /// Every contact whose address is unknown falls back to the White House.
    static let whiteHouse = "1600 Pennsylvania Avenue NW, Washington, DC 20500"

    /// One UTC Gregorian calendar shared by the parser, the `DatePicker`, and
    /// the table — so a parsed date shows the same day everywhere.
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }()

    /// `yyyy-MM-dd` ↔ `Date` on the shared calendar (parses the seed JSON).
    static let isoFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// Human-readable US date for display (e.g. "Feb 22, 1732").
    static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateStyle = .medium
        return formatter
    }()

    /// Decodes the bundled `presidents.json` resource once, at startup.
    func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true

        let json = Bundle.module.url(forResource: "presidents", withExtension: "json")
            .flatMap { try? Data(contentsOf: $0) } ?? Data()
        let decoded = (try? JSONDecoder().decode([PersonData].self, from: json)) ?? []
        people = decoded.map { data in
            let person = Person()
            person.name = data.name
            person.birthday = Self.isoFormatter.date(from: data.birthday) ?? Date()
            person.address = data.address.isEmpty ? Self.whiteHouse : data.address
            person.notes = data.notes
            return person
        }
    }

    /// Appends a blank contact and returns it.
    @discardableResult
    func add() -> Person {
        let person = Person()
        people.append(person)
        return person
    }
}
