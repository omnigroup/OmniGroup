// Copyright 2016-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

import UIKit

// Transitioning context used by MultiPaneController for handling compact navigation between panes and is used when the MultiPaneCompactTransitionStyle is .navigation
// Providing a custom UIViewControllerContextTransitioning is what allows for proper child controller containment before and after transitions, while still keeping a consistent interface for custom vc transitions to MultiPaneController clients.
//
class MultiPaneNavigationTransitionContext: NSObject, UIViewControllerContextTransitioning {
    let operation: UINavigationController.Operation
    let toViewController: UIViewController
    let fromViewController: UIViewController
    let animator: UIViewControllerAnimatedTransitioning
    let containerView: UIView
    
    @objc(isAnimated) var isAnimated: Bool = true
    @objc(isInteractive) var isInteractive: Bool = false
    var transitionWasCancelled: Bool = false // TODO: this should be dependent on the actual animation state.
    var completedTransition: (Bool) -> Void = { _ in }
    
    fileprivate var interactionChangedBlocks: [() -> ()] = []
    fileprivate var animationCompletionBlocks: [() -> ()] = []
    
    var propertyAnimator: UIViewPropertyAnimator?
    
    var presentationStyle: UIModalPresentationStyle {
        return .custom
    }
    
    init(fromViewController: UIViewController, toViewController: UIViewController, operation: UINavigationController.Operation, animator: UIViewControllerAnimatedTransitioning?) {
        self.toViewController = toViewController
        self.fromViewController = fromViewController
        self.operation = operation
        self.containerView = self.fromViewController.parent!.view
        self.animator = animator ?? MultiPanePushPopTransitionAnimator(with: operation, animator: nil)
        
        super.init()
        
        self.prepareForTransition()
    }
    
    func startTransition() {
        // note, that this should check for interactivity first.
        if self.isInteractive {
            if let propertyAnimator = self.animator.interruptibleAnimator?(using: self) as? UIViewPropertyAnimator {
                self.propertyAnimator = propertyAnimator
                // if we have an interruptible animator, and we are interactive, go ahead and use that. If we have a UIViewControllerAnimatedTransitioning that isn't using the new interruptibleAnimator just animate
                return
            }
            assertionFailure("Expcted the animator to provide a value for interruptibleAnimator() when using an interactive style transition")
        }
        
        self.animator.animateTransition(using: self)
    }
    
    func updateInteractiveTransition(_ percentComplete: CGFloat) {
        if let propertyAnimator = self.propertyAnimator {
            propertyAnimator.fractionComplete = percentComplete
        }
    }
    
    func finishInteractiveTransition() {
        for block in interactionChangedBlocks {
            block()
        }
        
        if let propertyAnimator = self.propertyAnimator {
            propertyAnimator.continueAnimation(withTimingParameters: nil, durationFactor: (1.0 - propertyAnimator.fractionComplete))
        }
    }
    
    func cancelInteractiveTransition() {
        for block in interactionChangedBlocks {
            block()
        }
        
        if let propertyAnimator = self.propertyAnimator {
            propertyAnimator.isReversed = true
            propertyAnimator.continueAnimation(withTimingParameters: nil, durationFactor: propertyAnimator.fractionComplete)
        }
    }

    func pauseInteractiveTransition() {
        if let propertyAnimator = self.animator.interruptibleAnimator?(using: self) {
            propertyAnimator.pauseAnimation()
        }
    }
    
    func completeTransition(_ didComplete: Bool) {
        guard let parentVC = self.fromViewController.parent else { return } // We've been booted off-screen

        if didComplete {
            self.fromViewController.view.removeFromSuperview()
            self.fromViewController.removeFromParent()
            self.toViewController.didMove(toParent: parentVC)
        } else {
            self.toViewController.willMove(toParent: nil)
            self.toViewController.view.removeFromSuperview()
            self.toViewController.removeFromParent()
        }
        
        finalizeTransition(didComplete)
    }
    
