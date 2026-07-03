#if !targetEnvironment(macCatalyst)
import UIKit
import PencilKit
import ObjectiveC

/// Adds Quill's A| "add text block" action to PencilKit's own edit menu (the
/// "Select All | Insert Space" callout on a finger tap).
///
/// PencilKit exposes no menu API and its `UIEditMenuInteraction` delegate is
/// read-only, so the delegate's menu method is augmented at runtime: the
/// original implementation runs first, then the A| action is appended to
/// whatever it returned. Everything is discovered dynamically — no private
/// names — and any lookup failure degrades to the stock menu.
enum EditMenuAugment {

    /// The canvas whose menu gets the extra action (one pad open at a time).
    static weak var activeCanvas: GrowingCanvasView?

    /// Delegate classes already augmented (the swap is per-class).
    private static var augmentedClasses = Set<String>()

    /// Find PencilKit's edit-menu interaction on the canvas (or a descendant)
    /// and augment its delegate. Safe to call repeatedly.
    static func install(on canvas: GrowingCanvasView) -> Bool {
        guard let interaction = findInteraction(in: canvas) else { return false }
        guard let delegate = interaction.delegate else { return false }
        augment(delegateClass: type(of: delegate))
        return true
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

    private static func augment(delegateClass: AnyClass) {
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
                rework(base: original(target, selector, interaction, configuration, suggested),
                       suggested: suggested)
            }
            method_setImplementation(method, imp_implementationWithBlock(block))
        } else {
            // Delegate relies on the suggested actions — provide the method.
            let block: @convention(block) (AnyObject, UIEditMenuInteraction,
                                           UIEditMenuConfiguration, [UIMenuElement]) -> UIMenu? = {
                _, _, _, suggested in
                rework(base: nil, suggested: suggested)
            }
            class_addMethod(delegateClass, selector,
                            imp_implementationWithBlock(block), "@@:@@@")
        }
    }

    /// The reworked menu: nil (no bar at all) when the press sits on an
    /// object — objects get direct interaction, not a menu — otherwise the
    /// stock menu plus the A| add-text-block action.
    private static func rework(base: UIMenu?, suggested: [UIMenuElement]) -> UIMenu? {
        guard let canvas = activeCanvas else { return base }
        let point = CGPoint(x: canvas.lastTouchPoint.x / canvas.zoomScale,
                            y: canvas.lastTouchPoint.y / canvas.zoomScale)
        if canvas.menuSuppressed?(point) == true { return nil }
        guard let insert = canvas.onInsertTextBlock else { return base }
        let add = UIAction(title: "",
                           image: UIImage(systemName: "character.cursor.ibeam")) { _ in
            insert(point)
        }
        if let base { return base.replacingChildren(base.children + [add]) }
        return UIMenu(children: suggested + [add])
    }
}
#endif
