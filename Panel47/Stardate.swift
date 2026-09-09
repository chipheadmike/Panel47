import Foundation

/// Star Trek never had one consistent stardate formula, but the TNG Writer's
/// Technical Manual established the closest thing to an official one: each
/// year is 1000 units, and the fractional part is how far through the year
/// you are. That manual anchors it at 2323 (the 24th-century setting), which
/// goes deeply negative for any real date — so this re-anchors the same
/// linear formula at year 2000 instead, purely for a sensible-looking number.
enum Stardate {
    static func string(for date: Date = Date(), calendar: Calendar = .current) -> String {
        String(format: "%.1f", value(for: date, calendar: calendar))
    }

    static func value(for date: Date = Date(), calendar: Calendar = .current) -> Double {
        let year = calendar.component(.year, from: date)
        let dayOfYear = calendar.ordinality(of: .day, in: .year, for: date) ?? 1
        let daysInYear = calendar.range(of: .day, in: .year, for: date)?.count ?? 365

        let startOfDay = calendar.startOfDay(for: date)
        let secondsIntoDay = date.timeIntervalSince(startOfDay)
        let daysElapsed = Double(dayOfYear - 1) + secondsIntoDay / 86400

        let yearFraction = daysElapsed / Double(daysInYear)
        return Double(year - 2000) * 1000 + yearFraction * 1000
    }
}
