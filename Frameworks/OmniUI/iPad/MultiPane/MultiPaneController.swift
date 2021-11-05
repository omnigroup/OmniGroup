// Copyright 2016-2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

@objc(OUIMultiPaneLayoutDelegate) public protocol MultiPaneLayoutDelegate {
    /// called for regular width transitions, and gives the delegate an opportunity to change the displayMode
    /// if .Compact is returned, the passed in displayMode will be used.
    @objc optional func wantsTransition(to displayMode: MultiPaneDisplayMode, on multiPaneController: MultiPaneController, using viewSize: CGSize) -> MultiPaneDisplayMode
    
    /// When the displayMode changes into .multi, we try to fit all 3 panes onto the screen. If we can't, we need to convert one of them into .overlay. By default we will convert the left pane into .overlay, but this gives the delegate a chance to change that behavior.
    @objc optional func locationToBecomeOverlay(displayMode: MultiPaneDisplayMode, multiPaneController: MultiPaneController, viewSize: CGSize) -> MultiPaneLocation
    
    /// called just before the display mode is changed on the MultiPaneController
    @objc optional func willTransition(to displayMode: MultiPaneDisplayMode, multiPaneController: MultiPaneController)
    
    /// called after the displayMode has been updated and the new pane layout is complete.
    /// NOTE: If you need to update a bar button item managed by the MultiPaneController, implement this delegate and access the button from the MultiPaneController. By the time this function is called, the button will have been returend to its deafult state.
    @objc optional func didTransition(to displayMode: MultiPaneDisplayMode, multiPaneController: MultiPaneController)
    
    /// called before hiding a pane if the displayMode is .multi and the pane is either .embeded or .overlay
    @objc optional func willHidePane(at location: MultiPaneLocation, multiPaneController: MultiPaneController)
    
    /// called before showing a pane if the displayMode is .multi and the pane is either .embeded or .overlay
    @objc optional func willShowPane(at location: MultiPaneLocation, multiPaneController: MultiPaneController)
    
    /// called before hiding a pane if the displayMode is .multi and the pane is either .embeded or .overlay
    @objc optional func didHidePane(at location: MultiPaneLocation, multiPaneController: MultiPaneController)
    
    /// called after showing a pane if the displayMode is .multi and the pane is either .embeded or .overlay
    @objc optional func didShowPane(at location: MultiPaneLocation, multiPaneController: MultiPaneController)
    
    /// called before showing a pane if the pane is .embeded and the displayMode is .multi. Called before willShowPane, as a false return value can preempt showing the pane.
    @objc optional func shouldShowPane(at location: MultiPaneLocation, multiPaneController: MultiPaneController) -> Bool

    /// called after updating button items.
    @objc optional func didUpdateDisplayButtonItems(_ multiPaneController: MultiPaneController)
    
    @objc optional func wantsUnpinnedPane(at location: MultiPaneLocation, multiPaneController: MultiPaneController) -> Bool
    @objc optional func willPinPane(at location: MultiPaneLocation, multiPaneController: MultiPaneController)
    @objc optional func didPinPane(at location: MultiPaneLocation, multiPaneController: MultiPaneController)
    @objc optional func willUnpinPane(at location: MultiPaneLocation, multiPaneController: MultiPaneController)
    @objc optional func didUnpinPane(at location: MultiPaneLocation, multiPaneController: MultiPaneController)
}

@objc (OUIMultiPaneNavigationDelegate) public protocol MultiPaneNavigationDelegate {
    
    /// default transition style is MultiPaneTransitionStyle.modal
    @objc (compactTransitioningStyleForLocation:) optional func compactTransitioningStyle(for location: MultiPaneLocation) -> MultiPaneCompactTransitionStyle

    /// If a responder in the right pane resigns, the search for a new first responder will go through the multi-pane controller and possibly end up in the window's root view controller. This allows the delegate to supply a better default (likely in the center pane). If the delegate is the OUIDocument subclass, this will map to the method of the name name on that class.
    @objc optional func defaultFirstResponder() -> UIResponder?

    /// called before a transition to left/center. (currently only called for transistions in compact) and only for the transition style is MultiPaneTransitionStyle.navigate
    @objc optional func willNavigate(toPane location: MultiPaneLocation, with multiPaneController: MultiPaneController)

    /// called faster a transition to left/center. (currently only called for transistions in compact) and only for the transition style is MultiPaneTransitionStyle.navigate
    @objc optional func didNavigate(toPane location: MultiPaneLocation, with multiPaneController: MultiPaneController)

    @objc optional func animationsToPerformAlongsideEmbeddedSidebarShowing(atLocation: MultiPaneLocation, withWidth: CGFloat) -> (()->())?

    @objc optional func animationsToPerformAlongsideEmbeddedSidebarHiding(atLocation: MultiPaneLocation, withWidth: CGFloat) -> (()->())?
    
    /// allows the delegate to setup the view controller that is going to be presented. Currently this is only called when the MultiPaneController is in compact mode. The overlay presentations are not effected by this.
    @objc(willPresentViewController:) optional func willPresent(viewController: UIViewController)
    
    /// called prior to a transition when the MultiPaneCompactTransitionStyle is .navigation
    @objc optional func navigationAnimationController(for operation: UINavigationController.Operation, animating toViewController: UIViewController, fromViewController: UIViewController, multiPaneController: MultiPaneController) -> UIViewControllerAnimatedTransitioning?
    
    /// called when the user taps one of the bar button items before presentation. This is called in addition to the willHidePane and willShowPane methods, but this will also be called in every displayMode. If the receiver only cares about this message in certain displayModes, it can check the display mode of the multiPaneController parameter.
    @objc optional func userWillExplicitlyToggleVisibility(_ paneWillBeShown: Bool, at location: MultiPaneLocation, multiPaneController: MultiPaneController)
    
    @objc optional func responderPreservationStyle(for responder: UIResponder & UITextInput, transitioningFrom oldTraitCollection: UITraitCollection, to newTraitCollection: UITraitCollection, multiPaneController: MultiPaneController) -> MultiPaneResponderPreservationStyle
    
    /// Called when the MPC transitions from compact with a presentation atop a modally presented pane to a multipane environment. This gives the caller a chance to anchor the popover to a new bar button item after that transition. If this is not implemented or returns nil, the popover is anchored to the bar button its popoverPresentationController was supplied with when it was originally presented. If your app recalculates and regenerates bar button items during this transition, implement this method and return newly created bar button item that fulfills the same function as the old item. Otherwise, the popover will be presented without an anchor, at the top left corner of the screen.
    @objc optional func barButtonItemForRetargetingPopoverOnTransitionToMultiMode(_ popover: UIViewController, presentingOn controller: UIViewController, originalSourceBarButtonItem: UIBarButtonItem) -> UIBarButtonItem?
    
    @objc optional func userWillBeginInteractiveGesturePresentation(at location: MultiPaneLocation, multiPaneController: MultiPaneController)
    
    @objc optional func userDidEndInteractiveGesturePresentation(at location: MultiPaneLocation, multiPaneController: MultiPaneController)
}

@objc (OUIMultiPaneAppearanceDelegate) public protocol MultiPaneAppearanceDelegate {
    
    /// If implemented, call when the MultiPaneController receives preferredStatusBarStyle. If the delegate does not implement this, preferredStatusBarStyle will return default
    @objc optional func preferredStatusBarStyle(for multiPaneController: MultiPaneController) -> UIStatusBarStyle
}

