import SwiftUI

struct TooltipsToggleButton: View {
    @AppStorage("tooltipsEnabled") private var tooltipsEnabled = true

    var body: some View {
        Button {
            tooltipsEnabled.toggle()
        } label: {
            Image(systemName: tooltipsEnabled ? "questionmark.circle.fill" : "questionmark.circle")
                .font(.body)
                .foregroundStyle(tooltipsEnabled ? .blue : .secondary)
        }
        .tooltip(.tooltipsToggle)
    }
}
