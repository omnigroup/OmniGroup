// Copyright 2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

@objc(OAScrollingCardView)
open class ScrollingCardView: CardView {
    override open class var defaultEdgeInsets: NSEdgeInsets {
        // N.B. Leave enough room for the shadow blur radius
        return NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
    }

    override public init(frame: NSRect) {
        super.init(frame: frame)
        commonInit()
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    // MARK: Appearance
    
    override public var cornerRadius: CGFloat {
        didSet {
            scrollView?.cornerRadius = cornerRadius
        }
    }
    
    /// ScrollingCardView takes over the content insets so that the scrollview can be positioned appropriately.
    override public var contentInsets: NSEdgeInsets {
        get {
            return super.contentInsets
        }
        set {
            assert(NSEdgeInsetsEqual(newValue, NSEdgeInsetsZero))
            super.contentInsets = newValue
        }
    }
    
    /// The inset between the scroll view and the scrolling content view. If unset, automatically computed from the corner radius.
    @objc public var scrollingContentInsets: NSEdgeInsets {
        get {
            if let scrollingContentInsets = _scrollingContentInsets {
                return scrollingContentInsets
            } else {
                let horizontalInset = cornerRadius
                let verticalInset = (cornerRadius / 2.0).rounded(.up)
                return NSEdgeInsets(top: verticalInset, left: horizontalInset, bottom: verticalInset, right: horizontalInset)
            }
        }
        set {
            _scrollingContentInsets = newValue
            needsUpdateConstraints = true
        }
    }

    // MARK: Content View

    /// ScrollingCardView owns the superclass's content view.
    /// Clients of ScrollingCardView should instead set `scrollingContentView` instead.
    override public var contentView: NSView? {
        willSet {
            assert(newValue is NSScrollView && contentView == nil)
        }
    }
    
    /// The scrolling content view is expected to be width flexible, and to provide its height via layout constraints.
    public var scrollingContentView: NSView? {
        willSet {
            scrollingContentView?.removeFromSuperview()
            documentViewWidthConstraint?.isActive = false
            documentViewWidthConstraint = nil
        }
        didSet {
            if let scrollingContentView = scrollingContentView {
                let documentView = CardScrollViewDocumentView(contentView: scrollingContentView, contentInsets: scrollingContentInsets)
                documentView.translatesAutoresizingMaskIntoConstraints = false
                scrollView.documentView = documentView
                
                // The document view should track the width of the scroll view (minus any required space for the scrollers.)
                let documentViewWidthConstraint = documentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor, multiplier: 1.0)
                documentViewWidthConstraint.isActive = true
                self.documentViewWidthConstraint = documentViewWidthConstraint
            }
        }
    }
    
    /// The floating footer view is expected to be width flexible, and to provide its height via layout constraints.
    public var footerView: NSView? {
        willSet {
            footerView?.removeFromSuperview()
        }
        didSet {
            if let footerView = footerView {
                footerView.translatesAutoresizingMaskIntoConstraints = false
                scrollView.addFloatingSubview(footerView, for: .vertical)
                
                if let containerView = footerView.superview {
                    let constraints: [NSLayoutConstraint] = [
                        footerView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
                        footerView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
                        footerView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
                    ]
                    
                    NSLayoutConstraint.activate(constraints)
                }

                footerViewHeight = footerView.fittingSize.height
            } else {
                footerViewHeight = 0
            }
            
            needsUpdateConstraints = true
        }
    }
    
    public var insetsScrollersForFooterView = false {
        didSet {
            needsUpdateConstraints = true
        }
    }
    
    public func flashScrollers() {
        scrollView.flashScrollers()
    }
    
    // MARK: NSView Subclass
    
    open override func updateConstraints() {
        super.updateConstraints()
        
        // This is done here, instead of the setter, so that the content insets are also updated reactively to corner radius changes.
        if let documentView = scrollView.documentView as? CardScrollViewDocumentView {
            documentView.contentInsets = scrollingContentInsets
            documentView.footerViewHeight = footerViewHeight
        }
        
        if insetsScrollersForFooterView {
            scrollView.scrollerInsets = NSEdgeInsetsMake(0, 0, footerViewHeight, 0)
        } else {
            scrollView.scrollerInsets = NSEdgeInsetsZero
        }
    }
    
    // MARK: Layout Hooks

    fileprivate func scrollViewDidTile() {
        // Update the document view's width
        let scrollerWidth: CGFloat
        let contentHeight = scrollView.documentView?.frame.height ?? 0
        if scrollView.scrollerStyle == .overlay || contentHeight < scrollView.frame.height {
            scrollerWidth = 0
        } else {
            scrollerWidth = scrollView.verticalScroller?.frame.width ?? 16
        }
        
        documentViewWidthConstraint?.constant = -scrollerWidth
        
        updateScrollability()
    }

    // MARK: Private
    
