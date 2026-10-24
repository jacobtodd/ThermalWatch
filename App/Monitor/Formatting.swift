import Foundation

enum Formatting {
    static func temperature(_ celsius: Double?, fahrenheit: Bool) -> String {
        guard let celsius else { return "—°" }
        let value = fahrenheit ? celsius * 9 / 5 + 32 : celsius
        return "\(Int(value.rounded()))°"
    }

    static func percent(_ fraction: Double?) -> String {
        guard let fraction else { return "—%" }
        return "\(Int((fraction * 100).rounded()))%"
    }

    static func menuBarTitle(temperature: Double?, load: Double?, showLoad: Bool, fahrenheit: Bool) -> String {
        let temp = Self.temperature(temperature, fahrenheit: fahrenheit)
        return showLoad ? "\(temp) · \(percent(load))" : temp
    }

    static func rpm(_ value: Double) -> String {
        "\(Int(value.rounded()).formatted(.number.grouping(.automatic))) rpm"
    }
}