@objc (OUIMultiPaneCompactTransitionStyle) public enum MultiPaneCompactTransitionStyle: Int {
    case modal = 0 // default, center pane is always embedded, left or right panes are presented modally
    case navigation // Provides a transistion between the the center and left/right panes using a transition animation like UINavigationController. The controller being transitioned to will end up embedded, and the transitioned from controller will be out of the view hierarchy.
    
    case custom // we may be able to get rid of this now. <bug:///137300> (Frameworks-iOS Unassigned: Review uses of MultiPaneCompactTransitionStyle.custom)
}

@objc(OUIMultiPaneLocation) public enum MultiPaneLocation: Int {
    case left = 0
    case center
    case right
}

@objc(OUIMultiPaneResponderPreservationStyle) public enum MultiPaneResponderPreservationStyle: Int {
    case none = 0
    case showPane
    case showPaneAndReactivateFirstResponder
}

public extension MultiPaneLocation {
    init?(named name: String) {
        switch name {
        case "left": self = .left
        case "right": self = .right
        case "center": self = .center
        default: assertionFailure("Unknown MultiPaneLocation \"\(name)\""); return nil
        }
    }
}

extension MultiPaneLocation: CustomStringConvertible {
    public var name: String {
        switch self {
        case .left: return "left"
        case .right: return "right"
        case .center: return "center"
        }
    }
    
    public var description: String {
        return name
    }
}

@objc(OUIMultiPaneDisplayMode) public enum MultiPaneDisplayMode: Int {
    case compact // compact width environment, individual apps can customize "sidebar" presentation (presented modally by default)
    case single  // regular width environment, sidebars are overlaid when shown
    case multi   // regular width environment, one or more sidebars will be embedded, one sidebar may be overlaid when shown
}

public extension MultiPaneDisplayMode {
    init?(named name: String) {
        switch name {
        case "compact": self = .compact
        case "single": self = .single
        case "multi": self = .multi
        default: assertionFailure("Unknown MultiPaneDisplayMode \"\(name)\""); return nil
        }
    }
}

extension MultiPaneDisplayMode: CustomStringConvertible {
    public var name: String {
        switch self {
        case .compact: return "compact"
        case .single: return "single"
        case .multi: return "multi"
        }
    }
    
    public var description: String {
        return name
    }
}

@objc(OUIMultiPaneController) open class MultiPaneController: UIViewController {
    // It's possible for the actions triggered by sending `willTransition(to:, multiPaneController:)` to our layout delegate to prompt a recursive call to `displayMode:` with the same argument. For example, this happens in OmniFocus when a call to `CATransaction.flush()` triggers a `traitCollectionDidChange` notification. Rather than requiring that delegate code be reëntrant, we avoid posting the redundant `willTransition` message.
    private var displayModeForCurrentWillTransitionNotification: MultiPaneDisplayMode? = nil
    private var layoutConstraints: [NSLayoutConstraint] = []

    @objc fileprivate(set) public var displayMode: MultiPaneDisplayMode = .multi {
        willSet {
            if newValue != displayMode && newValue != displayModeForCurrentWillTransitionNotification {
                displayModeForCurrentWillTransitionNotification = newValue
                layoutDelegate?.willTransition?(to: newValue, multiPaneController: self)
                displayModeForCurrentWillTransitionNotification = nil
            }
        }
        
        didSet {
            let changed = (oldValue != displayMode)
            if  changed {
                // for compact transitions from another display mode, we want to show the center pane
                visibleCompactPane = .center
            }
            
            preparePanesForLayout(toMode: displayMode, withSize: currentSize)
            if changed {
                updateDisplayButtonItems(forMode: displayMode)
                for pane in orderedPanes {
                    pane.viewController.multiPaneConfiguration = MultiPaneConfiguration(displayMode: displayMode, size: currentSize)
                }
                
                layoutDelegate?.didTransition?(to: displayMode, multiPaneController: self)
            }
        }
    }
    
    fileprivate var visibleCompactPane: MultiPaneLocation = .center
    fileprivate var pinRequest: PinRequest?
    fileprivate var pinningLayoutPass: Bool = false
    
    // ordered array of panes from Left to Right
    @objc /**REVIEW**/ open var orderedPanes: [Pane] {
        return panes.sorted { $0.location.rawValue < $1.location.rawValue }
    }
    
    @objc open weak var layoutDelegate: MultiPaneLayoutDelegate?
    @objc open weak var navigationDelegate: MultiPaneNavigationDelegate?
    @objc /**REVIEW**/ open weak var appearanceDelegate: MultiPaneAppearanceDelegate?
    
    @objc /**REVIEW**/ lazy var multiPanePresenter: MultiPanePresenter = {
        let presenter = MultiPanePresenter()
        presenter.delegate = self
        return presenter
    }()
    
    /// Backing property so we can force re-creation of leftEdgePanGesture.

    private var _leftEdgePanGesture: UIScreenEdgePanGestureRecognizer? = nil

    @discardableResult
    private func resetLeftEdgePanGesture() -> UIScreenEdgePanGestureRecognizer {
        if let recognizer = _leftEdgePanGesture {
            if self.isViewLoaded {
                self.view.removeGestureRecognizer(recognizer)
            }
        }

        let gesture = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(MultiPaneController.handleScreenEdgePanGesture))
        gesture.edges = .left
        gesture.delegate = self
        gesture.debugIdentifier = "MultiPane left edge swipe"
        _leftEdgePanGesture = gesture

        if self.isViewLoaded {
            self.view.addGestureRecognizer(gesture)
        }

