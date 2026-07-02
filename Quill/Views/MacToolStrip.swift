#if targetEnvironment(macCatalyst)
import SwiftUI
import PencilKit

/// Mac tool switcher (mock 4a): a segmented control of five icon tools —
/// Pen, Marker, Pencil, Eraser, and **Text** — plus ink colors and a width
/// slider. Text is a tool, not a mode: selecting it drives `textActive`
/// (the old `editingTexts`), and leaving text mode from outside (Esc) snaps
/// the switcher back to Pen. Selection persists across launches.
struct MacToolStrip: View {
    @Binding var tool: PKTool
    @Binding var textActive: Bool

    @AppStorage("macTool") private var toolName = "pen"
    @AppStorage("macColor") private var colorName = "black"
    @AppStorage("macWidth") private var width = 4.0

    private static let inks: [(name: String, ink: PKInkingTool.InkType, icon: String, help: String)] = [
        ("pen", .pen, "pencil.tip", "Pen"),
        ("marker", .marker, "paintbrush.pointed.fill", "Marker"),
        ("pencil", .pencil, "pencil", "Pencil"),
    ]

    var body: some View {
        HStack(spacing: 12) {
            switcher

            colorSquares
                .opacity(textActive ? 0.35 : 1)
                .disabled(textActive)
                .animation(.easeInOut(duration: 0.15), value: textActive)

            Slider(value: $width, in: 1...24, step: 1) { editing in
                if !editing { apply() }
            }
            .tint(Color(uiColor: selectedUIColor))
            .frame(width: 110)
            .opacity(textActive ? 0.35 : 1)
            .disabled(textActive)
            .animation(.easeInOut(duration: 0.15), value: textActive)
        }
        .onAppear { apply() }
        .onChange(of: textActive) { _, active in
            // Esc (or any outside exit) while the Text tool is selected snaps
            // the switcher back to Pen.
            if !active && toolName == "text" {
                toolName = "pen"
                apply()
            }
        }
    }

    // MARK: - Segmented switcher

    private var switcher: some View {
        HStack(spacing: 1) {
            ForEach(Self.inks, id: \.name) { ink in
                segment(icon: ink.icon, name: ink.name, help: ink.help)
            }
            segment(icon: "eraser", name: "eraser", help: "Eraser")
            segment(icon: "character.cursor.ibeam", name: "text", help: "Text")
        }
        .padding(2)
        .background(QuillTheme.hairlineInner, in: RoundedRectangle(cornerRadius: 8))
    }

    private func segment(icon: String, name: String, help: String) -> some View {
        let selected = toolName == name
        let isText = name == "text"
        return Button {
            toolName = name
            apply()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(selected && isText ? .white : QuillTheme.ink)
                .frame(width: 36, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(selected ? (isText ? QuillTheme.accent : QuillTheme.surface) : .clear)
                        .shadow(color: selected && !isText ? .black.opacity(0.12) : .clear,
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
                    // Picking a color while Eraser/Text is active implies inking.
                    if toolName == "eraser" || toolName == "text" { toolName = "pen" }
                    apply()
                } label: {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color(uiColor: entry.ui))
                        .frame(width: 17, height: 17)
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
        textActive = toolName == "text"
        if toolName == "eraser" {
            tool = PKEraserTool(.vector)
        } else if toolName != "text" {
            let ink = Self.inks.first { $0.name == toolName }?.ink ?? .pen
            tool = PKInkingTool(ink, color: selectedUIColor, width: width)
        }
    }
}
#endif
