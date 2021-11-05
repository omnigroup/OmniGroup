// Copyright 2016-2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

class MultiPaneSlidingOverlayPresenter: NSObject, UIViewControllerTransitioningDelegate {
    let pinBarButton: UIBarButtonItem
    let presentingPane: Pane
    var isInteractive: Bool = false
    weak var sldingOverlayPresentationControllerDelegate: SldingOverlayPresentationControllerDelegate?
    
    var edgeGesture: UIScreenEdgePanGestureRecognizer? {
        didSet {
            if edgeGesture != nil {
                isInteractive = true
            } else {
                isInteractive = false
            }
        }
    }
    
    init(pane: Pane, pinBarButtonItem item: UIBarButtonItem) {
        self.presentingPane = pane
        self.pinBarButton = item
        super.init()
    }
    
    func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        return SlidingOverlayAnimator(withPane: presentingPane, presenting: true)
    }
    
    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        // NOTE: this is not called when we rotate during a presenation. Trying to animate that transition leaves the system in a bad state.
        return SlidingOverlayAnimator(withPane: presentingPane, presenting: false)
    }
    
    func interactionControllerForPresentation(using animator: UIViewControllerAnimatedTransitioning) -> UIViewControllerInteractiveTransitioning? {
        // If we are not interactive, we don't want to return an interactive animator. If we do, nothing will animate because nothing drives the animation.
        if !isInteractive { return nil }
        guard let gesture = self.edgeGesture, (gesture.edges == .left || gesture.edges == .right) && gesture.isEnabled else {
            print("skipping interactive presentation because the gesture isn't setup correctly") // FIXME: can this be an os_log_debug message instead?
            return nil
        }
        return SlidingOverlayInteractiveAnimator(gesture: gesture)
    }
    
    func presentationController(forPresented presented: UIViewController, presenting: UIViewController?, source: UIViewController) -> UIPresentationController? {
        let presentationController = SldingOverlayPresentationController(withPane: presentingPane, presentingController: presenting)
        presentationController.sldingOverlayPresentationControllerDelegate = sldingOverlayPresentationControllerDelegate
        return presentationController
    }
    
    @objc private func handlePinButton(sender: AnyObject?) {
        debugPrint("got a pin request")
    }
}

// MARK: -

protocol SldingOverlayPresentationControllerDelegate: AnyObject {
    func slidingOverlayPresentationController(_ controller: SldingOverlayPresentationController, willDismiss pane: Pane)
    func slidingOverlayPresentationController(_ controller: SldingOverlayPresentationController, didDismiss pane: Pane)
}

// MARK: -

private class _DismissOverlayButton: UIButton {}

// MARK: -

class SldingOverlayPresentationController: UIPresentationController {
    private let shieldingView = _DismissOverlayButton(type: .custom)
    var pane: Pane
    weak var sldingOverlayPresentationControllerDelegate: SldingOverlayPresentationControllerDelegate?
    
    init(withPane pane: Pane, presentingController: UIViewController?) {
        self.pane = pane
        // For slideover presentations, we wrap the pane's view controller for adaptive presentation reasons
        super.init(presentedViewController: self.pane.viewController.furthestAncestor, presenting: presentingController)
        self.overrideTraitCollection = UITraitCollection(horizontalSizeClass: .compact)
    }
    