        return gesture
    }

    // TODO: This gets replaced at random intervals, so it shouldn't be public (otherwise a caller might latch onto a recognizer that is no longer in use).
    @objc open var leftEdgePanGesture: UIScreenEdgePanGestureRecognizer {
        get {
            return _leftEdgePanGesture ?? resetLeftEdgePanGesture()
        }
    }
    
    @objc open lazy var leftPaneDisplayButton: UIBarButtonItem = {
        let image = UIImage(systemName: "sidebar.left") ?? UIImage(named: "OUIMultiPaneLeftSidebarButton", in: OmniUIBundle, compatibleWith: self.traitCollection)
        let button = UIBarButtonItem(image: image, style: .plain, target: self, action: #selector(handleLeftPaneDisplayButton))
        return button
    }()
    
    @objc open lazy var rightPaneDisplayButton: UIBarButtonItem = {
        let image = UIImage(systemName: "sidebar.right") ?? UIImage(named: "OUIMultiPaneRightSidebarButton", in: OmniUIBundle, compatibleWith: self.traitCollection)
        let button = UIBarButtonItem(image: image, style: .plain, target: self, action: #selector(handleRightPaneDisplayButton))
        return button
    }()
    
    @objc public var leftPanePinButton: UIBarButtonItem {
        return multiPanePresenter.leftPinButton
    }
    
    @objc public var rightPanePinButton: UIBarButtonItem {
        return multiPanePresenter.rightPinButton
    }
    
    private func pinButton(forPaneAt location: MultiPaneLocation) -> UIBarButtonItem {
        switch location {
        case .left: return leftPanePinButton
        case .right: return rightPanePinButton
        case .center: fatalError("Don't request the pin button for the center pane. It doesn't exist.")
        }
    }

    private var panes: Set<Pane> = [] // the order of the panes is determined by the Pane.location value, so actual storage order isn't relevant
    private var deferChildControllerContainment = false
    public var currentSize: CGSize {
        // If we're in an animation that happens alongside for viewWillTransitionToSize, transitionDestinationSize will hold the size we'll be after the animation. See the comment by transitionDestinationSize's declaration for more info.
        return transitionDestinationSize ?? view.bounds.size
    }
    
    public var paneVisibilityIsReliableWithCurrentSize: Bool {
        // If we're transitioning from one size to another, our pane visibility may change when we reach that destination size.
        return transitionDestinationSize == view.bounds.size || transitionDestinationSize == nil
    }
    
    private var widthOfSidebars: CGFloat {
        return orderedPanes.reduce(0.0, { (value, pane) in
            let width = pane.configuration is Sidebar ? pane.width : 0.0
            return value + width
        })
    }
    
    private var widthOfPanes: CGFloat {
        let center = pane(withLocation: .center)!
        let minWidth = center.centerPanePinWidthThreshold
        #if DEBUG_kc
        print("DEBUG: minWidth=\(minWidth) widthOfSidebars=\(widthOfSidebars)")
        #endif
        return minWidth + widthOfSidebars
    }
    
    // MARK: - View Controller Lifecycle
    
    override open func viewDidLoad() {
        super.viewDidLoad()
        
        if view.backgroundColor == nil {
            view.backgroundColor = UIColor.systemBackground
        }
        
        if deferChildControllerContainment {
            deferChildControllerContainment = false
            // do containment work
            orderedPanes.forEach { insertPane(pane: $0) }
        }
        
        updateDisplayMode(forSize: currentSize, traitCollection: traitCollection)

        resetLeftEdgePanGesture()
    }
    
    override open func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        
    }
    
    override open func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        //updateDisplayButtonItems(forMode: displayMode)
    }
    
    override open func viewDidAppear(_ animated: Bool) {
        // <bug:///147267> (Frameworks-iOS Engineering: Remove requirement to subclass MultiPaneController in order to (re)customize leftPaneDisplayButton)
        super.viewDidAppear(animated)
        updateDisplayButtonItems(forMode: displayMode)
    }
    
    // MARK: - View Controller Trait Environment
    
    override open func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        self.pinningLayoutPass = false
        updateDisplayMode(forSize: currentSize, traitCollection: traitCollection)
        
        asyncPaneAndResponderRestorationIfNeeded()
        
        // If we've changed display modes, we've already updated the decorations.
        // If not, and the color appearance has changed, they may need an appeareance/decoration update.
        // (Doing that work in the case that we already have just above for the layout is OK.)
        //
        // Use perform as current in case the trait collection hasn't propagated down to the pane's view controllers.
        traitCollection.performAsCurrent {
            self.panes.forEach { $0.traitCollectionDidChange(previousTraitCollection) }
        }
    }
    
    override open func willTransition(to newCollection: UITraitCollection, with coordinator: UIViewControllerTransitionCoordinator) {
        // Must happen before super. Super propagates this to child controllers, and they may end editing in response to a trait collection change. We want to cache the responder before they get that chance.
        saveCurrentPaneAndFirstResponderForRestoration(for: newCollection)
        
        super.willTransition(to: newCollection, with: coordinator)
        
        coordinator.animate(alongsideTransition: { [weak self] (context) in
            guard let strongSelf = self else { return }
            strongSelf.pinningLayoutPass = false
            strongSelf.updateDisplayMode(forSize: strongSelf.currentSize, traitCollection: newCollection)
        }, completion: nil)
    }
    
    // This storage is used as the return value for currentSize if it's non-nil. If we're transitioning to a given size, consumers need to be able to know what that size is in order to properly update if our display mode changes.
    private var transitionDestinationSize: CGSize?
    override open func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        
        transitionDestinationSize = size
        coordinator.animate(alongsideTransition: { [weak self] (context) in
            guard let strongSelf = self else { return }
            strongSelf.pinningLayoutPass = false
            strongSelf.updateDisplayMode(forSize: size, traitCollection: strongSelf.traitCollection)
        }, completion: { _ in
            self.transitionDestinationSize = nil
        })
    }
    
    override open var preferredStatusBarStyle: UIStatusBarStyle {
        return (self.appearanceDelegate?.preferredStatusBarStyle?(for: self)) ?? super.preferredStatusBarStyle
    }
    
    open override var transitionCoordinator: UIViewControllerTransitionCoordinator? {
        if let superCoordinator = super.transitionCoordinator {
            return superCoordinator
        }
        
        if let activeContext = multiPanePresenter.transitionContext {
            return activeContext
        }
        
        return nil
    }

    // MARK:- UIResponder

    open override var canBecomeFirstResponder: Bool {
        if let defaultResponder = navigationDelegate?.defaultFirstResponder?() {
            return defaultResponder.canBecomeFirstResponder
        }
        return super.canBecomeFirstResponder
    }

    open override func becomeFirstResponder() -> Bool {
        if let defaultResponder = navigationDelegate?.defaultFirstResponder?() {
            return defaultResponder.becomeFirstResponder()
        }
        return super.becomeFirstResponder()
    }

