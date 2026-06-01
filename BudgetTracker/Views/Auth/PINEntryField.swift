import SwiftUI

/// Visible numeric PIN entry — the previous 1×1 hidden `SecureField` did not receive taps on device.
struct PINEntryField: View {
    @Binding var pin: String
    let length: Int
    var prompt: String = "Enter PIN"

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                ForEach(0..<length, id: \.self) { index in
                    Circle()
                        .strokeBorder(isFocused ? Color.accentColor : Color.secondary, lineWidth: 1.5)
                        .background(
                            Circle().fill(index < pin.count ? Color.primary : Color.clear)
                        )
                        .frame(width: 14, height: 14)
                }
            }

            TextField(prompt, text: $pin)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .multilineTextAlignment(.center)
                .font(.title2.monospacedDigit())
                .focused($isFocused)
                .frame(maxWidth: 280)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityLabel(prompt)
        }
        .onAppear {
            pin = sanitized(pin)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                isFocused = true
            }
        }
        .onChange(of: pin) { _, newValue in
            let cleaned = sanitized(newValue)
            if cleaned != newValue {
                pin = cleaned
            }
        }
    }

    private func sanitized(_ value: String) -> String {
        let digits = value.filter(\.isNumber)
        return String(digits.prefix(length))
    }
}
