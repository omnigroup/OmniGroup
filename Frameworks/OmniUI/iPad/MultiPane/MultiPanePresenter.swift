// Copyright 2016-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

@objc protocol MultiPanePresenterDelegate {

    func handlePinning(presenter: MultiPanePresenter, sender: AnyObject?)
    
    func willPerform(operation: MultiPanePresenterOperation, withPane pane: Pane)
    func didPerform(operation: MultiPanePresenterOperation, withPane pane: Pane)
    
    @objc optional func willPresent(viewController: UIViewController)
    
    @objc optional func navigationAnimationController(for operation: UINavigationControllerOperation, animatingTo toVC: UIViewController, from fromVC: UIViewController) -> UIViewControllerAnimatedTransitioning?
    
    @objc optional func animationsToPerformAlongsideEmbeddedSidebarShowing(atLocation: MultiPaneLocation, withWidth: CGFloat) -> (()->Void)?
    
    @objc optional func animationsToPerformAlongsideEmbeddedSidebarHiding(atLocation: MultiPaneLocation, withWidth: CGFloat) -> (()->Void)?
}

@objc enum MultiPanePresenterOperation: NSInteger {
    case push
    case pop
    case expand
    case collapse
    case present
    case overlay // modal overlay
    case dismiss // modal dismiss
}

// describes how a pane will be presented
enum MultiPanePresentationMode {
    case none
    case embedded
    case overlaid
}

class MultiPanePresenter: NSObject {
   
    private var overlayPresenter: MultiPaneSlidingOverlayPresenter? // keep this around until the presentation has completed, otherwise the overlaid panes will get generic dismiss animation.
    weak var delegate: MultiPanePresenterDelegate?
    