// MARK: - Other View Controller overrides
    
    override open var shouldAutorotate: Bool {
        if OUIRotationLock.hasActiveLocks {
            return false
        } else {
            return super.shouldAutorotate
        }
    }
    
    // MARK: - Public API
    @objc(addPrimaryViewController:)
    /// Add a view controller to the required pane location. Same as calling add(viewController at location: .center).
    @discardableResult open func add(primary viewController: UIViewController) -> Pane {
        return self.add(viewController: viewController, at: .center)
    }
    
    @objc(addViewController:atLocation:)
    /// add a new pane for for the given view controller, using the default configuration for the given location. Error to add a location that already exists.
    @discardableResult open func add(viewController: UIViewController, at location: MultiPaneLocation) -> Pane {
        guard self.pane(withLocation: location) == nil else {
            fatalError("Pane for location: \(location) already exists, must remove before adding")
        }
        
        let pane = Pane(withViewController: viewController, location: location)
        add(pane: pane)
        
        return pane
    }
    
    @objc(addPane:)
    open func add(pane: Pane) {
        guard !panes.contains(pane) else { return }
        panes.insert(pane)
        insertPane(pane: pane)

        if isViewLoaded {
            self.updateDisplayMode(forSize: self.currentSize, traitCollection: self.traitCollection)
        }
    }
    
    /// Removes the pane, if it exists, at the given location. Returns nil if the pane doesn't exist, otherwise returns the removed pane.
    /// The view controller associated with this pane will no longer be managed by the MultiPaneController and will be completely be rmoved from the view controller and view hierarchy.
    @discardableResult
    @objc open func removePane(at location: MultiPaneLocation) -> Pane? {
        guard let pane = self.pane(withLocation: location) else { return nil }
        self.removePane(pane: pane)

        // removePane(pane:) takes the child view controller out of the view (but leaves it in panes in case it is shown again later); this step absolves us of ownership entirely.
        panes.remove(pane)

        self.updateDisplayMode(forSize: self.currentSize, traitCollection: self.traitCollection)
        return pane
    }

    @discardableResult
    @objc open func replace(at location: MultiPaneLocation, viewController: UIViewController) -> Pane {
        // In particular, replacing the center pane is OK, but a remove/add with public API will hit errors.
        if let pane = self.pane(withLocation: location) {
            removePane(pane: pane)
        }
        return add(viewController: viewController, at: location)
    }

    /// Convenience method for returning the UIViewController currently installed in the pane at the given location.
    @objc public final func viewController(atLocation location: MultiPaneLocation) -> UIViewController? {
        return pane(withLocation: location)?.viewController
    }
    
    /// Convenience method for returning the UITraitCollection currently in use for the view controller at the given location.
    @objc public final func traitCollection(forChildAtLocation location: MultiPaneLocation) -> UITraitCollection? {
        return viewController(atLocation: location)?.traitCollection
    }
    
    @objc /**REVIEW**/ open func pane(withLocation location: MultiPaneLocation) -> Pane? {
        return panes.first { $0.location.rawValue == location.rawValue }
    }
    
    /// Show a pane for the given location in the style that MultiPaneController is acustomed. Calls showPane(at:animated:) with animation set to true.
    @objc open func showPane(atLocation location: MultiPaneLocation) {
        self.showPane(at: location, animated: true)
    }
    
    /// Show a pane for a given location, supplying an animation option, in the style that MultiPaneController is acustomed.
    @objc /**REVIEW**/ open func showPane(at location: MultiPaneLocation, animated: Bool) {
        showPane(at: location, animated: animated, completion: {})
    }
    
    /// Show a pane for a given location, supplying an animation option, in the style that MultiPaneController is acustomed.
    private func showPane(at location: MultiPaneLocation, animated: Bool, completion: @escaping ()->Void) {
        guard let pane = pane(withLocation: location) else { completion(); return }
        
        // If it's currently being dismissed, try to show it again once that's done
        guard !pane.isBeingDismissed else {
            DispatchQueue.main.async {
                self.showPane(at: location, animated: animated, completion: completion)
            }
            return
        }
        
        guard pane.isVisible == false else { completion(); return }
        
        multiPanePresenter.present(pane: pane, fromViewController: self, usingDisplayMode: displayMode, animated: animated, completion: completion)
    }
    
    /// Does nothing unless display mode is multi and the location is left or right
    @objc open func showSidebar(atLocation location: MultiPaneLocation) {
        guard (displayMode == .multi && (location == .right || location == .left)) else { return }
        
        guard let thePane = pane(withLocation: location) else { return }
        if (!thePane.isVisible) {
            multiPanePresenter.present(pane: thePane, fromViewController: self, usingDisplayMode: displayMode)
        }
    }
    
    /// Does nothing unless display mode is multi and the location is left or right
    @objc open func hideSidebar(atLocation location: MultiPaneLocation) {
        guard ((location == .right || location == .left)) else { return }
        guard let pane = pane(withLocation: location) else { return }
        guard pane.isVisible else { return }
        
        switch pane.presentationMode {
        case .embedded:
            // N.B. present(pane:fromViewController:usingDisplayMode:) is poorly named; it will actually toggle visibility in some cases, such as this one.
            multiPanePresenter.present(pane: pane, fromViewController: self, usingDisplayMode: displayMode)
            
        case .overlaid, .none:
            multiPanePresenter.dismiss(fromViewController: self, animated: true, completion: nil)
        }
    }
    
    /// Dismisses the overlay sidebar if necessary; otherwise a no-op
    @objc open func dismissSidebarIfNecessary(sidebar location: MultiPaneLocation) {
        guard let pane = pane(withLocation: location) else { return }
        if (pane.presentationMode != .embedded) && pane.isVisible {
            hideSidebar(atLocation: location)
        }
    }

    /// Intented to be called due to a user interface element (like the rightPaneDisplayButton) toggling the visibility of the rightPane.
    @objc public func toggleRightPane() {
        guard let rightPane = pane(withLocation: .right) else { return }
        self.navigationDelegate?.userWillExplicitlyToggleVisibility?(!rightPane.isVisible, at: .right, multiPaneController: self)
        multiPanePresenter.present(pane: rightPane, fromViewController: self, usingDisplayMode: displayMode)
    }

    @objc public func toggleLeftPane() {
        guard let leftPane = pane(withLocation: .left) else { return }
        let wantVisible = !leftPane.isVisible
        self.navigationDelegate?.userWillExplicitlyToggleVisibility?(wantVisible, at: .left, multiPaneController: self)
        if wantVisible || (leftPane.presentationMode == .embedded && displayMode == .multi) {
            multiPanePresenter.present(pane: leftPane, fromViewController: self, usingDisplayMode: displayMode)
        } else {
            self.dismissSidebarIfNecessary(sidebar: .left)
        }
    }

//MARK: - Private api
    
    func asyncPaneAndResponderRestorationIfNeeded() {
        if let paneAndResponder = paneAndResponderToReinstateUponTraitCollectionDidChange {
            DispatchQueue.main.async {
                self.showPane(at: paneAndResponder.location, animated: false) {
                    paneAndResponder.responder?.becomeFirstResponder()
                }
            }
            paneAndResponderToReinstateUponTraitCollectionDidChange = nil
        }
    }
    
    func saveCurrentPaneAndFirstResponderForRestoration(for destinationTraitCollection: UITraitCollection) {
        // We currently only want to save this information on the non-compact -> compact transition
        guard destinationTraitCollection.horizontalSizeClass == .compact && displayMode != .compact else { return }
        
        // We're already waiting to restore some cached value
        guard paneAndResponderToReinstateUponTraitCollectionDidChange == nil else { return }
        
        // Only restore text editing
        guard let responder = UIResponder.firstResponder as? UIResponder & UITextInput else { return }
        
        var paneContainingFirstResponder: MultiPaneLocation? = nil
        let precedingResponder = self.view.window ?? self.furthestAncestor
        if let leftController = pane(withLocation: .left)?.viewController, leftController.isInActiveResponderChain(preceding: precedingResponder) {
            paneContainingFirstResponder = .left
        } else if let rightController = pane(withLocation: .right)?.viewController, rightController.isInActiveResponderChain(preceding: precedingResponder) {
            paneContainingFirstResponder = .right
        } else if let centerController = pane(withLocation: .center)?.viewController, centerController.isInActiveResponderChain(preceding: precedingResponder) {
            paneContainingFirstResponder = .center
        }
        
        // There's only one responder per app, so perhaps the first responder is active in another scene?
        guard let paneToRestore = paneContainingFirstResponder else { return }
        
        // This caching is opt-in. Make the delegate call at the last second, so we only ask the delegate for input if we are actually about to try to cache some data to try to restore later.
        guard let preservationStyle = self.navigationDelegate?.responderPreservationStyle?(for: responder, transitioningFrom: traitCollection, to: destinationTraitCollection, multiPaneController: self) else { return }
        
        switch preservationStyle {
        case .showPaneAndReactivateFirstResponder:
            paneAndResponderToReinstateUponTraitCollectionDidChange = (paneToRestore, responder)
        case .showPane:
            paneAndResponderToReinstateUponTraitCollectionDidChange = (paneToRestore, nil)
        case .none:
            break
        }
    }
    