    override func presentationTransitionWillBegin() {
        guard let container = self.containerView  else {
            assertionFailure("No container view, can't continue")
            return
        }
        
        shieldingView.frame = container.bounds
        shieldingView.backgroundColor = UIColor.clear
        shieldingView.alpha = 0.0
        shieldingView.accessibilityLabel = NSLocalizedString("Dismiss overlay", tableName: "OmniUI", bundle: OmniUIBundle, comment: "Accessibility label for dismissing a sliding overlay pane")
        container.addSubview(shieldingView)
        
        shieldingView.addTarget(self, action: #selector(handleTap), for: .primaryActionTriggered)

        if let transition = presentedViewController.transitionCoordinator {
            transition.animate(alongsideTransition: { (context) in
                self.shieldingView.alpha = 0.3
            }, completion: nil)
            
            if let paneView = presentedViewController.view {
                container.addSubview(paneView)
                
                // Constrain the top/bottom and width
                paneView.translatesAutoresizingMaskIntoConstraints = false
                let paneWidth = pane.width > 0 ? pane.width : 320
                NSLayoutConstraint.activate([
                    paneView.topAnchor.constraint(equalTo: container.topAnchor),
                    paneView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                    paneView.widthAnchor.constraint(equalToConstant: paneWidth)
                ])
                
                // Constrain the pane's x-position, and animate it onscreen
                switch pane.location {
                case .left:
                    // Position the pane offscreen to the left
                    paneView.frame = CGRect(x: -paneWidth, y: 0, width: paneWidth, height: container.bounds.size.height)
                    
                    transition.animate(alongsideTransition: { (context) in
                        // Constrain the pane to the correct location, and ensure the layout pass happens so that the pane is in the correct spot after the transition
                        let leadingConstraint = paneView.leadingAnchor.constraint(equalTo: container.safeAreaLayoutGuide.leadingAnchor)
                        NSLayoutConstraint.activate([leadingConstraint])
                        container.setNeedsLayout()
                        container.layoutIfNeeded()
                    }, completion: nil)
                case .right:
                    // Position the pane offscreen to the right
                    paneView.frame = CGRect(x: container.bounds.size.width, y: 0, width: paneWidth, height: container.bounds.size.height)
                    
                    transition.animate(alongsideTransition: { (context) in
                        // Constrain the pane to the correct location, and ensure the layout pass happens so that the pane is in the correct spot after the transition
                        let trailingConstraint = paneView.trailingAnchor.constraint(equalTo: container.safeAreaLayoutGuide.trailingAnchor)
                        NSLayoutConstraint.activate([trailingConstraint])
                        container.setNeedsLayout()
                        container.layoutIfNeeded()
                    }, completion: nil)
                default:
                    assertionFailure("Should not present center pane as an overlay")
                }
            }
        }
    }
    
    override func dismissalTransitionWillBegin() {
        sldingOverlayPresentationControllerDelegate?.slidingOverlayPresentationController(self, willDismiss: pane)
        if let transistion = presentedViewController.transitionCoordinator {
            transistion.animate(alongsideTransition: { (context) in
                self.shieldingView.alpha = 0.0
            }, completion: nil)
        }
    }
    
    override func dismissalTransitionDidEnd(_ completed: Bool) {
        if completed {
            sldingOverlayPresentationControllerDelegate?.slidingOverlayPresentationController(self, didDismiss: pane)
        }
    }
    
    override func size(forChildContentContainer container: UIContentContainer, withParentContainerSize parentSize: CGSize) -> CGSize {
        let width: CGFloat = pane.width
        return CGSize(width: width > 0.0 ? width : 320.0, height: parentSize.height)
    }
    
    override var frameOfPresentedViewInContainerView: CGRect {
        var presentedFrame = CGRect.zero
        let bounds = self.containerView!.bounds
        presentedFrame.size = size(forChildContentContainer: presentedViewController, withParentContainerSize: bounds.size)
        if pane.location == .right {
            presentedFrame.origin.x = bounds.width - presentedFrame.size.width
        } else {
            presentedFrame.origin.x = 0.0
        }
        
        return presentedFrame
    }
    
    override func containerViewDidLayoutSubviews() {
        super.containerViewDidLayoutSubviews()
        shieldingView.frame = containerView!.bounds
        presentedView?.frame = frameOfPresentedViewInContainerView
    }
    
    override var presentationStyle: UIModalPresentationStyle {
        return .custom
    }
    
    override func willTransition(to newCollection: UITraitCollection, with coordinator: UIViewControllerTransitionCoordinator) {
        super.willTransition(to: newCollection, with: coordinator)
        dismiss(animated: false)
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        dismiss(animated: false)
    }
    
    @objc func handleTap(gesture: UITapGestureRecognizer) {
        dismiss(animated: true)
    }
    
    private func dismiss(animated: Bool) {
        // We don't want to do this if we're being dismissed by a transition caused by snapshotting
        // <bug:///183629> (iOS-OmniFocus Bug: Non-pinned inspector shows up then collapses after switching away and back to OmniFocus [UX])
        presentedViewController.dismiss(animated: animated, completion:nil)
    }
}

// MARK: -

class SlidingOverlayAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    // need to know what side we are presenting from
    // need to know what the transform is for the presentation
    let presentingPane: Pane
    let isPresenting: Bool
    
