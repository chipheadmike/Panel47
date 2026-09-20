import Foundation

/// A plain immediate-execution calculator (2 + 3 × 4 = 20, left to right, like
/// a desk calculator — not algebraic precedence). Arithmetic uses `Decimal` so
/// 0.1 + 0.2 is 0.3, not a binary-float near miss.
struct CalculatorEngine {
    enum Operation: Equatable {
        case add, subtract, multiply, divide

        var symbol: String {
            switch self {
            case .add: return "+"
            case .subtract: return "\u{2212}"
            case .multiply: return "\u{00D7}"
            case .divide: return "\u{00F7}"
            }
        }

        /// nil means the operation is invalid (divide by zero) or overflowed.
        func apply(_ lhs: Decimal, _ rhs: Decimal) -> Decimal? {
            let result: Decimal
            switch self {
            case .add: result = lhs + rhs
            case .subtract: result = lhs - rhs
            case .multiply: result = lhs * rhs
            case .divide:
                guard rhs != 0 else { return nil }
                result = lhs / rhs
            }
            return result.isNaN ? nil : result
        }
    }

    static let errorText = "ERROR"
    private static let maxEntryDigits = 12

    private(set) var display = "0"
    private(set) var hasError = false

    private var accumulator: Decimal?
    private var pendingOperation: Operation?
    /// Whether the next digit appends to `display` (true) or starts a new number.
    private var isTyping = true
    /// True right after an operator, before the right-hand side is entered.
    private var awaitingOperand = false

    /// e.g. "12 +" while the right-hand side is being entered.
    var expressionLine: String {
        guard let accumulator, let pendingOperation else { return "" }
        return "\(Self.format(accumulator)) \(pendingOperation.symbol)"
    }

    mutating func inputDigit(_ digit: Int) {
        guard (0...9).contains(digit) else { return }
        if hasError { clear() }
        startNewNumberIfNeeded()

        if display == "0" {
            display = String(digit)
            return
        }
        guard display.filter(\.isNumber).count < Self.maxEntryDigits else { return }
        display.append(String(digit))
    }

    mutating func inputDecimalPoint() {
        if hasError { clear() }
        startNewNumberIfNeeded()
        guard !display.contains(".") else { return }
        display.append(".")
    }

    mutating func inputOperation(_ operation: Operation) {
        guard !hasError else { return }

        // Pressing a second operator before entering a number just swaps it.
        if awaitingOperand, pendingOperation != nil {
            pendingOperation = operation
            return
        }

        if let accumulator, let pendingOperation {
            guard let result = pendingOperation.apply(accumulator, currentValue) else { fail(); return }
            self.accumulator = result
            display = Self.format(result)
        } else {
            let value = currentValue
            accumulator = value
            display = Self.format(value)
        }

        pendingOperation = operation
        isTyping = false
        awaitingOperand = true
    }

    mutating func equals() {
        guard !hasError, let accumulator, let pendingOperation else { return }
        guard let result = pendingOperation.apply(accumulator, currentValue) else { fail(); return }

        display = Self.format(result)
        self.accumulator = nil
        self.pendingOperation = nil
        isTyping = false
        awaitingOperand = false
    }

    mutating func clear() {
        self = CalculatorEngine()
    }

    mutating func toggleSign() {
        guard !hasError, display != "0" else { return }
        if display.hasPrefix("-") {
            display.removeFirst()
        } else {
            display = "-" + display
        }
        awaitingOperand = false
    }

    /// Divides the shown value by 100.
    mutating func percent() {
        guard !hasError else { return }
        display = Self.format(currentValue / 100)
        isTyping = false
        awaitingOperand = false
    }

    mutating func backspace() {
        guard !hasError, isTyping else { return }
        display.removeLast()
        if display.isEmpty || display == "-" {
            display = "0"
        }
    }

    /// Maps a typed character to a calculator action. Returns false if the
    /// character isn't one the calculator understands.
    @discardableResult
    mutating func handle(character: Character) -> Bool {
        switch character {
        case _ where character.isASCII && character.isNumber:
            inputDigit(character.wholeNumberValue ?? 0)
        case ".", ",":
            inputDecimalPoint()
        case "+":
            inputOperation(.add)
        case "-", "\u{2212}":
            inputOperation(.subtract)
        case "*", "x", "X", "\u{00D7}":
            inputOperation(.multiply)
        case "/", "\u{00F7}":
            inputOperation(.divide)
        case "=":
            equals()
        case "%":
            percent()
        case "c", "C":
            clear()
        default:
            return false
        }
        return true
    }

    // MARK: - Internals

    private mutating func startNewNumberIfNeeded() {
        guard !isTyping else { return }
        display = "0"
        isTyping = true
        awaitingOperand = false
    }

    private mutating func fail() {
        display = Self.errorText
        hasError = true
        accumulator = nil
        pendingOperation = nil
        isTyping = false
        awaitingOperand = false
    }

    private var currentValue: Decimal {
        let text = display.hasSuffix(".") ? String(display.dropLast()) : display
        return Decimal(string: text) ?? 0
    }

    /// Rounds to 8 decimal places; integers too large for the display switch
    /// to scientific notation.
    static func format(_ value: Decimal) -> String {
        var source = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &source, 8, .plain)

        let text = "\(rounded)"
        let integerPart = text.split(separator: ".").first.map(String.init) ?? text
        if integerPart.filter(\.isNumber).count > maxEntryDigits {
            return String(format: "%.6g", NSDecimalNumber(decimal: rounded).doubleValue)
        }
        return text
    }
}