//MARK: - Pane containment and layout
    @objc /**REVIEW**/ internal func pane(forViewController controller: UIViewController) -> Pane? {
        return orderedPanes.first { pane in
            if pane.viewController == controller {
                return true
            } else if controller is MultipanePresentationWrapperViewController {
                assert(controller.children.count == 1 && !(controller.children.first is MultipanePresentationWrapperViewController))
                if pane.viewController == controller.children.first {
                    return true
                }
            }
            return false
        }
    }
    
    private func insertPane(pane: Pane) {
        if !isViewLoaded {
            deferChildControllerContainment = true
            return
        }
        
        let viewController = pane.viewController
        if !children.contains(viewController) {
            addChild(viewController)
            viewController.view.translatesAutoresizingMaskIntoConstraints = false
            view.insertSubview(viewController.view, at: pane.location.rawValue)
            viewController.didMove(toParent: self)
            if pane.configuration is Sidebar {
                setupDividerIfNeeded(onPane: pane)
            }
            
            // We need to let nav controller's back gesture have precedence over our own. Sadly implementing the gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer) delegate method doesn't work. We're never consulted about the system's recognizer. Maybe UIKit is doing something “smart” with edge pan recognizers? bug:///142212 (iOS-OmniFocus Regression: Swipe navigation no longer works in the sidebar [interactive back gesture])
            if pane.location == .left, let navigationController = viewController as? UINavigationController, let navPop = navigationController.interactivePopGestureRecognizer {
                // Clear our existing recognizer so it doesn't keep accumulating a list of failure requirements. Then get a new recognizer.
                let gesture = resetLeftEdgePanGesture()
                gesture.require(toFail: navPop)
            }
        }
    }
    
    private func removePane(pane: Pane) {
        let viewController = pane.viewController
        if children.contains(viewController) {
            viewController.willMove(toParent: nil)
            viewController.view.removeFromSuperview()
            viewController.removeFromParent()
        }
    }
    
    var isShowingTransitionShieldView: Bool = false
    var paneAndResponderToReinstateUponTraitCollectionDidChange: (location: MultiPaneLocation, responder: UIResponder?)? = nil
    // setup the display mode for the given screen/windo size and trait collection
    // Called when a view controller size/trait transition occurs.
    fileprivate func updateDisplayMode(forSize size: CGSize, traitCollection: UITraitCollection) {
        guard pane(withLocation: .center) != nil else {
            // <bug:///174861> (iOS-OmniFocus Crasher: Has repro: iPadOS 13, specialized MultiPaneController.updateDisplayMode(forSize:traitCollection:) (MultiPaneController.swift:0), DatabaseSceneCoordinator.initialSetup() (DatabaseSceneCoordinator.swift:641))
            // In iOS 13, this started getting called from transitions very early in the window setup; don't crash, but return early
            return
        }
        
        var preferredMode: MultiPaneDisplayMode = .multi
        
        if traitCollection.horizontalSizeClass == .compact {
            preferredMode = .compact
        } else {
            let screenSize = UIScreen.main.bounds.size
            
            if size.width < screenSize.height || size.width < screenSize.width {
                // portrait or multitasking mode, traditionally single pane
                preferredMode = .single
            } else {
                // landscape, or traditionally multi pane
                preferredMode = .multi
            }
            
            let mode = layoutDelegate?.wantsTransition?(to: preferredMode, on: self, using: size) ?? preferredMode
            
            // .Compact isn't a valid response here, so guard against it and use the preferredMode instead.
            if mode != .compact {
                preferredMode = mode
            }
        }
        
        if let presentedController = presentedViewController, let pane = pane(forViewController: presentedController), displayMode == .compact && preferredMode != .compact {
            guard let view = view else { return }
            guard !isShowingTransitionShieldView else { return }
            
            
            let savedFirstResponder = UIResponder.firstResponder
            
            var presentedControllerQueue: [(controller: UIViewController, item: UIBarButtonItem?)] = []
            var loopController = presentedController
            while let anotherPresentation = loopController.presentedViewController {
                // We treat the end as the head of the queue
                presentedControllerQueue.insert((anotherPresentation, anotherPresentation.popoverPresentationController?.barButtonItem), at: 0)
                loopController = anotherPresentation
            }
            
            
            let shieldView = UIView(frame: view.frame)
            shieldView.translatesAutoresizingMaskIntoConstraints = false
            shieldView.backgroundColor = UIColor.systemBackground
            view.addSubview(shieldView)
            view.bringSubviewToFront(shieldView)
            
            NSLayoutConstraint.activate([
                NSLayoutConstraint(item: view, attribute: .leading, relatedBy: .equal, toItem: shieldView, attribute: .leading, multiplier: 1, constant: 0),
                NSLayoutConstraint(item: view, attribute: .trailing, relatedBy: .equal, toItem: shieldView, attribute: .trailing, multiplier: 1, constant: 0),
                NSLayoutConstraint(item: view, attribute: .top, relatedBy: .equal, toItem: shieldView, attribute: .top, multiplier: 1, constant: 0),
                NSLayoutConstraint(item: view, attribute: .bottom, relatedBy: .equal, toItem: shieldView, attribute: .bottom, multiplier: 1, constant: 0)
            ])
            
            isShowingTransitionShieldView = true
            
            self.dismiss(animated: true, completion: {
                self.displayMode = preferredMode
                self.updatePinButtonItems()
                
                shieldView.removeFromSuperview()
                self.isShowingTransitionShieldView = false
                
                // Need a turn of the run loop to get the shield view out of there. Otherwise, the appearance animation gets wonky.
                DispatchQueue.main.asyncAfter(deadline: DispatchTime.now()+0.1, execute: {
                    // Recursively presents previously presented view controllers
                    func representPresentations(on controller: UIViewController, completion: @escaping ()->Void) {
                        guard let presentationAndItem = presentedControllerQueue.popLast() else { completion(); return }
                        if presentationAndItem.controller.modalPresentationStyle == .popover {
                            let popoverPresentationController = presentationAndItem.controller.popoverPresentationController
                            if let presentingBarButtonItem = presentationAndItem.item {
                                popoverPresentationController?.barButtonItem = self.navigationDelegate?.barButtonItemForRetargetingPopoverOnTransitionToMultiMode?(presentationAndItem.controller, presentingOn: controller, originalSourceBarButtonItem: presentingBarButtonItem) ?? presentingBarButtonItem
                            } else {
                                assertionFailure("We need to add an additional delegate method similar to barButtonItemForRetargetingPopoverOnTransitionToMultiMode for the source view and rect case")
                                popoverPresentationController?.sourceView = self.view
                                popoverPresentationController?.sourceRect = CGRect.zero
                            }
                        }
                        
                        controller.present(presentationAndItem.controller, animated: false) {
                            representPresentations(on: presentationAndItem.controller, completion: completion)
                        }
                    }
                    
                    let completion = {
                        representPresentations(on: self.viewController(atLocation: pane.location)!) {
                            savedFirstResponder?.becomeFirstResponder()
                        }
                    }
                    if !pane.isVisible {
                        self.showPane(at: pane.location, animated: false, completion: completion)
                    } else {
                        completion()
                    }                    
                })
            })
        } else {
            displayMode = preferredMode
            updatePinButtonItems()
        }
    }
    
    // update the panes with the given size, setting the proper pane.displayStyle and preparing embedded panes for layout
    // Called when the MPC displayMode changes.
    fileprivate func preparePanesForLayout(toMode mode: MultiPaneDisplayMode, withSize size: CGSize) {
        // capture our visibility state for the sidebars prior to teardown.
        var leftIsVisible = false
        var rightIsVisible = false
        var paneLocationToPin: MultiPaneLocation? = nil
        var paneLocationToUnpin: MultiPaneLocation? = nil
        
        UIView.performWithoutAnimation {
            orderedPanes.forEach { (pane) in
                #if DEBUG_kc
                print("DEBUG: pane \(pane.location) presentationMode=\(pane.presentationMode) and MultiPaneDisplayMode \(mode)")
                #endif

                switch pane.location {
                case .left:
                    leftIsVisible = pane.environment?.presentationMode == .embedded
                case .right:
                    rightIsVisible = pane.environment?.presentationMode == .embedded
                case .center:
                    break
                }

                // Make a pass and update all panes based on the default environment, we adjust for pinning below
                pane.environment = environment(for: pane, displayMode: mode, size: size)
                
                // Now that we're conditionally removing panes based on their presentationMode, we need to wait until we've adjusted that from the default, which we do below. Pane removal has been moved down to before the layout call.
            }
        }

        if displayMode == .multi {

            let left = self.pane(withLocation: .left)
            let center = self.pane(withLocation: .center)
            let right = pane(withLocation: .right)

            if left?.environment?.presentationMode == .embedded && (layoutDelegate?.wantsUnpinnedPane?(at: .left, multiPaneController: self) ?? false) {
                left?.environment = RegularEnvironment(withPresentationMode: .overlaid, containerSize: size)
            }
            if right?.environment?.presentationMode == .embedded && (layoutDelegate?.wantsUnpinnedPane?(at: .right, multiPaneController: self) ?? false) {
                right?.environment = RegularEnvironment(withPresentationMode: .overlaid, containerSize: size)
            }

            if widthOfPanes > size.width && self.pinningLayoutPass == false {
                #if DEBUG_kc
                print("DEBUG: widthOfPanes \(widthOfPanes) > size.width \(size.width)")
                #endif

                let locationToBecomeOverlay = layoutDelegate?.locationToBecomeOverlay?(displayMode: mode, multiPaneController: self, viewSize: size) ?? .left
                let pane = self.pane(withLocation: locationToBecomeOverlay)
                pane?.environment = RegularEnvironment(withPresentationMode: .overlaid, containerSize: size)
            }
            
            // adjust for pinning changes.
            if self.pinningLayoutPass {
                let centerWidth = center?.centerPanePinWidthThreshold ?? size.width

                if let pinRequest = self.pinRequest {
                    switch pinRequest {
                    case .pin(let pane):
                        // Check if pinning this pane would cause our center width pin threshold to be exceeded. 
                        // dismiss that pane.
                        if (size.width - self.widthOfSidebars) < centerWidth {
                            if let oppositePane = pane.location == .left ? right : left {
                                oppositePane.environment = RegularEnvironment(withPresentationMode: .overlaid, containerSize: size)
                                oppositePane.configuration.isPinned = false
                                paneLocationToUnpin = oppositePane.location
                            }
                        }
                        
                        // we want to pin this pane, so embedded it.
                        pane.environment = RegularEnvironment(withPresentationMode: .embedded, containerSize: size)
                        paneLocationToPin = pane.location

                        if pane.location == .left {
                            leftIsVisible = true
                        }
                        
                        if pane.location == .right {
                            rightIsVisible = true
                        }

                        pane.configuration.isPinned = true
                        
                    case .unpin(let pane):
                        pane.environment = RegularEnvironment(withPresentationMode: .overlaid, containerSize: size)
                        paneLocationToUnpin = pane.location
                        pane.configuration.isPinned = false
                    }
                }
            }
            
            // Try to restore the last visibility state. This can be overriden later with the layout delegate.
            left?.visibleWhenEmbedded = leftIsVisible
            right?.visibleWhenEmbedded = rightIsVisible
        }
        
        UIView.performWithoutAnimation {
            for pane in orderedPanes {
                if pane.presentationMode != .embedded {
                    removePane(pane: pane)
                }
            }
        }
        NSLayoutConstraint.deactivate(layoutConstraints)
        layoutConstraints = []
        
        notifyDelegateWillUnpin(location: paneLocationToUnpin)
        notifyDelegateWillPin(location: paneLocationToPin)
        
        layout(panes: orderedPanes.filter { $0.presentationMode == MultiPanePresentationMode.embedded })
        
        notifyDelegateDidUnpin(location: paneLocationToUnpin)
        notifyDelegateDidPin(location: paneLocationToPin)

        updatePinButtonItems()

        self.pinningLayoutPass = false
        self.pinRequest = nil
    }
    
    /// Only notifies the delegate if location is non-nil.
    private func notifyDelegateWillUnpin(location: MultiPaneLocation?) {
        guard let location = location else { return }
        layoutDelegate?.willUnpinPane?(at: location, multiPaneController: self)
    }
    /// Only notifies the delegate if location is non-nil.
    private func notifyDelegateWillPin(location: MultiPaneLocation?) {
        guard let location = location else { return }
        layoutDelegate?.willPinPane?(at: location, multiPaneController: self)
    }
    /// Only notifies the delegate if location is non-nil.
    private func notifyDelegateDidUnpin(location: MultiPaneLocation?) {
        guard let location = location else { return }
        layoutDelegate?.didUnpinPane?(at: location, multiPaneController: self)
    }
    /// Only notifies the delegate if location is non-nil.
    private func notifyDelegateDidPin(location: MultiPaneLocation?) {
        guard let location = location else { return }
        layoutDelegate?.didPinPane?(at: location, multiPaneController: self)
    }
 
 
    // add the layout constraints, ordered L->R array for the embedded panes.
    private func layout(panes: [Pane]) {
 
        var layoutPanes = [Pane]()
        panes.forEach { (pane) in
            if pane.presentationMode == MultiPanePresentationMode.embedded {
                insertPane(pane: pane)
                layoutPanes.append(pane)
                pane.prepareForDisplay()
                
                if displayMode == .compact {
                    pane.visibleWhenEmbedded = true
                } else {
                    if let pinRequest = pinRequest, case let .pin(associatedPane) = pinRequest, associatedPane == pane {
                        return // Return out of this iteration of the `forEach`; this would normally be a `continue`
                    }

                    // only used in non-compact environments.
                    if let showPaneOverride = self.layoutDelegate?.shouldShowPane?(at: pane.location, multiPaneController: self) {
                        pane.visibleWhenEmbedded = showPaneOverride
                        if pane.configuration.canBePinned {
                            pane.configuration.isPinned = true
                        }
                    }
                }
                
            }
        }
        
        panes.forEach { (pane) in
            guard let sidebar = pane.configuration as? Sidebar else { return }
            guard sidebar.wantsDivider else { return }
            guard let divider = sidebar.divider else { return }

            view.bringSubviewToFront(divider)
        }

        NSLayoutConstraint.deactivate(layoutConstraints)
        layoutConstraints = MultiPaneLayout.layout(forPanes: layoutPanes)
        NSLayoutConstraint.activate(layoutConstraints)
        layoutPanes.first?.viewController.view.superview?.setNeedsLayout() // Without this, the superview won't necessarily lay out using the new constraints
    }
    
    private func environment(for pane: Pane, displayMode: MultiPaneDisplayMode, size: CGSize) -> PaneEnvironment {
        switch displayMode {
        case .compact:
            let style: MultiPaneCompactTransitionStyle = navigationDelegate?.compactTransitioningStyle?(for: pane.location) ?? .modal
            
            var presentationMode: MultiPanePresentationMode = .none
            if style == .navigation {
                let visiblePane = visibleCompactPane
                presentationMode = (visiblePane == pane.location ? .embedded : .none)
            } else {
                presentationMode = (pane.location == .center ? .embedded : .none)
            }
            
            var env: CompactEnvironment = CompactEnvironment(withPresentationMode: presentationMode, containerSize: size)
            env.transitionStyle = style
            return env
            
        case .single:
            let mode: MultiPanePresentationMode = (pane.configuration is Sidebar) ? .overlaid : .embedded
            return RegularEnvironment(withPresentationMode: mode, containerSize: size)
            
        case .multi:
            return RegularEnvironment(withPresentationMode: .embedded, containerSize: size)
        }
    }

    private func updateDisplayButtonItems(forMode displayMode: MultiPaneDisplayMode) {
        // sidebar representation
        let image = UIImage(systemName: "sidebar.left") ?? UIImage(named: "OUIMultiPaneLeftSidebarButton", in: OmniUIBundle, compatibleWith: traitCollection)
        leftPaneDisplayButton.image = image
        leftPaneDisplayButton.title = nil
        layoutDelegate?.didUpdateDisplayButtonItems?(self)
    }
    
    private func updatePinButtonItems() {
        leftPanePinButton.image = UIImage(multiPanePinButtonPinnedState: pane(withLocation: .left)?.isPinned ?? false)
        rightPanePinButton.image = UIImage(multiPanePinButtonPinnedState: pane(withLocation: .right)?.isPinned ?? false)
    }
    
    private func setupDividerIfNeeded(onPane pane: Pane) {
        guard let sidebar = pane.configuration as? Sidebar else { return }
        guard sidebar.wantsDivider else { return }
        guard sidebar.divider == nil else { return }
        
        var mutableSidebar = sidebar
        let divider = PaneDividerView()
       
        view.addSubview(divider) // install the divider on the MPC so that we don't get clipped by other views.
        divider.translatesAutoresizingMaskIntoConstraints = false
        mutableSidebar.divider = divider
        
        if sidebar.wantsMoveableDivider {
            sidebar.divider!.editStateChanged = { [weak self] (dividerState) in
                guard self != nil else { return }
                switch dividerState {
                case .Started:
                    let overlayView = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
                    overlayView.frame = self!.view.bounds
                    overlayView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                    overlayView.tag = 20
                    overlayView.alpha = 0.20
                    self!.view.insertSubview(overlayView, belowSubview: divider)
                    
                case .Changed(let xOffset):
                    let left = self!.pane(withLocation: .left)!
                    
                     let width = left.width + xOffset
                     left.preferredWidth = width

                case .Ended:
                    // cleanup the overlay view.
                    if let view = self!.view.viewWithTag(20) {
                        view.removeFromSuperview()
                    }
                }
            }
            
        }
        
        pane.configuration = mutableSidebar
    }
    
}