    init(withPane pane: Pane, presenting: Bool) {
        self.presentingPane = pane
        self.isPresenting = presenting
    }
    
    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        return MultiPaneAnimator.defaultAnimationDuration
    }
    
    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        let toViewController = transitionContext.viewController(forKey: UITransitionContextViewControllerKey.to)!
        let fromViewController = transitionContext.viewController(forKey: UITransitionContextViewControllerKey.from)!
       // let animatingView = isPresenting ? toViewController.view : fromViewController.view
        let containerView = transitionContext.containerView
        
        if isPresenting {
            containerView.addSubview(toViewController.view)
        }
        
        let operation: MultiPanePresenterOperation = isPresenting ? .overlay : .dismiss
        let animator = presentingPane.sidebarOverlayAnimator(forOperation: operation, interactive: transitionContext.isInteractive)
        animator.addCompletion { (postion) in
            let cancelled = transitionContext.transitionWasCancelled
            if !self.isPresenting {
                fromViewController.view.removeFromSuperview()
                fromViewController.view.transform = CGAffineTransform.identity
            }
            
            transitionContext.completeTransition(!cancelled)
        }
        
        animator.startAnimation()
    }
}

// MARK: -

class SlidingOverlayInteractiveAnimator: UIPercentDrivenInteractiveTransition {
    let edgeSwipeGesture: UIScreenEdgePanGestureRecognizer
    let direction: UIRectEdge
    var containerView: UIView = UIView()
    var shouldFinish: Bool = false
    
    init(gesture: UIScreenEdgePanGestureRecognizer) {
        self.edgeSwipeGesture = gesture
        self.direction = gesture.edges // left or right edge
        super.init()

        // hook the gesture with our action handler to continue driving the interactive updates.
        self.edgeSwipeGesture.addTarget(self, action: #selector(handleGestureEdgePan))
    }
    
    override func startInteractiveTransition(_ transitionContext: UIViewControllerContextTransitioning) {
        containerView = transitionContext.containerView
        super.startInteractiveTransition(transitionContext)
    }
    
    @objc func handleGestureEdgePan(gesture: UIScreenEdgePanGestureRecognizer) {
        let currentView = containerView
        let panLocation = gesture.location(in: currentView)
        var percentage:CGFloat = 0.0
        
        switch gesture.state {
        case .began:
            gesture.setTranslation(CGPoint(), in: currentView)
            break

        case .changed:
            percentage = self.updatePercentage(locationX: panLocation.x, viewWidth: currentView.bounds.width, direction: gesture.edges)
            self.update(percentage)
            self.shouldFinish = percentage > 0.25
            break

        case .ended:
             if shouldFinish {
                finish()
            } else {
                cancel()
            }
            break

        default:
            cancel()
            break
        }
    }
    
    override func finish() {
        super.finish()
        edgeSwipeGesture.removeTarget(self, action: #selector(handleGestureEdgePan))
    }

    override func cancel() {
        super.cancel()
        edgeSwipeGesture.removeTarget(self, action: #selector(handleGestureEdgePan))
    }
    
    private func updatePercentage(locationX: CGFloat, viewWidth: CGFloat, direction: UIRectEdge) -> CGFloat {
        var percentage: CGFloat = 0.0
        let modifier: CGFloat = (viewWidth / 2) // improve the feel of the gesture as the user pulls out the sidebar
        if direction == .left {
            percentage = locationX / modifier
        } else {
            percentage = (viewWidth - locationX) / modifier
        }
        return fmax(fmin(percentage, 0.99), 0.0)
    }
}


