import AppKit
import SwiftUI

private let wordmarkCanvas = CGSize(width: 517, height: 256)
private let symbolCanvas = CGSize(width: 256, height: 256)
private let ringWidth: CGFloat = 25
private let iconRingWidth: CGFloat = 29
private let iconCanvasSide: CGFloat = 1024
private let iconTileInset: CGFloat = 100
private let iconTileRadius: CGFloat = 185
private let iconSymbolOrigin = CGPoint(x: 192, y: 184)
private let iconSymbolSide: CGFloat = 640

private func ring(x: CGFloat, top: CGFloat, width: CGFloat) -> Path {
    let outer = CGRect(x: x, y: top - 1, width: 100, height: 114)
    var path = Path(roundedRect: outer, cornerRadius: 34, style: .circular)
    path.addPath(Path(roundedRect: outer.insetBy(dx: width, dy: width), cornerRadius: max(34 - width, 4), style: .circular))
    return path
}

private func letterN(x: CGFloat) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: x, y: 184))
    path.addLine(to: CGPoint(x: x, y: 120))
    path.addArc(center: CGPoint(x: x + 48, y: 120), radius: 48, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
    path.addLine(to: CGPoint(x: x + 96, y: 184))
    path.addLine(to: CGPoint(x: x + 68, y: 184))
    path.addLine(to: CGPoint(x: x + 68, y: 120))
    path.addArc(center: CGPoint(x: x + 48, y: 120), radius: 20, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: true)
    path.addLine(to: CGPoint(x: x + 28, y: 184))
    path.closeSubpath()
    return path
}

private func letterK(x: CGFloat) -> Path {
    var path = Path()
    path.addRect(CGRect(x: x, y: 32, width: 28, height: 152))
    path.addLines([CGPoint(x: x + 28, y: 104), CGPoint(x: x + 60, y: 72), CGPoint(x: x + 99.6, y: 72), CGPoint(x: x + 28, y: 143.6)])
    path.closeSubpath()
    path.addLines([CGPoint(x: x + 50, y: 121.6), CGPoint(x: x + 70, y: 101.6), CGPoint(x: x + 152.4, y: 184), CGPoint(x: x + 112.4, y: 184)])
    path.closeSubpath()
    return path
}

private struct CanvasShape: Shape {
    let canvas: CGSize
    let build: @Sendable () -> Path

    func path(in rect: CGRect) -> Path {
        build().applying(CGAffineTransform(scaleX: rect.width / canvas.width, y: rect.height / canvas.height))
    }
}

private let evenOdd = FillStyle(eoFill: true)

struct NookWordmark: View {
    let height: CGFloat

    var body: some View {
        ZStack {
            CanvasShape(canvas: wordmarkCanvas) {
                var path = letterN(x: 0)
                path.addPath(ring(x: 120, top: 72, width: ringWidth))
                path.addPath(letterK(x: 364))
                return path
            }
            .fill(Theme.text, style: evenOdd)
            CanvasShape(canvas: wordmarkCanvas) { ring(x: 240, top: 54, width: ringWidth) }
                .fill(Theme.lime, style: evenOdd)
        }
        .frame(width: height * wordmarkCanvas.width / wordmarkCanvas.height, height: height)
        .accessibilityLabel("Nook")
    }
}

let symbolLift: CGFloat = 18

struct NookSymbol: View {
    let side: CGFloat
    var strokeWidth: CGFloat = ringWidth
    var swapProgress: CGFloat = 0

    var body: some View {
        let shift = symbolLift * swapProgress * side / symbolCanvas.height
        ZStack {
            CanvasShape(canvas: symbolCanvas) { [strokeWidth] in ring(x: 18, top: 81, width: strokeWidth) }
                .fill(Theme.text, style: evenOdd)
                .offset(y: -shift)
            CanvasShape(canvas: symbolCanvas) { [strokeWidth] in ring(x: 138, top: 63, width: strokeWidth) }
                .fill(Theme.lime, style: evenOdd)
                .offset(y: shift)
        }
        .frame(width: side, height: side)
        .accessibilityLabel("Nook")
    }
}

private struct AppIconArtwork: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: iconTileRadius, style: .continuous)
                .fill(Theme.background)
                .frame(width: iconCanvasSide - 2 * iconTileInset, height: iconCanvasSide - 2 * iconTileInset)
                .offset(x: iconTileInset, y: iconTileInset)
            NookSymbol(side: iconSymbolSide, strokeWidth: iconRingWidth)
                .offset(x: iconSymbolOrigin.x, y: iconSymbolOrigin.y)
        }
        .frame(width: iconCanvasSide, height: iconCanvasSide, alignment: .topLeading)
    }
}

@MainActor
func makeAppIconImage() -> NSImage? {
    ImageRenderer(content: AppIconArtwork()).nsImage
}