// MARK: - Extensions and helpers.

extension MultiPaneController: MultiPanePresenterDelegate {
    func handlePinning(presenter: MultiPanePresenter, sender: AnyObject?) {
        guard let pinButton = sender as? UIBarButtonItem else {
            assertionFailure("expected the pin button to be a UIBarButtonItem")
            return
        }
        
        var pane: Pane? = nil
        if presenter.leftPinButton == pinButton {
            // left pin
            pane = self.pane(withLocation: .left)
        } else if presenter.rightPinButton == pinButton {
            pane = self.pane(withLocation: .right)
        }
        
        guard let pinningPane = pane else {
            // Couldn't find a pane to pin
            return
        }
        
        if pinningPane.wantsToBePinnable {
            let env = pinningPane.environment
            if env?.presentationMode == .overlaid {
                self.presenterWantsToPin(pane: pinningPane)
            } else {
                self.presenterWantsToUnpin(pane: pinningPane)
            }
        }
    }
    
    @objc /**REVIEW**/ func presenterWantsToPin(pane: Pane) {
        self.pinningLayoutPass = true
        self.pinRequest = .pin(pane)
        self.pinButton(forPaneAt: pane.location).image = UIImage(multiPanePinButtonPinnedState: true)
        multiPanePresenter.dismiss(fromViewController: self, animated: false, completion: { [weak self] in
            // we update the displaymode after the presenter has dismissed, otherwise we will get crazy drawing issues.
            self?.displayMode = .multi
        })
    }
    