    func viewController(forKey key: UITransitionContextViewControllerKey) -> UIViewController? {
        guard key == .from || key == .to else {
            assertionFailure("Unknown UITransitionContextViewControllerKey key: \(key)")
            return nil
        }
        
        return key == .from ? self.fromViewController : self.toViewController
    }
    
    func view(forKey key: UITransitionContextViewKey) -> UIView? {
        guard key == .from || key == .to else {
            assertionFailure("Unknown UITransitionContextViewKey key: \(key)")
            return nil
        }
        
        let vcKey: UITransitionContextViewControllerKey = key == .from ? .from : .to
        return self.viewController(forKey: vcKey)?.view
    }

    var targetTransform: CGAffineTransform = CGAffineTransform.identity
    
    func initialFrame(for vc: UIViewController) -> CGRect {
        if vc == self.fromViewController {
            return self.containerView.bounds
        }
        
        return CGRect.zero
    }
    
    func finalFrame(for vc: UIViewController) -> CGRect {
        if vc == self.toViewController {
            return self.containerView.bounds
        }
        
        return CGRect.zero
    }

    private func prepareForTransition() {
        let parent = self.fromViewController.parent!
        self.fromViewController.willMove(toParent: nil)
        parent.addChild(self.toViewController)
    }
    
    private func finalizeTransition(_ didComplete: Bool) {
        self.completedTransition(didComplete)
        
        for block in animationCompletionBlocks {
            block()
        }
    }
}

extension MultiPaneNavigationTransitionContext: UIViewControllerTransitionCoordinatorContext {
    
    var transitionDuration: TimeInterval {
        return animator.transitionDuration(using: self)
    }
    
    var completionCurve: UIView.AnimationCurve {
        let defaultCurve = UIView.AnimationCurve.linear
        guard let propertyAnimator = propertyAnimator else { return defaultCurve }
        guard let parameters = propertyAnimator.timingParameters else { return defaultCurve }
        
        switch parameters.timingCurveType {
        case .builtin: fallthrough
        case .cubic:
            let cubic = parameters.cubicTimingParameters!
            return cubic.animationCurve

        case .spring: fallthrough
        case .composed:
            // TODO: can we do better than linear here?
            return defaultCurve
            
        @unknown default:
            return defaultCurve
        }
    }
    
    var completionVelocity: CGFloat {
        return 1.0
    }
    
    var percentComplete: CGFloat {
        return propertyAnimator?.fractionComplete ?? 0
    }
    
    var initiallyInteractive: Bool {
        // We never change this flag, so go ahead and use it
        return isInteractive
    }
    
    @objc(isCancelled) var isCancelled: Bool {
        return transitionWasCancelled
    }
    
    var isInterruptible: Bool {
        return propertyAnimator?.isInterruptible ?? false
    }
    
}

extension MultiPaneNavigationTransitionContext: UIViewControllerTransitionCoordinator {
    
    func animateAlongsideTransition(in view: UIView?, animation: ((UIViewControllerTransitionCoordinatorContext) -> Void)?, completion: ((UIViewControllerTransitionCoordinatorContext) -> Void)? = nil) -> Bool {
        if let propertyAnimator = propertyAnimator {
            propertyAnimator.addAnimations({ animation?(self) })
            propertyAnimator.addCompletion({ _ in completion?(self) })
        } else {
            assert(animation == nil, "Unimplemented: MultiPaneController doesn't yet support animations alongside a non-interactive transition") // TODO figure out how to implement this if necessary
            animationCompletionBlocks.append { [unowned self] in
                completion?(self)
            }
        }
        
        return true
    }
    
    func animate(alongsideTransition animation: ((UIViewControllerTransitionCoordinatorContext) -> Void)?, completion: ((UIViewControllerTransitionCoordinatorContext) -> Void)? = nil) -> Bool {
        return animateAlongsideTransition(in: containerView, animation: animation, completion: completion)
    }
    
    func notifyWhenInteractionChanges(_ handler: @escaping (UIViewControllerTransitionCoordinatorContext) -> Void) {
        interactionChangedBlocks.append { [unowned self] in
            handler(self)
        }
    }
    
