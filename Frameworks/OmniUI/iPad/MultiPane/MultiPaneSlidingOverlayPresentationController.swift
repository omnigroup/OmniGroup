// Copyright 2016-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

class MultiPaneSlidingOverlayPresenter: NSObject, UIViewControllerTransitioningDelegate {
    let pinBarButton: UIBarButtonItem
    let presentingPane: Pane
    var isInteractive: Bool = false
    
    var edgeGesture: UIScreenEdgePanGestureRecognizer? {
        didSet {
            if self.edgeGesture != nil {
                self.isInteractive = true
            } else {
                self.isInteractive = false
            }
        }
    }
    
    init(pane: Pane, pinBarButtonItem item: UIBarButtonItem) {
        self.presentingPane = pane
        self.pinBarButton = item
        super.init()
    }
    
    func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        return SlidingOverlayAnimator(withPane: self.presentingPane, presenting: true)
    }
    
    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        // NOTE: this is not called when we rotate during a presenation. Trying to animate that transition leaves the system in a bad state.
        return SlidingOverlayAnimator(withPane: self.presentingPane, presenting: false)
    }
    
    func interactionControllerForPresentation(using animator: UIViewControllerAnimatedTransitioning) -> UIViewControllerInteractiveTransitioning? {
        // If we are not interactive, we don't want to return an interactive animator. If we do, nothing will animate because nothing drives the animation.
        if !self.isInteractive { return nil }
        guard let gesture = self.edgeGesture, (gesture.edges == .left || gesture.edges == .right) && gesture.isEnabled else {
            print("skipping interactive presentation because the gesture isn't setup correctly") // FIXME: can this be an os_log_debug message instead?
            return nil
        }
        return SlidingOverlayInteractiveAnimator(gesture: gesture)
    }
    
    func presentationController(forPresented presented: UIViewController, presenting: UIViewController?, source: UIViewController) -> UIPresentationController? {
        return SldingOverlayPresentationController(withPane: self.presentingPane, presentingController: presenting)

    }
    
    @objc private func handlePinButton(sender: AnyObject?) {
        print("got a pin request")
        
    }
}


class SldingOverlayPresentationController: UIPresentationController {
    let shieldingView = UIView()
    var pane: Pane
    
    init(withPane pane: Pane, presentingController: UIViewController?) {
        self.pane = pane
        super.init(presentedViewController: self.pane.viewController, presenting: presentingController)
        self.overrideTraitCollection = UITraitCollection(horizontalSizeClass: .compact)
    }
    
    override func presentationTransitionWillBegin() {
        guard let container = self.containerView  else {
            assertionFailure("No container view, can't contiue")
            return
        }
        
        self.shieldingView.frame = container.bounds
        self.shieldingView.backgroundColor = UIColor.clear
        self.shieldingView.alpha = 0.0
        container.addSubview(self.shieldingView)
        
        let dismiss = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        dismiss.debugIdentifier = "overlay sidebar dismisser"
        self.shieldingView.addGestureRecognizer(dismiss)
        
        if let transition = self.presentedViewController.transitionCoordinator {
            transition.animate(alongsideTransition: { (context) in
                self.shieldingView.alpha = 0.3
                }, completion: nil)
        }
    }
    
    override func dismissalTransitionWillBegin() {
        if let transistion = self.presentedViewController.transitionCoordinator {
            transistion.animate(alongsideTransition: { (context) in
                self.shieldingView.alpha = 0.0
                }, completion: nil)
        }
    }
    
    override func size(forChildContentContainer container: UIContentContainer, withParentContainerSize parentSize: CGSize) -> CGSize {
        let width: CGFloat = self.pane.width
        return CGSize(width: width > 0.0 ? width : 320.0, height: parentSize.height)
    }
    
    override var frameOfPresentedViewInContainerView: CGRect {
        var presentedFrame = CGRect.zero
        let bounds = self.containerView!.bounds
        presentedFrame.size = self.size(forChildContentContainer: self.presentedViewController, withParentContainerSize: bounds.size)
        if self.pane.location == .right {
            presentedFrame.origin.x = bounds.width - presentedFrame.size.width
        } else {
            presentedFrame.origin.x = 0.0
        }
        
        return presentedFrame
    }
    
    override func containerViewDidLayoutSubviews() {
        super.containerViewDidLayoutSubviews()
        self.shieldingView.frame = self.containerView!.bounds
        self.presentedView?.frame = self.frameOfPresentedViewInContainerView
    }
    
    override var presentationStyle: UIModalPresentationStyle {
        return .custom
    }
    
    override func willTransition(to newCollection: UITraitCollection, with coordinator: UIViewControllerTransitionCoordinator) {
        super.willTransition(to: newCollection, with: coordinator)
        self.dismiss(animated: false)
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        self.dismiss(animated: false)
    }
    
    func handleTap(gesture: UITapGestureRecognizer) {
        self.dismiss(animated: true)
    }
    
    private func dismiss(animated: Bool) {
        self.presentedViewController.dismiss(animated: true, completion:nil)
    }
}

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
        return 0.3
    }
    
    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        let toViewController = transitionContext.viewController(forKey: UITransitionContextViewControllerKey.to)!
        let fromViewController = transitionContext.viewController(forKey: UITransitionContextViewControllerKey.from)!
       // let animatingView = self.isPresenting ? toViewController.view : fromViewController.view
        let containerView = transitionContext.containerView
        
        if self.isPresenting {
            containerView.addSubview(toViewController.view)
        }
        
        let operation: MultiPanePresenterOperation = self.isPresenting ? .overlay : .dismiss
        let animator = self.presentingPane.slidebarOverlayAnimator(forOperation: operation, interactive: transitionContext.isInteractive)
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
        self.containerView = transitionContext.containerView
        super.startInteractiveTransition(transitionContext)
    }
    
    func handleGestureEdgePan(gesture: UIScreenEdgePanGestureRecognizer) {
        let currentView = self.containerView
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
             if self.shouldFinish {
                self.finish()
            } else {
                self.cancel()
            }
            break
        default:
            self.cancel()
            break
        }
    }
    
    override func finish() {
        super.finish()
        self.edgeSwipeGesture.removeTarget(self, action: #selector(handleGestureEdgePan))
    }
    override func cancel() {
        super.cancel()
        self.edgeSwipeGesture.removeTarget(self, action: #selector(handleGestureEdgePan))
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


