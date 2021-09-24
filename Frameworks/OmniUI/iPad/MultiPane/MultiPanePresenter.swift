// Copyright 2016-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

@objc protocol MultiPanePresenterDelegate {
    func handlePinning(presenter: MultiPanePresenter, sender: AnyObject?)
    
    func willPerform(operation: MultiPanePresenterOperation, withPane pane: Pane)
    func didPerform(operation: MultiPanePresenterOperation, withPane pane: Pane)
    
    @objc optional func willPresent(viewController: UIViewController)
    
    @objc optional func navigationAnimationController(for operation: UINavigationController.Operation, animatingTo toVC: UIViewController, from fromVC: UIViewController) -> UIViewControllerAnimatedTransitioning?
    
    @objc optional func animationsToPerformAlongsideEmbeddedSidebarShowing(atLocation: MultiPaneLocation, withWidth: CGFloat) -> (()->Void)?
    
    @objc optional func animationsToPerformAlongsideEmbeddedSidebarHiding(atLocation: MultiPaneLocation, withWidth: CGFloat) -> (()->Void)?
}

// MARK: -

@objc enum MultiPanePresenterOperation: NSInteger {
    case push
    case pop
    case expand
    case collapse
    case present
    case overlay // modal overlay
    case dismiss // modal dismiss
}

// MARK: -

/// Describes how a pane will be presented
enum MultiPanePresentationMode {
    case none
    case embedded
    case overlaid
}

// MARK: -

extension UIImage {
    convenience init?(multiPanePinButtonPinnedState pinned: Bool) {
        let name = pinned ? "OUIMultiPanePinDownButton" : "OUIMultiPanePinUpButton"
        self.init(named: name, in: OmniUIBundle, compatibleWith: nil)
    }
}

// MARK: -

class MultiPanePresenter: NSObject {
    private var overlayPresenter: MultiPaneSlidingOverlayPresenter? // keep this around until the presentation has completed, otherwise the overlaid panes will get generic dismiss animation.
    weak var delegate: MultiPanePresenterDelegate?
    
    // Doing a live resize of the sidebar seems to result in UIBarButtonItem's with customViews bounding around. Provide an opt out. <bug:///156110> (iOS-OmniPlan Bug: Undo button in the tool bar bounces when opening Inspector and might be related to this crasher)
    @objc public var animatesSidebarLayout: Bool = true
    