    func notifyWhenInteractionEnds(_ handler: @escaping (UIViewControllerTransitionCoordinatorContext) -> Void) {
        notifyWhenInteractionChanges(handler)
    }
    
}

extension UINavigationController.Operation {
    func pushPopTransform(width: CGFloat) -> CGAffineTransform {
        switch self {
        case .push: return CGAffineTransform(translationX: width * -1, y: 0.0)
        case .pop: return CGAffineTransform(translationX: width, y: 0.0)
        case .none: return CGAffineTransform.identity
        @unknown default: return CGAffineTransform.identity
        }
    }
}

class MultiPanePushPopTransitionAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    let operation: UINavigationController.Operation
    
    // Default animation setup to mimic the push/pop style that UINavigationController uses.
    var animator: UIViewPropertyAnimator = UIViewPropertyAnimator(duration: 0.0, timingParameters: UISpringTimingParameters())
    
    init(with operation: UINavigationController.Operation, animator: UIViewPropertyAnimator?) {
        self.operation = operation
        if let animator = animator {
            self.animator = animator
        }
    }
    
    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        let animated = transitionContext?.isAnimated ?? false
        return animated == true ? self.animator.duration : 0.0
    }
    
    
    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        // this is a non-interruptible animation.
        
        self.interruptibleAnimator(using: transitionContext).startAnimation()
    }
    
    
    func interruptibleAnimator(using transitionContext: UIViewControllerContextTransitioning) -> UIViewImplicitlyAnimating {
        guard let toVC = transitionContext.viewController(forKey: .to), let fromVC = transitionContext.viewController(forKey: .from) else {
            assertionFailure("can't animate the transition without to and from view controllers")
            return UIViewPropertyAnimator() // return an animtor that does nothing
        }
        
        let containerView = transitionContext.containerView
        
        let toView = toVC.view!
        let fromView = fromVC.view!

        toView.frame = containerView.bounds
        fromView.frame = containerView.bounds
        
        let baseTransform = self.operation.pushPopTransform(width: containerView.bounds.width)
        
        let shieldingContainerView: UIView

        let fromViewAlpha: CGFloat
        let fromViewTransform: CGAffineTransform
        
        let shieldingViewFromAlpha: CGFloat
        let shieldingViewToAlpha: CGFloat

        // workout style and transfrom offsets based on the operation type.
        if self.operation == .pop {
             containerView.insertSubview(toView, belowSubview: fromView)
            let toTransform = CGAffineTransform(translationX: baseTransform.tx * 0.25, y: 0.0)
            toView.transform = toTransform.inverted()
            toView.alpha = 0.92
            
            fromViewAlpha = 1.0
            fromViewTransform = baseTransform

            shieldingContainerView = toView
            
            shieldingViewFromAlpha = 1.0
            shieldingViewToAlpha = 0.0
        } else {
            containerView.insertSubview(toView, aboveSubview: fromView)
            toView.transform = baseTransform.inverted()

            fromViewTransform = CGAffineTransform(translationX: baseTransform.tx * 0.25, y: 0.0)
            fromViewAlpha = 0.92
            
            shieldingContainerView = fromView

            shieldingViewFromAlpha = 0.0
            shieldingViewToAlpha = 1.0
        }

        let shieldingView = self.addShieldingView(to: shieldingContainerView)
        shieldingView.alpha = shieldingViewFromAlpha

        let transitionBlock = {
            fromView.transform = fromViewTransform
            fromView.alpha = fromViewAlpha
            toView.transform = CGAffineTransform.identity
            toView.alpha = 1.0
            shieldingView.alpha = shieldingViewToAlpha
        }
        
        let completionBlock: (UIViewAnimatingPosition) -> Void = { (position) in
            let didComplete = !transitionContext.transitionWasCancelled && position == .end
            
            // TODO: what else do we need to do here for a interactive transition?
            fromView.alpha = 1.0
            toView.alpha = 1.0
            fromView.transform = CGAffineTransform.identity

            shieldingView.removeFromSuperview()

            transitionContext.completeTransition(didComplete)
        }
        
        // Honor transitionContext.isAnimated flag by either applying or animation and completion block work to the animator or applying directly.
        // From what i can tell, there really isn't a better way to do this.
        if transitionContext.isAnimated {
            self.animator.addAnimations {
                transitionBlock()
            }
        
            self.animator.addCompletion { (position) in
                completionBlock(position)
            }
        } else {
            // Add an empty animation block to keep the system happy.
            // For non-animating versions, we have to return the same animator, but we don't want to do any work, so the empty block just keeps the system from asserting.
            self.animator.addAnimations {}
            transitionBlock()
            completionBlock(.end)
        }
        
        return self.animator
    }
    
    private func addShieldingView(to view: UIView) -> UIView {
        let shieldingColor: UIColor
        
        switch view.traitCollection.userInterfaceStyle {
        case .dark:
            shieldingColor = UIColor.clear
            
        case .light, .unspecified:
            fallthrough
            
        @unknown default:
            shieldingColor = UIColor.black.withAlphaComponent(0.10)
        }

        let shieldingView = UIView(frame: view.bounds)
        shieldingView.translatesAutoresizingMaskIntoConstraints = false
        shieldingView.backgroundColor = shieldingColor
        
        view.addSubview(shieldingView)

        return shieldingView
    }
}

