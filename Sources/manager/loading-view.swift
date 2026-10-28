import SwiftUI

let loadingSymbolSide: CGFloat = 128
let loadingMessage = "Warming up your nooklets…"
let loadingCycle: Double = 1.2

struct LoadingView: View {
    @Environment(\.accessibilityReduceMotion) private var isMotionReduced
    @State private var isSwapped = false

    var body: some View {
        VStack(spacing: 0) {
            NookSymbol(side: loadingSymbolSide, swapProgress: isSwapped ? 1 : 0)
            Text(loadingMessage)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.faint)
        }
            .padding(.bottom, 52)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .combine)
            .onAppear {
                guard !isMotionReduced else { return }
                withAnimation(.easeInOut(duration: loadingCycle).repeatForever(autoreverses: true)) {
                    isSwapped = true
                }
            }
    }
}
