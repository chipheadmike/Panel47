import Testing
@testable import Panel47

struct CalculatorEngineTests {
    /// Feeds a string of keystrokes through the same mapping the keyboard uses.
    private func run(_ keys: String) -> CalculatorEngine {
        var engine = CalculatorEngine()
        for character in keys {
            engine.handle(character: character)
        }
        return engine
    }

    @Test func startsAtZero() {
        #expect(CalculatorEngine().display == "0")
    }

    @Test func enteringDigitsBuildsANumber() {
        #expect(run("123").display == "123")
    }

    @Test func leadingZerosDontStack() {
        #expect(run("007").display == "7")
    }

    @Test func decimalPointStartsWithZeroAndOnlyAppliesOnce() {
        #expect(run(".5").display == "0.5")
        #expect(run("1.2.3").display == "1.23")
    }

    @Test func entryIsCappedAtTwelveDigits() {
        #expect(run("1234567890123456").display == "123456789012")
    }

    @Test func basicArithmetic() {
        #expect(run("2+3=").display == "5")
        #expect(run("9-4=").display == "5")
        #expect(run("6*7=").display == "42")
        #expect(run("8/2=").display == "4")
    }

    @Test func chainsLeftToRightLikeADeskCalculator() {
        #expect(run("2+3*4=").display == "20")
    }

    @Test func intermediateResultShowsWhenChaining() {
        #expect(run("2+3+").display == "5")
    }

    @Test func decimalsAreExactNotFloatingPoint() {
        #expect(run("0.1+0.2=").display == "0.3")
    }

    @Test func divisionRoundsToEightPlaces() {
        #expect(run("1/3=").display == "0.33333333")
    }

    @Test func divideByZeroShowsErrorAndRecoversOnNextDigit() {
        var engine = run("5/0=")
        #expect(engine.display == CalculatorEngine.errorText)
        #expect(engine.hasError)

        engine.inputOperation(.add) // operators are ignored while in error
        #expect(engine.hasError)

        engine.inputDigit(7)
        #expect(engine.display == "7")
        #expect(engine.hasError == false)
    }

    @Test func clearResetsEverything() {
        var engine = run("5+3")
        engine.clear()
        #expect(engine.display == "0")
        #expect(engine.expressionLine == "")
        #expect(engine.hasError == false)
    }

    @Test func toggleSignFlipsAndZeroStaysZero() {
        var engine = run("5")
        engine.toggleSign()
        #expect(engine.display == "-5")
        engine.toggleSign()
        #expect(engine.display == "5")

        var zero = CalculatorEngine()
        zero.toggleSign()
        #expect(zero.display == "0")
    }

    @Test func percentDividesByOneHundred() {
        var engine = run("50")
        engine.percent()
        #expect(engine.display == "0.5")
    }

    @Test func percentMidExpressionKeepsThePendingOperation() {
        var engine = run("5+50")
        engine.percent()
        engine.equals()
        #expect(engine.display == "5.5")
    }

    @Test func backspaceRemovesTheLastCharacter() {
        var engine = run("123")
        engine.backspace()
        #expect(engine.display == "12")

        var single = run("5")
        single.backspace()
        #expect(single.display == "0")

        var negative = run("5")
        negative.toggleSign()
        negative.backspace()
        #expect(negative.display == "0")
    }

    @Test func backspaceDoesNothingToAResult() {
        var engine = run("2+3=")
        engine.backspace()
        #expect(engine.display == "5")
    }

    @Test func secondOperatorReplacesTheFirst() {
        #expect(run("5+*3=").display == "15")
    }

    @Test func typingAfterEqualsStartsANewNumber() {
        #expect(run("2+3=7").display == "7")
    }

    @Test func operatingOnAResultContinuesFromIt() {
        #expect(run("2+3=*4=").display == "20")
    }

    @Test func expressionLineShowsThePendingOperation() {
        #expect(run("12+").expressionLine == "12 +")
        #expect(run("12+3").expressionLine == "12 +")
        #expect(run("12+3=").expressionLine == "")
    }

    @Test func hugeResultsSwitchToScientificNotation() {
        let display = run("999999999999*999999999999=").display
        #expect(display.contains("e"))
    }

    @Test func unknownCharactersAreIgnored() {
        var engine = CalculatorEngine()
        #expect(engine.handle(character: "q") == false)
        #expect(engine.display == "0")
    }
}