class MultiPaneInteractivePushPopAnimator: NSObject, UIViewControllerInteractiveTransitioning {
    let gesture: UIScreenEdgePanGestureRecognizer
    var transitionContext: MultiPaneNavigationTransitionContext?
    var shouldFinish = false
    
    // points per second, and when exceeded and the user lifts the finger on the gesture, the transition will be completed (even if the gesture travel distance would have otherwise cancelled the transition). Set to a higher value if a swipe is becomes to sensitive.
    let velocityThreshold: CGFloat = 200.0
    
    // the percentage of translation change that must happen before the transition will be completed when the gesture ends. If not exceeded, the transition will be cancelled.
    let completionThreshold: CGFloat = 0.45
    
    init(with gesture: UIScreenEdgePanGestureRecognizer) {
        self.gesture = gesture
        super.init()
        self.gesture.addTarget(self, action: #selector(MultiPaneInteractivePushPopAnimator.screenEdgeGesture(gesture:)))
        self.gesture.isEnabled = true
    }
    
    deinit {
        gesture.removeTarget(self, action: #selector(MultiPaneInteractivePushPopAnimator.screenEdgeGesture(gesture:)))
    }
    
    func startInteractiveTransition(_ transitionContext: UIViewControllerContextTransitioning) {
        guard let transitionContext = transitionContext as? MultiPaneNavigationTransitionContext else {
            assertionFailure("expected a MultiPaneNavigationTransitionContext")
            return
        }
        
        self.transitionContext = transitionContext
        transitionContext.startTransition()
    }
    
    @objc func screenEdgeGesture(gesture: UIScreenEdgePanGestureRecognizer) {
        let translation = gesture.translation(in: gesture.view!.superview)
        // grab the horizontal velocity, which is points per second and use that to detect swipes that should finish a transition
        let hVelocity = gesture.velocity(in: gesture.view!.superview).x
        
        switch gesture.state {
        case .began:
            break
        case .changed:
            let change: CGFloat = min(max(translation.x / (gesture.view!.bounds.width * 0.667), 0.0), 1.0)
            self.transitionContext?.updateInteractiveTransition(change)
            self.shouldFinish = change > self.completionThreshold
            break
        case .ended, .failed, .cancelled:
            // arbitray threshold picked for the hVelocity detection. If we are to sensitive to swipes, we should increase this number.
            if gesture.state == .ended && hVelocity > self.velocityThreshold || self.shouldFinish {
                self.transitionContext?.finishInteractiveTransition()
            } else {
                self.transitionContext?.cancelInteractiveTransition()
            }
            gesture.setTranslation(CGPoint.zero, in: gesture.view)
            gesture.removeTarget(self, action: #selector(MultiPaneInteractivePushPopAnimator.screenEdgeGesture(gesture:)))
            break
        default:
            self.transitionContext?.cancelInteractiveTransition()
            break
        }
    }
}