    private func updateScrollability() {
        // Update vertical elasticity
        let contentHeight = scrollView.documentView?.frame.height ?? 0
        // The document view already includes the footer view's height via its contentViewBottomConstraint
        if contentHeight > frame.height {
            scrollView.verticalScrollElasticity = .automatic
            scrollView.canScroll = true
        } else {
            scrollView.verticalScrollElasticity = .none
            // We've determined that we have enough room in our scroll view to display all of our content without scrolling. But, without this, we hit <bug:///175242>, which looks like it's roughly a 16 point math discrepency. Potentially because of the hidden horizontal scroller?
            scrollView.canScroll = false
        }
    }
    
    private var scrollView: CardScrollView!
    private var documentViewWidthConstraint: NSLayoutConstraint? = nil
    private var footerViewHeight: CGFloat = 0 {
        didSet {
            needsUpdateConstraints = true
        }
    }

    private var _scrollingContentInsets: NSEdgeInsets? = nil

    private func commonInit() {
        contentInsets = NSEdgeInsetsZero

        // Use an arbitrary non-zero frame so that the initial constraints system passes
        let initialFrame = NSRect(x: 0, y: 0, width: 640, height: 480)
        
        scrollView = CardScrollView(frame: initialFrame)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.cornerRadius = cornerRadius
        
        contentView = scrollView
    }
}

// MARK: -

private class CardScrollView: NSScrollView {
    var canScroll: Bool = true {
        didSet {
            hasVerticalScroller = canScroll
        }
    }
    
    override init(frame: NSRect) {
        super.init(frame: frame)
        commonInit()
    }
    
    required init?(coder: NSCoder) {
        fatalError("\(#function) is not implemented.")
    }
    
    var cornerRadius: CGFloat = 0 {
        didSet {
            layer?.cornerRadius = cornerRadius
            needsLayout = true
        }
    }

    override func tile() {
        super.tile()

        if let scrollingCardView = enclosingView(of: ScrollingCardView.self) {
            scrollingCardView.scrollViewDidTile()
        }

        if let verticalScroller = verticalScroller {
            verticalScroller.wantsLayer = true
            verticalScroller.layer?.cornerRadius = cornerRadius
            verticalScroller.layer?.maskedCorners = [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
        }
    }
    
    override func scrollWheel(with event: NSEvent) {
        if canScroll {
            super.scrollWheel(with: event)
        } else {
            nextResponder?.scrollWheel(with: event)
        }
    }
    
    // MARK: Private

    private func commonInit() {
        wantsLayer = true

        contentView = CardScrollViewClipView(frame: .zero)
        
        automaticallyAdjustsContentInsets = false
        
        drawsBackground = false
        autohidesScrollers = true
        
        hasVerticalScroller = true
        hasHorizontalScroller = false
        
        verticalScrollElasticity = .automatic
        horizontalScrollElasticity = .none
        
        lineScroll = 32
    }
}

// MARK: -

private class CardScrollViewClipView: NSClipView {
    override var isFlipped: Bool {
        return true
    }
}

// MARK: -

private class CardScrollViewDocumentView: NSView {
    init(contentView: NSView, contentInsets: NSEdgeInsets = NSEdgeInsetsZero) {
        self.contentView = contentView
        self.contentInsets = contentInsets

        // Use some arbitrary non-zero initial size to avoid constraint violations
        super.init(frame: NSRect(x: 0, y: 0, width: 200, height: 200))

        contentView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentView)

        contentViewLeadingConstraint = contentView.leadingAnchor.constraint(equalTo: leadingAnchor)
        contentViewTrailingConstraint = contentView.trailingAnchor.constraint(equalTo: trailingAnchor)
        
        contentViewTopConstraint = contentView.topAnchor.constraint(equalTo: topAnchor)
        contentViewBottomConstraint = contentView.bottomAnchor.constraint(equalTo: bottomAnchor)
        
        let constraints: [NSLayoutConstraint] = [
            contentViewLeadingConstraint,
            contentViewTrailingConstraint,
            
            contentViewTopConstraint,
            contentViewBottomConstraint,
        ]
        
        NSLayoutConstraint.activate(constraints)
    }
    
    required init?(coder decoder: NSCoder) {
        fatalError("\(#function) has not been implemented.")
    }
    
    private(set) var contentView: NSView

    var contentInsets: NSEdgeInsets {
        didSet {
            needsUpdateConstraints = true
        }
    }
    
    var footerViewHeight: CGFloat = 0 {
        didSet {
            needsUpdateConstraints = true
        }
    }

    open override func updateConstraints() {
        super.updateConstraints()
        
        contentViewLeadingConstraint.constant = contentInsets.left
        contentViewTrailingConstraint.constant = -1 * contentInsets.right
        
        contentViewTopConstraint.constant = contentInsets.top
        contentViewBottomConstraint.constant = -1 * (contentInsets.bottom + footerViewHeight)
    }

    private var contentViewLeadingConstraint: NSLayoutConstraint!
    private var contentViewTrailingConstraint: NSLayoutConstraint!
    
    private var contentViewTopConstraint: NSLayoutConstraint!
    private var contentViewBottomConstraint: NSLayoutConstraint!
}