    @objc /**REVIEW**/ func presenterWantsToUnpin(pane: Pane) {
        // the presenter can't pass us the pinned pane, so we need to try to find it for ourseleves.
        self.pinningLayoutPass = true
        self.pinRequest = .unpin(pane)
        self.pinButton(forPaneAt: pane.location).image = UIImage(multiPanePinButtonPinnedState: false)
        self.multiPanePresenter.addSnapshot(to: self.view!, for: pane)
        self.updateDisplayMode(forSize: self.currentSize, traitCollection: self.traitCollection)
    
        DispatchQueue.main.async {
            // For this case we need to manually push appearance transistions so pane's view controller lays out correctly.
            pane.viewController.beginAppearanceTransition(true, animated: false)
            self.multiPanePresenter.present(pane: pane, fromViewController: self, usingDisplayMode: self.displayMode, animated: false)
            pane.viewController.endAppearanceTransition()
        }
    }
    
    private func reassignFirstResponderIfNeededAfterHidingPane(at location: MultiPaneLocation) {
        guard displayMode != .compact else { return }
        guard isViewLoaded else { return }
        let disappearingViewController: UIViewController
        
        switch location {
        case .right, .left:
            guard let vc = viewController(atLocation: location) else { return }
            disappearingViewController = vc
            
        case .center:
            assertionFailure("Why is the center pane being hidden in a non-compact environment?")
            return
        }
        
        guard let firstResponder = UIResponder.firstResponder else { return }
        guard firstResponder.isInActiveResponderChain(preceding: disappearingViewController) else { return }
        
        if let firstResponder = firstResponder as? UIView {
            firstResponder.endEditing(true)
        }
        
        // When hiding either the left or the right pane, but keyboard focus center view, if possible.
        // Otherwise we'll just have to move it to the multipane controller.
        
        var candidateFirstResponder: UIResponder? = nil
        
        if let centerViewController = viewController(atLocation: .center) {
            if let navigationController = centerViewController as? UINavigationController, let topView = navigationController.topViewController?.viewIfLoaded {
                candidateFirstResponder = topView
            } else if let centerView = centerViewController.viewIfLoaded {
                candidateFirstResponder = centerView
            } else {
                candidateFirstResponder = viewIfLoaded
            }
        } else {
            candidateFirstResponder = viewIfLoaded ?? self
        }
        
        while let possibleFirstResponder = candidateFirstResponder {
            if possibleFirstResponder.canBecomeFirstResponder {
                possibleFirstResponder.becomeFirstResponder()
                return
            }
            
            candidateFirstResponder = possibleFirstResponder.next
        }
        
        assertionFailure("Didn't find a new candidate first responder.")
    }
    
    func willPerform(operation: MultiPanePresenterOperation, withPane pane: Pane) {
       
        switch operation {
        case .push, .pop:
            visibleCompactPane = pane.location
            sendWillNavigateToPaneNotification(pane: visibleCompactPane)
            
        case .overlay:
            layoutDelegate?.willShowPane?(at: pane.location, multiPaneController: self)
            // TODO: decide if we want a shadow on an overlaid controller.
            if pane.location == .left || pane.location == .right {
                pane.apply(decorations: [AddShadow()])
            }
            
        case .dismiss:
            layoutDelegate?.willHidePane?(at: pane.location, multiPaneController: self)

        case .expand:
            layoutDelegate?.willShowPane?(at: pane.location, multiPaneController: self)
            NotificationCenter.default.post(name: .OUIMultiPaneControllerWillShowPane, object: self, userInfo: [OUIMultiPaneControllerPaneLocationUserInfoKey : pane.location.rawValue])
            
            
            if pane.location == .left || pane.location == .right {
                pane.apply(decorations: [ShowDivider()])
            }

        case .collapse:
            layoutDelegate?.willHidePane?(at: pane.location, multiPaneController: self)
            NotificationCenter.default.post(name: .OUIMultiPaneControllerWillHidePane, object: self, userInfo: [OUIMultiPaneControllerPaneLocationUserInfoKey : pane.location.rawValue])
            
            // If the delegate hasn't ensured that the first responder is somewhere reasonable (not in a chain that includes the view controller that was just hidden), put it someplace reasonble by default.
            reassignFirstResponderIfNeededAfterHidingPane(at: pane.location)
            
        default:
            break
        }
    }
    
    func didPerform(operation: MultiPanePresenterOperation, withPane pane: Pane) {
        switch operation {
        case .push, .pop:
            // catch the interactive cancel case and update correctly.
            if visibleCompactPane != pane.location {
                visibleCompactPane = pane.location
                sendWillNavigateToPaneNotification(pane: visibleCompactPane)
            } else {
                sendDidNavigateToPaneNotification(pane: visibleCompactPane)
            }

            // re-run our layout so that the panes and the layout are lined up.
            preparePanesForLayout(toMode: displayMode, withSize: currentSize)

        case .overlay:
            layoutDelegate?.didShowPane?(at: pane.location, multiPaneController: self)
            
        case .dismiss:
            layoutDelegate?.didHidePane?(at: pane.location, multiPaneController: self)
            
        case .collapse:
            if pane.location == .left || pane.location == .right {
               pane.apply(decorations: [HideDivider()])
            }
            layoutDelegate?.didHidePane?(at: pane.location, multiPaneController: self)
            NotificationCenter.default.post(name: .OUIMultiPaneControllerDidHidePane, object: self, userInfo: [OUIMultiPaneControllerPaneLocationUserInfoKey : pane.location.rawValue])

        case .expand:
            layoutDelegate?.didShowPane?(at: pane.location, multiPaneController: self)
            NotificationCenter.default.post(name: .OUIMultiPaneControllerDidShowPane, object: self, userInfo: [OUIMultiPaneControllerPaneLocationUserInfoKey : pane.location.rawValue])
        
        default:
            break
        }
    }
    
