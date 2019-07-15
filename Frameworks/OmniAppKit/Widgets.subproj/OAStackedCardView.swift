// Copyright 2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

@objc(OAStackedCardView)
open class StackedCardView: CardView {
    public override init(frame: NSRect) {
        super.init(frame: frame)
        commonInit()
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    // MARK: Content Views
    
    /// StackedCardView owns the superclass's content view.
    /// Clients of StackedCardView should instead set `contentViews` instead.
    override public var contentView: NSView? {
        willSet {
            assert(newValue is NSStackView && contentView == nil)
        }
    }
    
    // MARK: Appearance
    
    public var contentViews: [NSView] = [] {
        didSet {
            needsReconfigureViews = true
            reconfigureViewsIfNeeded()
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
        reconfigureViewsIfNeeded()
        stackView.setCustomSpacing(spacing, after: contentView)
    }
    
    /// The floating footer view is expected to be width flexible, and to provide its height via layout constraints.
    public var footerView: NSView? {
        didSet {
            needsReconfigureViews = true
        }
    }
    
    // MARK: NSView Subclass
    
    open override func updateConstraints() {
        super.updateConstraints()
        reconfigureViewsIfNeeded()
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
        
        contentView = stackView
    }

    private var needsReconfigureViews = false {
        didSet {
            if needsReconfigureViews {
                needsUpdateConstraints = true
                needsLayout = true
            }
        }
    }
    
    private func reconfigureViewsIfNeeded() {
        guard needsReconfigureViews else { return }
        needsReconfigureViews = false
        
        var contentViews = self.contentViews
        
        if let footerView = footerView {
            let flexibleSpacerView = NSView(frame: .zero)

            contentViews.append(flexibleSpacerView)
            contentViews.append(footerView)
        }
        
        stackView.removeAllArrangedSubviews()
        for view in contentViews {
            stackView.addArrangedSubview(view)
        }
    }
}
