import SwiftUI

struct ColorPickerPopover: View {
    let activeColor: CodableColor
    let recentColors: [CodableColor]
    var onSelectPreset: (CodableColor) -> Void
    var onSelectCustom: (CodableColor) -> Void

    @State private var customColor: Color = .black
    @Environment(\.dismiss) private var dismiss

    static let presets: [CodableColor] = [
        CodableColor(red: 0.00, green: 0.00, blue: 0.00, alpha: 1),
        CodableColor(red: 1.00, green: 1.00, blue: 1.00, alpha: 1),
        CodableColor(red: 0.70, green: 0.70, blue: 0.70, alpha: 1),
        CodableColor(red: 0.35, green: 0.35, blue: 0.35, alpha: 1),
        CodableColor(red: 0.90, green: 0.15, blue: 0.15, alpha: 1),
        CodableColor(red: 0.95, green: 0.55, blue: 0.10, alpha: 1),
        CodableColor(red: 0.98, green: 0.85, blue: 0.15, alpha: 1),
        CodableColor(red: 0.25, green: 0.75, blue: 0.30, alpha: 1),
        CodableColor(red: 0.15, green: 0.45, blue: 0.95, alpha: 1),
        CodableColor(red: 0.60, green: 0.25, blue: 0.85, alpha: 1),
    ]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 5)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Presets")
                .font(.caption).foregroundStyle(.secondary)
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(Self.presets, id: \.self) { preset in
                    swatch(for: preset)
                        .onTapGesture {
                            onSelectPreset(preset)
                            dismiss()
                        }
                }
            }

            if !recentColors.isEmpty {
                Text("Recentes")
                    .font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    ForEach(recentColors, id: \.self) { color in
                        swatch(for: color)
                            .onTapGesture {
                                onSelectCustom(color)
                                dismiss()
                            }
                    }
                    Spacer()
                }
            }

            Divider()

            ColorPicker("Personalizar…", selection: $customColor, supportsOpacity: true)
                .onChange(of: customColor) { _, newValue in
                    onSelectCustom(CodableColor(newValue))
                }
        }
        .padding(16)
        .frame(width: 260)
        .onAppear { customColor = Color(activeColor) }
    }

    private func swatch(for color: CodableColor) -> some View {
        Circle()
            .fill(Color(color))
            .frame(width: 32, height: 32)
            .overlay(Circle().stroke(Color.primary.opacity(0.3), lineWidth: 1))
            .overlay(
                Circle()
                    .stroke(Color.accentColor, lineWidth: color == activeColor ? 3 : 0)
            )
    }
}

extension CodableColor: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(red); hasher.combine(green); hasher.combine(blue); hasher.combine(alpha)
    }
}

extension Color {
    init(_ c: CodableColor) {
        self.init(.sRGB, red: Double(c.red), green: Double(c.green), blue: Double(c.blue), opacity: Double(c.alpha))
    }
}

extension CodableColor {
    init(_ color: Color) {
        let ui = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        self.init(red: r, green: g, blue: b, alpha: a)
    }
}
