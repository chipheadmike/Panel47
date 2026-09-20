import SwiftUI

/// The calculator viewscreen: a recessed readout over a keypad of LCARS pills.
/// Works with the mouse and the keyboard (digits, + - * /, =, Return, Delete,
/// Escape, % and C).
struct LCARSCalculatorView: View {
    @Binding var engine: CalculatorEngine
    var onKeyPress: () -> Void = {}

    @FocusState private var focused: Bool

    private struct Key: Identifiable {
        let id = UUID()
        let title: String
        let color: Color
        var span = 1
        /// Antonio draws punctuation small, so symbol keys are set larger.
        var isSymbol = false
        let action: (inout CalculatorEngine) -> Void
    }

    private var rows: [[Key]] {
        [
            [
                Key(title: "C", color: LCARSColor.alertRed) { $0.clear() },
                Key(title: "\u{00B1}", color: LCARSColor.lilac, isSymbol: true) { $0.toggleSign() },
                Key(title: "%", color: LCARSColor.lilac) { $0.percent() },
                Key(title: "\u{00F7}", color: LCARSColor.orange, isSymbol: true) { $0.inputOperation(.divide) },
            ],
            [
                digit(7), digit(8), digit(9),
                Key(title: "\u{00D7}", color: LCARSColor.orange, isSymbol: true) { $0.inputOperation(.multiply) },
            ],
            [
                digit(4), digit(5), digit(6),
                Key(title: "\u{2212}", color: LCARSColor.orange, isSymbol: true) { $0.inputOperation(.subtract) },
            ],
            [
                digit(1), digit(2), digit(3),
                Key(title: "+", color: LCARSColor.orange, isSymbol: true) { $0.inputOperation(.add) },
            ],
            [
                Key(title: "0", color: LCARSColor.peach, span: 2) { $0.inputDigit(0) },
                Key(title: ".", color: LCARSColor.peach, isSymbol: true) { $0.inputDecimalPoint() },
                Key(title: "=", color: LCARSColor.paleCanary, isSymbol: true) { $0.equals() },
            ],
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("CALCULATOR")
                .font(LCARSFont.antonio(44, weight: 700))
                .foregroundStyle(LCARSColor.textOnBlack)

            readout
            keypad
        }
        .frame(maxWidth: 560)
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(LCARSColor.background)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onAppear { focused = true }
        .onKeyPress(phases: .down) { press in handle(press) }
    }

    private var readout: some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: 30, bottomLeadingRadius: 0,
            bottomTrailingRadius: 30, topTrailingRadius: 0
        )

        return VStack(alignment: .trailing, spacing: 0) {
            Text(engine.expressionLine.isEmpty ? " " : engine.expressionLine)
                .font(LCARSFont.antonio(20, weight: 400))
                .tracking(1)
                .foregroundStyle(.gray)

            Text(engine.display)
                .font(LCARSFont.antonio(72, weight: 700))
                .foregroundStyle(engine.hasError ? LCARSColor.alertRed : LCARSColor.textOnBlack)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
        .background(shape.fill(Color.white.opacity(0.04)))
        .overlay(shape.stroke(LCARSColor.orange.opacity(0.5), lineWidth: 2))
    }

    private var keypad: some View {
        GeometryReader { geometry in
            let spacing: CGFloat = 8
            let column = (geometry.size.width - spacing * 3) / 4

            VStack(spacing: spacing) {
                ForEach(rows.indices, id: \.self) { rowIndex in
                    HStack(spacing: spacing) {
                        ForEach(rows[rowIndex]) { key in
                            keyButton(key)
                                .frame(width: column * CGFloat(key.span) + spacing * CGFloat(key.span - 1))
                        }
                    }
                    .frame(maxHeight: 84)
                }
            }
        }
    }

    private func keyButton(_ key: Key) -> some View {
        Button {
            onKeyPress()
            key.action(&engine)
        } label: {
            // The label is an overlay so the (large) text can't set the key's minimum
            // height — otherwise the keypad can't shrink to fit a short window.
            Capsule()
                .fill(LCARSColor.gloss(key.color))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay {
                    Text(key.title)
                        .font(LCARSFont.antonio(key.isSymbol ? 60 : 32, weight: 700))
                        .foregroundStyle(.black)
                        .offset(y: key.isSymbol ? (key.title == "." ? -24 : -10) : 0) // Antonio sets punctuation low in the line box
                }
        }
        .buttonStyle(.plain)
    }

    private func digit(_ value: Int) -> Key {
        Key(title: String(value), color: LCARSColor.peach) { $0.inputDigit(value) }
    }

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        // Leave Command/Control shortcuts (copy, quit, ...) to the system.
        guard !press.modifiers.contains(.command), !press.modifiers.contains(.control) else {
            return .ignored
        }

        switch press.key {
        case .return:
            onKeyPress()
            engine.equals()
            return .handled
        case .delete:
            onKeyPress()
            engine.backspace()
            return .handled
        case .escape:
            onKeyPress()
            engine.clear()
            return .handled
        default:
            guard let character = press.characters.first else { return .ignored }
            var updated = engine
            guard updated.handle(character: character) else { return .ignored }
            onKeyPress()
            engine = updated
            return .handled
        }
    }
}