    lazy var rightPinButton: UIBarButtonItem = {
        let image = UIImage(named: "OUIMultiPaneRightPinButton", in: OmniUIBundle, compatibleWith: nil)
        let button = UIBarButtonItem(image: image, style: .plain, target: self, action: #selector(handlePinButton(_:)))
        button.accessibilityIdentifier = "RightPinButton"
        return button
    }()
    
    lazy var leftPinButton: UIBarButtonItem = {
        let image = UIImage(named: "OUIMultiPaneLeftPinButton", in: OmniUIBundle, compatibleWith: nil)
        let button = UIBarButtonItem(image: image, style: .plain, target: self, action: #selector(handlePinButton(_:)))
        button.accessibilityIdentifier = "LeftPinButton"
        return button
    }()
    
    func present(pane: Pane, fromViewController presentingController: UIViewController, usingDisplayMode displayMode: MultiPaneDisplayMode, interactivelyWith gesture: UIScreenEdgePanGestureRecognizer? = nil, animated: Bool = true) {
        
        switch (pane.presentationMode, displayMode) {
        case (.overlaid, _):
            self.overlay(pane: pane, presentingController: presentingController, gesture: gesture, animated: animated)
            break
            
        case (.none, .compact):
            if let compactEnv = pane.environment as? CompactEnvironment {
                if compactEnv.transitionStyle == .navigation {
                    self.navigate(to: pane, presentingController: presentingController, gesture: gesture, animated: animated)
                    break
                }
            }
            self.present(pane: pane, presentingController: presentingController, animated: animated)
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
            let animator = pane.sidebarAnimator(forOperation: operation)
            var additionalAnimations: (()->())?
            if operation == .collapse {
                additionalAnimations = self.delegate?.animationsToPerformAlongsideEmbeddedSidebarHiding?(atLocation: pane.location, withWidth: pane.width)
            } else {
                additionalAnimations = self.delegate?.animationsToPerformAlongsideEmbeddedSidebarShowing?(atLocation: pane.location, withWidth: pane.width)
            }
            if let additionalAnimations = additionalAnimations {
                animator.addAnimations {
                    additionalAnimations()
                }
            }
            self.animate(pane: pane, withAnimator: animator, forOperation: operation)
            
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
        
        if self.snapShotView != nil {
            self.snapShotView?.removeFromSuperview()
            self.snapShotView = nil
        }
        
        let paneView = pane.viewController.view!
        let snapshot = paneView.snapshotView(afterScreenUpdates: false)
        snapshot?.frame = paneView.frame
        containingView.addSubview(snapshot!)
        self.snapShotView = snapshot
    }
    
    func removeSnapshotIfNeeded(pane: Pane) {
        if let snapshot = self.snapShotView {
            snapshot.removeFromSuperview()
            snapShotView = nil
        }
    }
    
    private func overlay(pane: Pane, presentingController: UIViewController, gesture: UIScreenEdgePanGestureRecognizer?, animated: Bool = true) {
        
        self.delegate?.willPerform(operation: .overlay, withPane: pane)
        
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
            self.overlayPresenter?.edgeGesture = gesture
            pane.viewController.transitioningDelegate = self.overlayPresenter
            pane.viewController.modalPresentationStyle = .custom
            
            assert(pane.viewController.presentedViewController == nil, "We hit an infinite loop if we try to present a view controller with a presented view controller")
            presentingController.present(pane.viewController, animated: animated, completion: {
                self.removeSnapshotIfNeeded(pane: pane)
                self.delegate?.didPerform(operation: .overlay, withPane: pane)
            })
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

    private func present(pane: Pane, presentingController: UIViewController, animated: Bool) {
        guard pane.viewController.isBeingPresented == false else { return }
        
        self.delegate?.willPerform(operation: .present, withPane: pane)
        self.overlayPresenter = nil
        
        if self.delegate?.willPresent?(viewController: pane.viewController) == nil {
            // Setup reasonable defaults if the delegate is nil or the optional `willPresent` method is not implemented.
            pane.viewController.transitioningDelegate = nil
            pane.viewController.modalPresentationStyle = .fullScreen
        }
        
        presentingController.present(pane.viewController, animated: animated, completion: {
            self.delegate?.didPerform(operation: .present, withPane: pane)
        })
    }
    
    internal private(set) var transitionContext: MultiPaneNavigationTransitionContext?
    private var interactiveTransition: MultiPaneInteractivePushPopAnimator?
    
    private func navigate(to pane: Pane, presentingController: UIViewController, gesture: UIScreenEdgePanGestureRecognizer?, animated: Bool) {
        // FIXME: instead of assuming the current child controller, should we delegate back for the pane we want to use instead?
        guard let fromController = presentingController.childViewControllers.first else {
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
        
        let animationOperation: UINavigationControllerOperation = (operation == .pop ? .pop : .push)
        let animation = self.delegate?.navigationAnimationController?(for: animationOperation, animatingTo: pane.viewController, from: fromController)
        
        let transitionContext = MultiPaneNavigationTransitionContext(fromViewController: fromController, toViewController: pane.viewController, operation: animationOperation, animator: animation)
        transitionContext.isAnimated = animated
        transitionContext.completedTransition = { [weak self] (didComplete) in
            var currentPane = pane
            if !didComplete {
                currentPane = visiblePane
            }
            self?.delegate?.didPerform(operation: operation, withPane: currentPane)
            
            self?.transitionContext = nil
            self?.interactiveTransition = nil
        }
        
        self.delegate?.willPerform(operation: operation, withPane: pane)
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
        self.delegate?.handlePinning(presenter: self, sender: sender)
    }
    
    private func animate(pane: Pane, withAnimator animator: UIViewPropertyAnimator, forOperation operation: MultiPanePresenterOperation) {
        self.delegate?.willPerform(operation: operation, withPane: pane)
        
        animator.addCompletion { (position) in
            if position == .end {
                self.delegate?.didPerform(operation: operation, withPane: pane)
            }
        }
        
        animator.startAnimation()
    }
}

typealias MultiPaneAnimator = Pane
extension MultiPaneAnimator {
    
    var defaultAnimator: UIViewPropertyAnimator {
        return UIViewPropertyAnimator(duration: 0.35, timingParameters: UISpringTimingParameters())
    }
    
    private func transform(forView view: UIView, makingVisible: Bool) -> CGAffineTransform {
        
        if makingVisible {
            if self.location == .left {
                return CGAffineTransform(translationX: view.bounds.size.width, y: 0)
            } else if self.location == .right {
                return CGAffineTransform(translationX: view.bounds.size.width * -1, y: 0)
            } else {
                assert(false, "unsupported location for transform")
            }
        }
        
        return CGAffineTransform.identity
    }
    
    func slidebarOverlayAnimator(forOperation operation: MultiPanePresenterOperation, interactive: Bool) -> UIViewPropertyAnimator {
        var animator = self.defaultAnimator
        guard operation == .overlay || operation == .dismiss else {
            assertionFailure("expected a expand/collapse operation type, not \(operation)")
            return animator // return animator with no animations
        }
        
        if interactive {
            // for an interactive animation, juse a linear, short duration type so that interactivity feels natural
            animator = UIViewPropertyAnimator(duration: 0.15, curve: .linear, animations: nil)
        }
        
        let view = self.viewController.view! // TODO: should this be handled by a guard? If the view is nil here we have bigger problems, so maybe ok to force and crash (if in a bad state)
        let transform = self.transform(forView: view, makingVisible: (operation == .overlay))
        animator.addAnimations {
            view.transform = transform
        }
        
        return animator
    }
    
    func sidebarAnimator(forOperation operation: MultiPanePresenterOperation) -> UIViewPropertyAnimator {
        let animator = self.defaultAnimator
        guard operation == .expand || operation == .collapse else {
            assertionFailure("expected a expand/collapse operation type, not \(operation)")
            return animator // return animator with no animations
        }
        
        guard let superview = self.viewController.view.superview else {
            assertionFailure("can't animate compact \(operation) because the view has no superview")
            return animator // return animator with no animations
        }
        
        let collapseOffset = self.viewController.view.bounds.width * -1
        let constraintValue = (operation == .expand) ? 0.0 : collapseOffset
        let location = self.location
        
        animator.addAnimations {
            if location == .left {
                MultiPaneLayout.leadingConstraint(forView: superview)?.constant = constraintValue
            } else if location == .right {
                MultiPaneLayout.trailingConstraint(forView: superview)?.constant = constraintValue
            } else {
                assertionFailure("unexpected pane location for expand/collapse animation \(location)")
            }
        }
        animator.addAnimations {
            superview.layoutIfNeeded()
        }
        
        return animator
    }
}