    @objc lazy var rightPinButton: UIBarButtonItem = {
        let image = UIImage(multiPanePinButtonPinnedState: false)
        let button = UIBarButtonItem(image: image, style: .plain, target: self, action: #selector(handlePinButton(_:)))
        button.accessibilityIdentifier = "RightPinButton"
        return button
    }()
    
    @objc lazy var leftPinButton: UIBarButtonItem = {
        let image = UIImage(multiPanePinButtonPinnedState: false)
        let button = UIBarButtonItem(image: image, style: .plain, target: self, action: #selector(handlePinButton(_:)))
        button.accessibilityIdentifier = "LeftPinButton"
        return button
    }()
    
    // This class and the following helper methods, along with the multiPanePresentationCompletionHelpers property, both help to ensure that we do not attempt to present a pane that is already being presented and ensure all the relevant completion handlers for in-progress presentations get called.
    private class MultiPanePresentationCompletionHelper {
        weak var multiPaneController: MultiPaneController?
        var locationBeingShownAndCompletionHandlers: (location: MultiPaneLocation, isShowing: Bool, handlers: [()->Void], expiration: Date)? = nil
        
        // Return value is true if no presentation operation is in progress, and false otherwise.
        func hasActivePresentationPreventingNewPresentation(at location: MultiPaneLocation, isShowing: Bool, completionHandlerToAppendIfEligible: @escaping ()->Void) -> Bool {
            flushExistingCompletionsIfNecessary()
            if let locationBeingShownAndCompletionHandlers = locationBeingShownAndCompletionHandlers {
                // We are already mid-presentation at another location, we cannot start a new one while it's in-progress. Drop this handler on the floor.
                guard locationBeingShownAndCompletionHandlers.location == location else { return true }
                // We are in the middle of showing/hiding and being asked to do the opposite- we can't do that until the first transition is complete. Drop this handler on the floor.
                guard locationBeingShownAndCompletionHandlers.isShowing == isShowing else { return true }
                // We have a duplicate request to show/hide a pane that's already being shown. Append the completion handler so it is run when the presentation completes. Return true since there is already an operation in progress.
                var newHandlers = locationBeingShownAndCompletionHandlers.handlers
                newHandlers.append(completionHandlerToAppendIfEligible)
                self.locationBeingShownAndCompletionHandlers = (location, isShowing, newHandlers, locationBeingShownAndCompletionHandlers.expiration)
                return true
            } else {
                // No existing operation in progress. Return false, indicating that the presentation must be started by the caller.
                locationBeingShownAndCompletionHandlers = (location, isShowing, [completionHandlerToAppendIfEligible], expiration: Date(timeInterval: 1, since: Date()))
                return false
            }
        }
        
        private func flushExistingCompletionsIfNecessary() {
            guard let multiPaneController = multiPaneController else { return }
            guard let locationBeingShownAndCompletionHandlers = locationBeingShownAndCompletionHandlers else { return }
            let paneIsVisible = multiPaneController.paneIsVisible(at: locationBeingShownAndCompletionHandlers.location)
            let shouldBeVisible = locationBeingShownAndCompletionHandlers.isShowing
            if paneIsVisible == shouldBeVisible {
                locationBeingShownAndCompletionHandlers.handlers.forEach({ $0() })
                self.locationBeingShownAndCompletionHandlers = nil
            } else if locationBeingShownAndCompletionHandlers.expiration.timeIntervalSinceNow < 0 {
                // This transition has expired, and must have been cancelled by the system for some reason.
                self.locationBeingShownAndCompletionHandlers = nil
            }
        }
        
        init(multiPaneController: MultiPaneController) {
            self.multiPaneController = multiPaneController
        }
    }
    
    private func completionHelperForMultipaneControllerCreatingIfNecessary(_ multiPaneController: MultiPaneController) -> MultiPanePresentationCompletionHelper {
        if let existing = multiPanePresentationCompletionHelpers.first(where: { $0.multiPaneController == multiPaneController }) {
            return existing
        } else {
            let helper = MultiPanePresentationCompletionHelper(multiPaneController: multiPaneController)
            multiPanePresentationCompletionHelpers.append(helper)
            return helper
        }
    }
    
    private func completionHandlers(for multiPaneController: MultiPaneController) -> [()->Void]? {
        return completionHelperForMultipaneControllerCreatingIfNecessary(multiPaneController).locationBeingShownAndCompletionHandlers?.handlers
    }
    
    private func clearCompletionHandlers(for multiPaneController: MultiPaneController) {
        completionHelperForMultipaneControllerCreatingIfNecessary(multiPaneController).locationBeingShownAndCompletionHandlers = nil
    }
    
    private var multiPanePresentationCompletionHelpers: [MultiPanePresentationCompletionHelper] = []
    
    func present(pane: Pane, fromViewController presentingController: MultiPaneController, usingDisplayMode displayMode: MultiPaneDisplayMode, interactivelyWith gesture: UIScreenEdgePanGestureRecognizer? = nil, animated: Bool = true, completion: @escaping ()->Void = {}) {
        let location = pane.location
        
        // Logging for <bug:///178768> (iOS-OmniFocus Crasher: Check for 3.7 Reports: UIViewControllerHierarchyInconsistency', reason: 'child view controller:<FocusNavigationController: 0xdeaddead> should have parent view controller:<OmniUI.MultipanePresentationWrapperViewController: 0xdeaddead> but actual parent is:<OmniUI.MultipanePresentationWrapperViewController: 0xdeaddead>')
        OBRecordBacktrace("Pane Presentation at \(location.name)", OBBacktraceBufferType.generic)
        
        // Attempted fix for <bug:///178768>. This cut down reports by 99%, but a couple still come in.
        let multiPanePresentationCompletionHelper = completionHelperForMultipaneControllerCreatingIfNecessary(presentingController)
        // Since this method takes a non-optional completion handler, the presence of any existing enqueued completion handler indicates that a presentation for this pane is currently in progress. If there is a presentation in progress, we early out and avoid requesting another presentation.
        guard !multiPanePresentationCompletionHelper.hasActivePresentationPreventingNewPresentation(at: location, isShowing: !pane.isVisible, completionHandlerToAppendIfEligible: completion) else { return }
        
        // No presentation is currently in progress. Continue with requesting a presentation.
        
        // Reassign completion to ensure we perform all enqueued completion handlers for this presentation. They were stored by passing them as the completionHandlerToAppendIfEligible to hasActivePresentationPreventingNewPresentation above.
        let completion = {[weak self] in
            if let completionHandlers = self?.completionHandlers(for: presentingController) {
                for completionHandler in completionHandlers {
                    completionHandler()
                }
            }
            // We performed the completions, so clear out our references to them.
            self?.clearCompletionHandlers(for: presentingController)
        }
        
        // Below, we have the actual presentation code.
        
        // Ensure layout is up to date before we build up the animation and new constraints
        if animated {
            presentingController.view.layoutIfNeeded()
        }

        switch (pane.presentationMode, displayMode) {
        case (.overlaid, _):
            overlay(pane: pane, presentingController: presentingController, gesture: gesture, animated: animated, completion: completion)
            break
            
        case (.none, .compact):
            if let compactEnv = pane.environment as? CompactEnvironment {
                if compactEnv.transitionStyle == .navigation {
                    navigate(to: pane, presentingController: presentingController, gesture: gesture, animated: animated, completion: completion)
                    break
                }
            }
            
            present(pane: pane, presentingController: presentingController, animated: animated, completion: completion)
            break
            
        case (.embedded, .compact):
            // typically evaluated when trying to show a compact pane that is already visible. no-op in that case.
            break
            
        case (.embedded, .multi):
            // expand or collapse
            if pane.location == .center {
                // ignore the center for this presentation request
                break
            }
            
            if gesture != nil { return } // TODO: decide if we want to bail here, or try to support this gesture to drive the expand/collapse animation. It might be confusing for users that they can gesture sometimes, but not others.

            let operation: MultiPanePresenterOperation = pane.isVisible ? .collapse : .expand
            let animator = pane.sidebarAnimator(forOperation: operation, in: presentingController, animate:animatesSidebarLayout)
            var additionalAnimations: (()->())?

            if operation == .collapse {
                additionalAnimations = delegate?.animationsToPerformAlongsideEmbeddedSidebarHiding?(atLocation: pane.location, withWidth: pane.width)
            } else {
                additionalAnimations = delegate?.animationsToPerformAlongsideEmbeddedSidebarShowing?(atLocation: pane.location, withWidth: pane.width)
            }

            if let additionalAnimations = additionalAnimations {
                animator.addAnimations {
                    additionalAnimations()
                }
            }
            
            animator.addCompletion { _ in
                completion()
            }
            
            animate(pane: pane, withAnimator: animator, forOperation: operation)
            break

        case (.embedded, .single):
            if pane.location == .center {
                // ignore the center for this presentation request
                break
            }

        default:
            assertionFailure("can't present: unexpected pane displayStyle \(pane.presentationMode) and MultiPaneDisplayMode \(displayMode)")
            break
        }

    }
    
    func dismiss(fromViewController presentingController: UIViewController, animated: Bool, completion: (()->Void)?) {
        if presentingController.presentedViewController != nil {
            presentingController.dismiss(animated: animated, completion: completion )
        } else {
            if let completeBlock = completion {
                completeBlock()
            }
        }
    }
    
    private var snapShotView: UIView?
    
    func addSnapshot(to containingView: UIView, for pane: Pane) {
        
        if snapShotView != nil {
            snapShotView?.removeFromSuperview()
            snapShotView = nil
        }
        
        let paneView = pane.viewController.view!
        let snapshot = paneView.snapshotView(afterScreenUpdates: false)
        snapshot?.frame = paneView.frame
        containingView.addSubview(snapshot!)
        snapShotView = snapshot
    }
    
    func removeSnapshotIfNeeded(pane: Pane) {
        if let snapshot = snapShotView {
            snapshot.removeFromSuperview()
            snapShotView = nil
        }
    }
    
    private var panesInOverlayTransition: Set<Pane> = []

    private func overlay(pane: Pane, presentingController: UIViewController, gesture: UIScreenEdgePanGestureRecognizer?, animated: Bool = true, completion: @escaping ()->Void) {
        guard !panesInOverlayTransition.contains(pane) else { return } // already animating this one
        
        // Update the decorations for the environment we are going to present *into*.
        // This is kind of gross, because the pane wraps the view controller, the pane isn't going to get notification of the trait collection changes.
        // As such, we have to force the user interface style here.
        if let environment = pane.environment, pane.viewController.overrideUserInterfaceStyle == .unspecified {
            pane.viewController.overrideUserInterfaceStyle = presentingController.traitCollection.userInterfaceStyle
            pane.apply(decorations: pane.configuration.decorations(forEnvironment: environment))
            pane.viewController.overrideUserInterfaceStyle = .unspecified
        }
        
        delegate?.willPerform(operation: .overlay, withPane: pane)
        panesInOverlayTransition.insert(pane)
        
        // If the pane has a presented view controller when we try to present it with our custom presentation, we get into an infinite loop trying to find the firstResponder. The solution is to dismiss any presented view controller from the pane, and then re-present it after we get the pane back in the view hierarchy.
        let presentedController = pane.viewController.presentedViewController
        let presentationBlock = {
            // create a new one each time, instead of trying to reuse. Clients shouldn't hold on to this button anyway, because we might take it away at some point
            
            let pinButton: UIBarButtonItem
            if pane.configuration.location == .left {
                pinButton = self.leftPinButton
            } else {
                pinButton = self.rightPinButton
            }

            self.overlayPresenter = MultiPaneSlidingOverlayPresenter(pane: pane, pinBarButtonItem: pinButton)
            self.overlayPresenter?.sldingOverlayPresentationControllerDelegate = self
            self.overlayPresenter?.edgeGesture = gesture
            
            assert(pane.viewController.presentedViewController == nil, "We hit an infinite loop if we try to present a view controller with a presented view controller")
            
            MultipanePresentationWrapperViewController.presentWrapperController(from: presentingController, animated: animated, contentViewController: pane.viewController, presentationStyle: .custom, adaptivePresentationDelegate: pane.viewController as? UIAdaptivePresentationControllerDelegate, configurationBlock: { wrapper in
                wrapper.transitioningDelegate = self.overlayPresenter
            }) {
                self.removeSnapshotIfNeeded(pane: pane)
                self.panesInOverlayTransition.remove(pane)
                self.delegate?.didPerform(operation: .overlay, withPane: pane)
                completion()
            }

            if let presentedController = presentedController {
                pane.viewController.present(presentedController, animated: false, completion: nil)
            }
        }

        if pane.viewController.presentedViewController != nil {
            pane.viewController.dismiss(animated: false, completion: presentationBlock)
        } else {
            presentationBlock()
        }
    }

    private func present(pane: Pane, presentingController: UIViewController, animated: Bool, completion: @escaping ()->Void) {
        guard pane.viewController.isBeingPresented == false else { return }
        
        delegate?.willPerform(operation: .present, withPane: pane)
        overlayPresenter = nil
        
        MultipanePresentationWrapperViewController.presentWrapperController(from: presentingController, animated: animated, contentViewController: pane.viewController, presentationStyle: nil, adaptivePresentationDelegate: pane.viewController as? UIAdaptivePresentationControllerDelegate, configurationBlock: { wrapper in
            if self.delegate?.willPresent?(viewController: wrapper) == nil {
                // Setup reasonable defaults if the delegate is nil or the optional `willPresent` method is not implemented.
                wrapper.transitioningDelegate = nil
                wrapper.modalPresentationStyle = .automatic
            }
        }) {
            self.delegate?.didPerform(operation: .present, withPane: pane)
            completion()
        }
    }
    
    internal private(set) var transitionContext: MultiPaneNavigationTransitionContext?
    private var interactiveTransition: MultiPaneInteractivePushPopAnimator?
    
    private func navigate(to pane: Pane, presentingController: UIViewController, gesture: UIScreenEdgePanGestureRecognizer?, animated: Bool, completion: @escaping ()->Void) {
        // FIXME: instead of assuming the current child controller, should we delegate back for the pane we want to use instead?
        guard let fromController = presentingController.children.first else {
            assertionFailure("Expected a controller to exist prior to navigation")
            return
        }
        
        guard let multiPaneController = presentingController as? MultiPaneController else {
            return
        }
        
        let visiblePane = multiPaneController.pane(forViewController: fromController)!
        var operation: MultiPanePresenterOperation = .pop
        
        let panes = (from: visiblePane.location, to: pane.location)
        switch panes {
        case (.left, .center):
            operation = .push
            break
        case (.center, .left):
            operation = .pop
            break
        case (.center, .right):
            operation = .push
            break
        case (.right, .center):
            operation = .pop
            break
        default:
            // unsupported transition
            break
        }
        
        let animationOperation: UINavigationController.Operation = (operation == .pop ? .pop : .push)
        let animation = delegate?.navigationAnimationController?(for: animationOperation, animatingTo: pane.viewController, from: fromController)
        
        let transitionContext = MultiPaneNavigationTransitionContext(fromViewController: fromController, toViewController: pane.viewController, operation: animationOperation, animator: animation)
        transitionContext.isAnimated = animated
        transitionContext.completedTransition = { [weak self] (didComplete) in
            guard let self = self else { return }
            
            var currentPane = pane
            if !didComplete {
                currentPane = visiblePane
            }
            
            self.delegate?.didPerform(operation: operation, withPane: currentPane)
            
            self.transitionContext = nil
            self.interactiveTransition = nil
            
            completion()
        }
        
        delegate?.willPerform(operation: operation, withPane: pane)
        gesture?.setTranslation(CGPoint.zero, in: gesture?.view)

        let isInteractive: Bool
            
        if let gesture = gesture {
            isInteractive = gesture.state == .began
        } else {
            isInteractive = false
        }

        if isInteractive {
            transitionContext.isInteractive = true
            let interactiveTransition = MultiPaneInteractivePushPopAnimator(with: gesture!)
            self.transitionContext = transitionContext
            self.interactiveTransition = interactiveTransition
            interactiveTransition.startInteractiveTransition(transitionContext)
        } else {
            self.transitionContext = transitionContext
            transitionContext.startTransition()
        }
    }
    
    @objc private func handlePinButton(_ sender: AnyObject?) {
        delegate?.handlePinning(presenter: self, sender: sender)
    }
    
    private func animate(pane: Pane, withAnimator animator: UIViewPropertyAnimator, forOperation operation: MultiPanePresenterOperation) {
        delegate?.willPerform(operation: operation, withPane: pane)
        
        animator.addCompletion { (position) in
            if position == .end {
                self.delegate?.didPerform(operation: operation, withPane: pane)
            }
        }
        
        animator.startAnimation()
    }
}

// MARK: -

extension MultiPanePresenter: SldingOverlayPresentationControllerDelegate {
    @nonobjc func slidingOverlayPresentationController(_ controller: SldingOverlayPresentationController, willDismiss pane: Pane) {
        delegate?.willPerform(operation: .dismiss, withPane: pane)
    }

    @nonobjc func slidingOverlayPresentationController(_ controller: SldingOverlayPresentationController, didDismiss pane: Pane) {
        delegate?.didPerform(operation: .dismiss, withPane: pane)
    }
}

// MARK: -

typealias MultiPaneAnimator = Pane

extension MultiPaneAnimator {
    static let defaultAnimationDuration: TimeInterval = 0.25
    static let interactiveAnimationDuration: TimeInterval = 0.1
    
    var defaultAnimator: UIViewPropertyAnimator {
        return UIViewPropertyAnimator(duration: MultiPaneAnimator.defaultAnimationDuration, curve: .easeInOut, animations: nil)
    }
    
    private func centerX(forView view: UIView, makingVisible: Bool) -> CGFloat {
        let multiplier: CGFloat = makingVisible ? 1 : -1
        if location == .left {
            return multiplier * view.bounds.size.width / 2.0
        } else if location == .right {
            guard let container = view.superview else { assertionFailure(); return 0 }
            return container.frame.maxX - (multiplier * view.bounds.size.width / 2.0)
        } else {
            assertionFailure("unsupported location for transform")
            return 0
        }
    }
    
    func sidebarOverlayAnimator(forOperation operation: MultiPanePresenterOperation, interactive: Bool) -> UIViewPropertyAnimator {
        var animator = defaultAnimator
        guard operation == .overlay || operation == .dismiss else {
            assertionFailure("expected a expand/collapse operation type, not \(operation)")
            return animator // return animator with no animations
        }
        
        if interactive {
            // for an interactive animation, juse a linear, short duration type so that interactivity feels natural
            animator = UIViewPropertyAnimator(duration: MultiPaneAnimator.interactiveAnimationDuration, curve: .linear, animations: nil)
        }
        
        // Our pane can be contained in a wrapper controller, so perform the animation on the deepest ancestor
        let view = viewController.furthestAncestor.view! // TODO: should this be handled by a guard? If the view is nil here we have bigger problems, so maybe ok to force and crash (if in a bad state)
        
        // Ensure the view is ready to animate
        UIView.performWithoutAnimation {
            view.layoutIfNeeded()
        }

        let centerX = self.centerX(forView: view, makingVisible: (operation == .overlay))
        animator.addAnimations {
            view.center.x = centerX
        }
        
        return animator
    }
    
    func sidebarAnimator(forOperation operation: MultiPanePresenterOperation, in multipaneController: MultiPaneController, animate: Bool) -> UIViewPropertyAnimator {
        let animator = defaultAnimator
        guard operation == .expand || operation == .collapse else {
            assertionFailure("expected a expand/collapse operation type, not \(operation)")
            return animator // return animator with no animations
        }
        
        guard let superview = viewController.view.superview else {
            assertionFailure("can't animate compact \(operation) because the view has no superview")
            return animator // return animator with no animations
        }
        
        let collapseOffset = viewController.view.bounds.width * -1
        let constraintValue = (operation == .expand) ? 0.0 : collapseOffset
        let location = self.location
        
        let performConstraintChanges = {
            if location == .left {
                MultiPaneLayout.leadingConstraint(forView: superview)?.constant = constraintValue
            } else if location == .right {
                MultiPaneLayout.trailingConstraint(forView: superview)?.constant = constraintValue
            } else {
                assertionFailure("unexpected pane location for expand/collapse animation \(location)")
            }
            // workaround for <bug:///175873> (iOS-OmniGraffle Bug: [iOS 13] hiding sidebar inspector does not resize the canvas back to the edge of the window)
            multipaneController.orderedPanes.forEach { (pane:Pane) in
                pane.viewController.view.setNeedsLayout()
            }
        }
        
        let invalidateSearchBarLayout = {
            for pane in multipaneController.orderedPanes {
                guard let navigationController = pane.viewController as? UINavigationController else { continue }
                guard let searchController = navigationController.topViewController?.navigationItem.searchController else { continue }
                searchController.searchBar.setNeedsLayout()
            }
        }

        if (animate) {
            animator.addAnimations {
                performConstraintChanges()
                
                // Invalidate the layout for all search bars now, otherwise they are stale after sidebar expand/collapse.
                //
                // <bug:///176005> (iOS-OmniFocus Bug: iOS 13: Search field width does not update properly with multipane controller layouts)
                // Filed with Apple as FB6786500

                invalidateSearchBarLayout()

                superview.layoutIfNeeded()
            }
        } else {
            animator.addAnimations(performConstraintChanges)
        }
        
        return animator
    }
}

// MARK: -

// In order to present a pane as an overlay in one context and as a page sheet in another, we need to create a new wrapping view controller every time a presentation occurs. Once a view controller has received a modalPresentationStyle, it's stuck with that style forever once it's been presented. So, call this class' presentation method each time a pane needs to be presented modally or as an overlay, and we'll wrap the pane's controller in this wrapper.
// This class is only intended to be used internally by the MultiPanePresenter. It is marked public in case there is an app-level protocol implementation that this controller is required to have an implementation of. OmniFocus needs this for overrides for FocusSyncViewControllerCompatibility.
@objc(OUIMultipanePresentationWrapperViewController)
public class MultipanePresentationWrapperViewController: UIViewController {
    fileprivate static func presentWrapperController(from presentingController: UIViewController, animated: Bool, contentViewController: UIViewController, presentationStyle: UIModalPresentationStyle?, adaptivePresentationDelegate: UIAdaptivePresentationControllerDelegate?, configurationBlock: (MultipanePresentationWrapperViewController)->Void = {_ in }, completion: @escaping ()->Void = {}) {
        let wrapper = MultipanePresentationWrapperViewController()
        wrapper.contentViewController = contentViewController
        wrapper.addChild(contentViewController)
        
        configurationBlock(wrapper)
        
        if let presentationStyle = presentationStyle {
            wrapper.modalPresentationStyle = presentationStyle
        }
        
        if let adaptivePresentationDelegate = adaptivePresentationDelegate {
            assert(wrapper.presentationController?.delegate == nil)
            wrapper.presentationController?.delegate = adaptivePresentationDelegate
        }
        
        presentingController.present(wrapper, animated: animated, completion: completion)
    }
    
    public private(set) var contentViewController: UIViewController!
    
    override public func loadView() {
        let view = UIView()
        let rootView = contentViewController.view!
        view.addSubview(rootView)
        rootView.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            view.topAnchor.constraint(equalTo: rootView.topAnchor),
            view.bottomAnchor.constraint(equalTo: rootView.bottomAnchor)
        ])
        
        view.frame.size = rootView.frame.size
        
        self.view = view
        
        view.setNeedsLayout()
        view.layoutIfNeeded()
    }
    
