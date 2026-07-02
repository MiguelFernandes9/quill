#if targetEnvironment(macCatalyst)
import SwiftUI
import PencilKit

/// Mac drawing tools. Catalyst's PKToolPicker palette is unreliable (and its
/// first-responder machinery was implicated in the input-hijack bug), so the
/// Mac builds its own strip: tool, color, and width — all in the pen-free bar
/// region. Selection persists across launches.
struct MacToolStrip: View {
    @Binding var tool: PKTool

    @AppStorage("macTool") private var toolName = "pen"
    @AppStorage("macColor") private var colorName = "black"
    @AppStorage("macWidth") private var width = 4.0

    private static let inks: [(name: String, ink: PKInkingTool.InkType, icon: String)] = [
        ("pen", .pen, "pencil.tip"),
        ("marker", .marker, "paintbrush.pointed.fill"),
        ("pencil", .pencil, "pencil"),
    ]

    private static let colors: [(name: String, color: UIColor)] = [
        ("black", .label), ("blue", .systemBlue), ("red", .systemRed),
        ("green", .systemGreen), ("orange", .systemOrange), ("purple", .systemPurple),
    ]

    var body: some View {
        HStack(spacing: 10) {
            // Tools
            HStack(spacing: 2) {
                ForEach(Self.inks, id: \.name) { ink in
                    toolButton(icon: ink.icon, selected: toolName == ink.name) {
                        toolName = ink.name
                        rebuildTool()
                    }
                }
                toolButton(icon: "eraser", selected: toolName == "eraser") {
                    toolName = "eraser"
                    rebuildTool()
                }
            }

            Divider().frame(height: 16)

            // Colors
            HStack(spacing: 5) {
                ForEach(Self.colors, id: \.name) { entry in
                    Button {
                        colorName = entry.name
                        if toolName == "eraser" { toolName = "pen" } // picking a color implies inking
                        rebuildTool()
                    } label: {
                        Circle()
                            .fill(Color(uiColor: entry.color))
                            .frame(width: 15, height: 15)
                            .overlay(Circle().stroke(Color.accentColor,
                                                     lineWidth: colorName == entry.name ? 2 : 0))
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider().frame(height: 16)

            // Width
            Slider(value: $width, in: 1...24, step: 1) { editing in
                if !editing { rebuildTool() }
            }
            .frame(width: 84)
        }
        .onAppear { rebuildTool() }
    }

    private func toolButton(icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 28, height: 26)
                .background(selected ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear),
                            in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private func rebuildTool() {
        if toolName == "eraser" {
            tool = PKEraserTool(.vector)
            return
        }
        let ink = Self.inks.first { $0.name == toolName }?.ink ?? .pen
        let color = Self.colors.first { $0.name == colorName }?.color ?? .label
        tool = PKInkingTool(ink, color: color, width: width)
    }
}
#endif
