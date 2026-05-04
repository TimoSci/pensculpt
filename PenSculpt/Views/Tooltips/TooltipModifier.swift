import SwiftUI

struct TooltipView: View {
    let content: TooltipContent

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(content.title)
                .font(.callout.weight(.medium))
            if let subtitle = content.subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: 240, alignment: .leading)
    }
}

struct TooltipModifier: ViewModifier {
    let id: TooltipID
    @AppStorage("tooltipsEnabled") private var tooltipsEnabled = true
    @State private var isShowing = false
    @State private var hoverTask: Task<Void, Never>?
    @State private var longPressDismissTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onContinuousHover { phase in
                guard tooltipsEnabled else { return }
                handleHover(phase)
            }
            .onLongPressGesture(minimumDuration: 0.5) {
                guard tooltipsEnabled else { return }
                showFromLongPress()
            }
            .popover(isPresented: $isShowing) {
                TooltipView(content: id.content)
                    .presentationCompactAdaptation(.popover)
            }
    }

    private func handleHover(_ phase: HoverPhase) {
        switch phase {
        case .active:
            hoverTask?.cancel()
            hoverTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.15)) { isShowing = true }
            }
        case .ended:
            hoverTask?.cancel()
            hoverTask = nil
            withAnimation(.easeOut(duration: 0.1)) { isShowing = false }
        }
    }

    private func showFromLongPress() {
        longPressDismissTask?.cancel()
        withAnimation(.easeOut(duration: 0.15)) { isShowing = true }
        longPressDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.1)) { isShowing = false }
        }
    }
}

extension View {
    func tooltip(_ id: TooltipID) -> some View {
        modifier(TooltipModifier(id: id))
    }
}