    @available(iOSApplicationExtension, unavailable)
    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // <bug:///179342> (iOS-OmniFocus Bug: Compact: Inspector bottom bar is scrolled out of view after backgrounding, then returning to app)
        guard let scene = containingScene else { assertionFailure("Unable to find containing scene"); return }
        NotificationCenter.default.addObserver(self, selector: #selector(forceViewLayout), name: UIScene.willEnterForegroundNotification, object: scene)
    }
    
    
    override public func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            // Need a turn of the run loop or else we hit an infinite loop
            // <bug:///179688> (iOS-OmniFocus Bug: Compact: Inspector bottom bar is scrolled out of view after toggling between light / dark mode)
            DispatchQueue.main.async { [weak self] in
                self?.forceViewLayout()
            }
        }
    }

    @objc private dynamic func forceViewLayout() {
        view.setNeedsLayout()
        view.layoutIfNeeded()
    }
    
    // Once the presentation is over, we want to throw this wrapper away, since it's served its purpose of supplying a presentation.
    override public func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        
        // Only remove the wrapped controller if we're being dismissed. If something is being presented over top of us, we need to stick around.
        guard isBeingDismissed else { return }
        
        // We remove the controller manually below, and that prevents this lifecycle message from percolating down. Call it manually, instead.
        contentViewController?.viewDidDisappear(animated)
        
        contentViewController?.removeFromParent()
        contentViewController?.view?.removeFromSuperview()
        contentViewController = nil
    }
}
