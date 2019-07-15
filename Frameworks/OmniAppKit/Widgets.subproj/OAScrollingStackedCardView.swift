// Copyright 2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

@objc(OAScrollingStackedCardView)
open class ScrollingStackedCardView: ScrollingCardView {
    public override init(frame: NSRect) {
        super.init(frame: frame)
        commonInit()
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    // MARK: Content Views
    
    /// ScrollingStackedCardView owns the superclass's content and scrolling content views.
    /// Clients of ScrollingStackedCardView should instead set `contentViews` instead.
    override public var scrollingContentView: NSView? {
        willSet {
            assert(newValue is NSStackView && scrollingContentView == nil)
        }
    }

    public var contentViews: [NSView] = [] {
        didSet {
            stackView.removeAllArrangedSubviews()
            for view in contentViews {
                stackView.addArrangedSubview(view)
            }
        }
    }
    
    @objc public var contentViewSpacing: CGFloat {
        get {
            return stackView.spacing
        }
        set {
            stackView.spacing = newValue
        }
    }
    
    public func customSpacing(after contentView: NSView) -> CGFloat {
        return stackView.customSpacing(after: contentView)
    }
    
    public func setCustomSpacing(_ spacing: CGFloat, after contentView: NSView) {
        stackView.setCustomSpacing(spacing, after: contentView)
    }

    // MARK: Private
    
    private var stackView: NSStackView!
    
    private func commonInit() {
        stackView = NSStackView(views: [])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        
        stackView.orientation = .vertical
        stackView.distribution = .fill
        stackView.spacing = 10
        
        stackView.setHuggingPriority(.required, for: .vertical)

        scrollingContentView = stackView
    }
}
