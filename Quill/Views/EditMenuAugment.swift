import UIKit
import PencilKit
import ObjectiveC

/// Adds Quill's "add text block" action to PencilKit's own edit menu — the
/// "Select All | Insert Space" callout on an iPad finger tap, which Catalyst
/// presents as the Mac's right-click menu (the same machinery serves both).
///
/// PencilKit exposes no menu API and its `UIEditMenuInteraction` delegate is
/// read-only, so the delegate's menu method is augmented at runtime: the
/// original implementation runs first, then the result is reworked. The press
/// point comes from the menu configuration's `sourcePoint`. Everything is
/// discovered dynamically — no private names — and any lookup failure
/// degrades to the stock menu.
enum EditMenuAugment {

    /// The canvas whose menu gets the extra action (one pad open at a time).
    /// Also gates the text-input suppression: while nil (no pad open), text
    /// menus behave normally everywhere.
    static weak var activeCanvas: GrowingCanvasView?

    /// How an augmented delegate class treats its menu.
    private enum Rule {
        /// PencilKit's canvas menu: text-block action appended; on iPad,
        /// nil over objects (they get direct interaction instead).
        case canvasMenu
        /// A text input's menu: suppressed entirely while a pad is open —
        /// the Cut/Copy bar kept popping over text-block controls.
        case textInput
    }

    /// Delegate classes already augmented (the swap is per-class).
    private static var augmentedClasses = Set<String>()

    /// Find PencilKit's edit-menu interaction on the canvas (or a descendant)
    /// and augment its delegate. Safe to call repeatedly.
    static func install(on canvas: GrowingCanvasView) -> Bool {
        guard let interaction = findInteraction(in: canvas) else { return false }
        guard let delegate = interaction.delegate else { return false }
        augment(delegateClass: type(of: delegate), rule: .canvasMenu)
        return true
    }

    /// Suppress every OTHER edit-menu interaction in the window (text
    /// inputs) while a pad is open. Called shortly after a block focuses —
    /// text-input menu machinery attaches lazily, and one hit per class
    /// covers all its instances for the app's lifetime.
    static func suppressTextMenusSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            guard let canvas = activeCanvas, let window = canvas.window else { return }
            let canvasOwned = findInteraction(in: canvas)
            for interaction in findAllInteractions(in: window) where interaction !== canvasOwned {
                guard let delegate = interaction.delegate else { continue }
                augment(delegateClass: type(of: delegate), rule: .textInput)
            }
        }
    }

    private static func findInteraction(in view: UIView) -> UIEditMenuInteraction? {
        if let found = view.interactions.compactMap({ $0 as? UIEditMenuInteraction }).first {
            return found
        }
        for subview in view.subviews {
            if let found = findInteraction(in: subview) { return found }
        }
        return nil
    }

    private static func findAllInteractions(in view: UIView) -> [UIEditMenuInteraction] {
        var found = view.interactions.compactMap { $0 as? UIEditMenuInteraction }
        for subview in view.subviews {
            found += findAllInteractions(in: subview)
        }
        return found
    }

    private static func augment(delegateClass: AnyClass, rule: Rule) {
        let name = NSStringFromClass(delegateClass)
        guard !augmentedClasses.contains(name) else { return }
        augmentedClasses.insert(name)

        let selector = #selector(UIEditMenuInteractionDelegate
            .editMenuInteraction(_:menuFor:suggestedActions:))

        if let method = class_getInstanceMethod(delegateClass, selector) {
            // Delegate builds its own menu — run it, then rework the result.
            typealias MenuFn = @convention(c) (AnyObject, Selector, UIEditMenuInteraction,
                                               UIEditMenuConfiguration, [UIMenuElement]) -> UIMenu?
            let original = unsafeBitCast(method_getImplementation(method), to: MenuFn.self)
            let block: @convention(block) (AnyObject, UIEditMenuInteraction,
                                           UIEditMenuConfiguration, [UIMenuElement]) -> UIMenu? = {
                target, interaction, configuration, suggested in
                apply(rule, base: original(target, selector, interaction, configuration, suggested),
                      suggested: suggested, interaction: interaction, configuration: configuration)
            }
            method_setImplementation(method, imp_implementationWithBlock(block))
        } else {
            // Delegate relies on the suggested actions — provide the method.
            let block: @convention(block) (AnyObject, UIEditMenuInteraction,
                                           UIEditMenuConfiguration, [UIMenuElement]) -> UIMenu? = {
                _, interaction, configuration, suggested in
                apply(rule, base: nil, suggested: suggested,
                      interaction: interaction, configuration: configuration)
            }
            class_addMethod(delegateClass, selector,
                            imp_implementationWithBlock(block), "@@:@@@")
        }
    }

    private static func apply(_ rule: Rule, base: UIMenu?, suggested: [UIMenuElement],
                              interaction: UIEditMenuInteraction?,
                              configuration: UIEditMenuConfiguration?) -> UIMenu? {
        switch rule {
        case .canvasMenu:
            return rework(base: base, suggested: suggested,
                          interaction: interaction, configuration: configuration)
        case .textInput:
            // While a pad is open, text inputs (the blocks) never show the
            // Cut/Copy bar; elsewhere (home search, rename) menus are stock.
            return activeCanvas == nil ? base : nil
        }
    }

    /// The menu's press point in canvas CONTENT coordinates.
    private static func contentPoint(_ interaction: UIEditMenuInteraction?,
                                     _ configuration: UIEditMenuConfiguration?,
                                     canvas: GrowingCanvasView) -> CGPoint? {
        guard let configuration else { return nil }
        let source = configuration.sourcePoint
        let inCanvas = interaction?.view.map { canvas.convert(source, from: $0) } ?? source
        return CGPoint(x: inCanvas.x / canvas.zoomScale,
                       y: inCanvas.y / canvas.zoomScale)
    }

    /// The reworked canvas menu, per platform.
    private static func rework(base: UIMenu?, suggested: [UIMenuElement],
                               interaction: UIEditMenuInteraction?,
                               configuration: UIEditMenuConfiguration?) -> UIMenu? {
        guard let canvas = activeCanvas, let insert = canvas.onInsertTextBlock,
              let point = contentPoint(interaction, configuration, canvas: canvas)
        else { return base }

        #if targetEnvironment(macCatalyst)
        // Mac right-click: on a block, editing is the only sensible action
        // (no direct-press path under a context menu); elsewhere, the stock
        // items plus Add Text Block.
        if canvas.blockHit?(point) == true {
            return UIMenu(children: [
                UIAction(title: "Edit Text Block",
                         image: UIImage(systemName: "character.cursor.ibeam")) { _ in
                    insert(point)
                }
            ])
        }
        let add = UIAction(title: "Add Text Block",
                           image: UIImage(systemName: "character.cursor.ibeam")) { _ in
            insert(point)
        }
        #else
        // iPad: objects get direct interaction — no menu over them at all.
        if canvas.menuSuppressed?(point) == true { return nil }
        let add = UIAction(title: "",
                           image: UIImage(systemName: "character.cursor.ibeam")) { _ in
            insert(point)
        }
        #endif

        if let base { return base.replacingChildren(base.children + [add]) }
        return UIMenu(children: suggested + [add])
    }
}