    // <bug:///157931> (iOS-OmniFocus Engineering: Method argument cleanup in MultiPaneController) - pane never used
    private func sendWillNavigateToPaneNotification(pane: MultiPaneLocation) {
        navigationDelegate?.willNavigate?(toPane: visibleCompactPane, with: self)
        NotificationCenter.default.post(name: .OUIMultiPaneControllerWillNavigateToPane, object: self, userInfo: [OUIMultiPaneControllerPaneLocationUserInfoKey : visibleCompactPane.rawValue])
    }

    // <bug:///157931> (iOS-OmniFocus Engineering: Method argument cleanup in MultiPaneController) - pane never used
    private func sendDidNavigateToPaneNotification(pane: MultiPaneLocation) {
        navigationDelegate?.didNavigate?(toPane: visibleCompactPane, with: self)
        NotificationCenter.default.post(name: .OUIMultiPaneControllerDidNavigateToPane, object: self, userInfo: [OUIMultiPaneControllerPaneLocationUserInfoKey : visibleCompactPane.rawValue])
    }

    func willPresent(viewController: UIViewController) {
        navigationDelegate?.willPresent?(viewController: viewController)
        guard let pane = pane(forViewController: viewController) else { return }
        NotificationCenter.default.post(name: .OUIMultiPaneControllerWillPresentPane, object: self, userInfo: [OUIMultiPaneControllerPaneLocationUserInfoKey : pane.location.rawValue])
    }
    
    func navigationAnimationController(for operation: UINavigationController.Operation, animatingTo toVC: UIViewController, from fromVC: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        return navigationDelegate?.navigationAnimationController?(for: operation, animating:toVC, fromViewController: fromVC, multiPaneController: self)
    }
    
    func animationsToPerformAlongsideEmbeddedSidebarHiding(atLocation: MultiPaneLocation, withWidth: CGFloat) -> (() -> Void)? {
        return navigationDelegate?.animationsToPerformAlongsideEmbeddedSidebarHiding?(atLocation: atLocation, withWidth: withWidth)
    }
    
    func animationsToPerformAlongsideEmbeddedSidebarShowing(atLocation: MultiPaneLocation, withWidth: CGFloat) -> (() -> Void)? {
        return navigationDelegate?.animationsToPerformAlongsideEmbeddedSidebarShowing?(atLocation: atLocation, withWidth: withWidth)
    }
}

typealias MultiPaneControllerPaneVisibility = MultiPaneController
extension MultiPaneControllerPaneVisibility {
    @objc public func paneIsVisible(at location: MultiPaneLocation) -> Bool {
        return pane(withLocation: location)?.isVisible ?? false
    }
    @objc public func paneIsOverlaid(at location: MultiPaneLocation) -> Bool {
        if (self.paneIsVisible(at: location) == false) {
            return false;
        }
        guard let pane = pane(withLocation: location) else { return false }

        if (pane.presentationMode == MultiPanePresentationMode.overlaid) {
            return true
        } else {
            return false
        }
    }
    @objc public func paneIsVisibleAndNonEmbedded(at location: MultiPaneLocation) -> Bool {
        if (self.paneIsVisible(at: location) == false) {
            return false
        }
        guard let pane = pane(withLocation: location) else { return false }
        return (pane.presentationMode != .embedded)
    }
}

typealias MultiPaneControllerSidebarPresentation = MultiPaneController
extension MultiPaneControllerSidebarPresentation {
    //MARK: - Actions
    @objc internal func handleLeftPaneDisplayButton(sender: AnyObject?) {
        toggleLeftPane()
    }
    
    @objc internal func handleRightPaneDisplayButton(sender: AnyObject?) {
        toggleRightPane()
    }
    
    @objc internal func handleScreenEdgePanGesture(gesture: UIScreenEdgePanGestureRecognizer) {
        guard gesture.state == .began else {
            if gesture.state == .ended || gesture.state == .cancelled {
                if gesture.edges.contains(.left) {
                    navigationDelegate?.userDidEndInteractiveGesturePresentation?(at: .left, multiPaneController: self)
                }
                if gesture.edges.contains(.right) {
                    navigationDelegate?.userDidEndInteractiveGesturePresentation?(at: .right, multiPaneController: self)
                }
            }
            return
        }
        
        if gesture.edges == .left {
            guard let leftPane = pane(withLocation: .left) else { return }
            navigationDelegate?.userWillBeginInteractiveGesturePresentation?(at: .left, multiPaneController: self)
            multiPanePresenter.present(pane: leftPane, fromViewController: self, usingDisplayMode: displayMode, interactivelyWith: gesture)
        } else if gesture.edges == .right {
            // ignore this gesture when we are in compact since it is not a configuration the MultiPanePresenter supports.
            guard displayMode != .compact else { return }
            guard let rightPane = pane(withLocation: .right) else { return }
            navigationDelegate?.userWillBeginInteractiveGesturePresentation?(at: .right, multiPaneController: self)
            multiPanePresenter.present(pane: rightPane, fromViewController: self, usingDisplayMode: displayMode, interactivelyWith: gesture)
        } else {
            assertionFailure("unexpected screen edge pan gesture direction \(gesture.edges)")
        }
    }
}

extension MultiPaneController: UIGestureRecognizerDelegate {
    
    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer == self.leftEdgePanGesture {
            return self.pane(withLocation: .left) != nil
        }
        
        return true
    }
    
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer == leftEdgePanGesture else { return false }
        
        // <bug:///157076> (iOS-OmniFocus Crasher: Compact: Crash swiping to navigate (No occurrence for index path (null)' | -[UISwipeActionController swipeHandlerDidBeginSwipe:] + 280))
        // The left edge pan gesture recognizer will start to take the center pane out of the view — but if that view is a UITableView, and there's a swipe action on the row under the panning touch, UIKit may try to begin that swipe as well and fail an assertion. Suppress UITableView gestures when handling left edge pans to avoid the resultant crash.
        if otherGestureRecognizer.view is UITableView {
            return false
        }
        
        return true
    }
}

/// Represents the the displayMode and size of the MPC to the managed view controllers of each Pane.
public final class MultiPaneConfiguration: NSObject {
    @objc /**REVIEW**/ public let displayMode: MultiPaneDisplayMode
    @objc /**REVIEW**/ public let currentSize: CGSize
    
    @objc /**REVIEW**/ init(displayMode: MultiPaneDisplayMode, size: CGSize) {
        self.displayMode = displayMode
        currentSize = size
    }
}

// Wraps up what pinning state to apply to a given pane.
fileprivate enum PinRequest {
    case pin(Pane)
    case unpin(Pane)
}

/// convenience helpers for the MPC
extension Pane {
    @objc /**REVIEW**/ var location: MultiPaneLocation {
        return configuration.location
    }
    
    var isBeingDismissed: Bool {
        return viewController.furthestAncestor.isBeingDismissed
    }
    
    @objc /**REVIEW**/ var isVisible: Bool {
        if let wrapper = viewController.parent as? MultipanePresentationWrapperViewController {
            return wrapper.isVisible
        } else {
            return viewController.isVisible
        }
    }
    
    var presentationMode: MultiPanePresentationMode {
        return environment?.presentationMode ?? .none
    }
}
