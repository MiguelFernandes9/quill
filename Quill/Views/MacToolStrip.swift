#if targetEnvironment(macCatalyst)
import SwiftUI
import PencilKit

/// Mac tool switcher (mock 4a): a segmented control of four icon tools —
/// Pen, Marker, Pencil, Eraser — plus ink colors and a width slider. Text is
/// no longer a tool: click-and-hold on the canvas inserts a block where the
/// mouse is (matching the iPad's press), so drawing tools stay live and the
/// canvas keeps scrolling. Selection persists across launches.
struct MacToolStrip: View {
    @Binding var tool: PKTool

    @AppStorage("macTool") private var toolName = "pen"
    @AppStorage("macColor") private var colorName = "black"
    @AppStorage("macWidth") private var width = 4.0
    /// "vector" removes whole strokes; "bitmap" erases pixels under the tip.
    @AppStorage("macEraser") private var eraserMode = "vector"

    private static let inks: [(name: String, ink: PKInkingTool.InkType, icon: String, help: String)] = [
        ("pen", .pen, "pencil.tip", "Pen"),
        ("marker", .marker, "paintbrush.pointed.fill", "Marker"),
        ("pencil", .pencil, "pencil", "Pencil"),
    ]

    var body: some View {
        HStack(spacing: 12) {
            switcher

            if toolName == "eraser" {
                eraserModeToggle
            }

            colorSquares

            Slider(value: $width, in: 1...24, step: 1) { editing in
                if !editing { apply() }
            }
            .tint(Color(uiColor: selectedUIColor))
            .frame(width: 130)
        }
        .onAppear {
            // Migration: "text" was a persisted tool before it became the
            // click-and-hold gesture.
            if toolName == "text" { toolName = "pen" }
            apply()
        }
    }

    // MARK: - Segmented switcher

    private var switcher: some View {
        HStack(spacing: 1) {
            ForEach(Self.inks, id: \.name) { ink in
                segment(icon: ink.icon, name: ink.name, help: ink.help)
            }
            segment(icon: "eraser", name: "eraser", help: "Eraser")
        }
        .padding(2)
        .background(QuillTheme.hairlineInner, in: RoundedRectangle(cornerRadius: 8))
    }

    private func segment(icon: String, name: String, help: String) -> some View {
        let selected = toolName == name
        return Button {
            toolName = name
            apply()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(QuillTheme.ink)
                .frame(width: 42, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(selected ? QuillTheme.surface : .clear)
                        .shadow(color: selected ? .black.opacity(0.12) : .clear,
                                radius: 1.5, y: 0.5)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: - Eraser modes (only shown while the eraser is selected)

    private var eraserModeToggle: some View {
        HStack(spacing: 1) {
            eraserSegment(mode: "vector", icon: "scribble", help: "Erase whole strokes")
            eraserSegment(mode: "bitmap", icon: "circle.dotted", help: "Erase pixels")
        }
        .padding(2)
        .background(QuillTheme.hairlineInner, in: RoundedRectangle(cornerRadius: 8))
    }

    private func eraserSegment(mode: String, icon: String, help: String) -> some View {
        Button {
            eraserMode = mode
            apply()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(QuillTheme.ink)
                .frame(width: 32, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(eraserMode == mode ? QuillTheme.surface : .clear)
                        .shadow(color: eraserMode == mode ? .black.opacity(0.12) : .clear,
                                radius: 1.5, y: 0.5)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: - Colors (17pt squares, accent ring when selected)

    private var colorSquares: some View {
        HStack(spacing: 7) {
            ForEach(QuillTheme.inkPalette, id: \.name) { entry in
                Button {
                    colorName = entry.name
                    // Picking a color while the Eraser is active implies inking.
                    if toolName == "eraser" { toolName = "pen" }
                    apply()
                } label: {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color(uiColor: entry.ui))
                        .frame(width: 20, height: 20)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6.5)
                                .stroke(QuillTheme.accent, lineWidth: 1.5)
                                .padding(-3.5)
                                .opacity(colorName == entry.name ? 1 : 0)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 4) // room for the selection ring
    }

    // MARK: - Apply

    private var selectedUIColor: UIColor {
        QuillTheme.inkPalette.first { $0.name == colorName }?.ui ?? .label
    }

    private func apply() {
        if toolName == "eraser" {
            tool = eraserMode == "bitmap"
                ? PKEraserTool(.bitmap, width: max(width * 3, 12))
                : PKEraserTool(.vector)
        } else {
            let ink = Self.inks.first { $0.name == toolName }?.ink ?? .pen
            tool = PKInkingTool(ink, color: selectedUIColor, width: width)
        }
    }
}
#endif
