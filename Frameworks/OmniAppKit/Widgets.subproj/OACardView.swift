// Copyright 2019-2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

@objc(OACardView)
open class CardView: NSView {
    open class var defaultCornerRadius: CGFloat {
        return 10
    }
    
    open class var defaultEdgeInsets: NSEdgeInsets {
        // N.B. Leave enough room for the shadow blur radius
        return NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
    }

    override public init(frame: NSRect) {
        super.init(frame: frame)
        commonInit()
    }
    
    public required init?(coder: NSCoder) {
        // REVIEW: Due to how you need to configure the content view separately from the nib, it isn't terribly useful to use this in a nib right now.
        // You could, however, lay out your nib, and then insert the content view at awakeFromNib time.
        super.init(coder: coder)
        commonInit()
    }
    
    // MARK: Content View
    
    public var contentView: NSView? {
        willSet {
            removeContentView()
        }
        didSet {
            installContentView()
        }
    }
    
    // MARK: Appearance

    @objc open var backgroundColor: NSColor {
        get {
            return backgroundView.backgroundColor
        }
        set {
            backgroundView.backgroundColor = newValue
        }
    }

    @objc public var shadowStyle: CardViewShadowStyle {
        get {
            return backgroundView.shadowStyle
        }
        set {
            backgroundView.shadowStyle = newValue
        }
    }

    @objc public var cornerRadius: CGFloat {
        get {
            return backgroundView.cornerRadius
        }
        set {
            backgroundView.cornerRadius = newValue
        }
    }
    
    /// The insets between the edge of the view and the background view.
    @objc public var edgeInsets: NSEdgeInsets = CardView.defaultEdgeInsets {
        didSet {
            needsUpdateConstraints = true
        }
    }
    
    /// The inset between the background view and the content view. If unset, automatically computed from the corner radius.
    @objc public var contentInsets: NSEdgeInsets {
        get {
            if let contentInset = _contentInsets {
                return contentInset
            } else {
                let inset = (cornerRadius / 2.0).rounded(.up)
                return NSEdgeInsets(top: inset, left: inset, bottom: inset, right: inset)
            }
        }
        set {
            _contentInsets = newValue
            needsUpdateConstraints = true
        }
    }

    // MARK: NSView Subclass
    
    open override func updateConstraints() {
        super.updateConstraints()
        
        // Edge inset
        
        backgroundViewLeadingConstraint.constant = edgeInsets.left
        backgroundViewTrailingConstraint.constant = -1 * edgeInsets.right
        
        backgroundViewTopConstraint.constant = edgeInsets.top
        backgroundViewBottomConstraint.constant = -1 * edgeInsets.bottom

        // Content inset
        
        contentWrapperViewLeadingConstraint.constant = contentInsets.left
        contentWrapperViewTrailingConstraint.constant = -1 * contentInsets.right
        
        contentWrapperViewTopConstraint.constant = contentInsets.top
        contentWrapperViewBottomConstraint.constant = -1 * contentInsets.bottom
    }
    
    // MARK: Private
    
    private var backgroundView: CardBackgroundView!
    
    private var backgroundViewLeadingConstraint: NSLayoutConstraint!
    private var backgroundViewTrailingConstraint: NSLayoutConstraint!
    
    private var backgroundViewTopConstraint: NSLayoutConstraint!
    private var backgroundViewBottomConstraint: NSLayoutConstraint!

    private var contentWrapperView: NSView!
    
    private var contentWrapperViewLeadingConstraint: NSLayoutConstraint!
    private var contentWrapperViewTrailingConstraint: NSLayoutConstraint!
    
    private var contentWrapperViewTopConstraint: NSLayoutConstraint!
    private var contentWrapperViewBottomConstraint: NSLayoutConstraint!

    private var _contentInsets: NSEdgeInsets? = nil

    private func commonInit() {
        installSubviews()
        wantsLayer = true
        
        // Use the dynamic (subclass) defaults rather than local defaults.
        cornerRadius = type(of: self).defaultCornerRadius
        edgeInsets = type(of: self).defaultEdgeInsets
    }
    
    private func installSubviews() {
        precondition(backgroundView == nil)
        precondition(contentWrapperView == nil)

        installBackgroundView()
        installContentWrapperView()
    }
    
    private func installBackgroundView() {
        precondition(backgroundView == nil)

        backgroundView = CardBackgroundView(frame: .zero)
        backgroundView.wantsLayer = true
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(backgroundView)
        
        backgroundViewLeadingConstraint = backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor)
        backgroundViewTrailingConstraint = backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor)
        
        backgroundViewTopConstraint = backgroundView.topAnchor.constraint(equalTo: topAnchor)
        backgroundViewBottomConstraint = backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor)
        
        let constraints: [NSLayoutConstraint] = [
            backgroundViewLeadingConstraint,
            backgroundViewTrailingConstraint,
            
            backgroundViewTopConstraint,
            backgroundViewBottomConstraint,
        ]
        
        NSLayoutConstraint.activate(constraints)
    }

    private func installContentWrapperView() {
        precondition(backgroundView != nil)
        precondition(contentWrapperView == nil)

        contentWrapperView = NSView(frame: .zero)
        contentWrapperView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.addSubview(contentWrapperView)
        
        contentWrapperViewLeadingConstraint = contentWrapperView.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor)
        contentWrapperViewTrailingConstraint = contentWrapperView.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor)
        
        contentWrapperViewTopConstraint = contentWrapperView.topAnchor.constraint(equalTo: backgroundView.topAnchor)
        contentWrapperViewBottomConstraint = contentWrapperView.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor)
        
        let constraints: [NSLayoutConstraint] = [
            contentWrapperViewLeadingConstraint,
            contentWrapperViewTrailingConstraint,
            
            contentWrapperViewTopConstraint,
            contentWrapperViewBottomConstraint,
        ]
        
        NSLayoutConstraint.activate(constraints)
    }
    
    private func installContentView() {
        precondition(contentWrapperView.subviews.isEmpty)
        guard let contentView = contentView else { return }
        
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentWrapperView.addSubview(contentView)
        
        let constraints: [NSLayoutConstraint] = [
            contentView.leadingAnchor.constraint(equalTo: contentWrapperView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: contentWrapperView.trailingAnchor),

            contentView.topAnchor.constraint(equalTo: contentWrapperView.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: contentWrapperView.bottomAnchor),
        ]
        
        NSLayoutConstraint.activate(constraints)
    }
    
    private func removeContentView() {
        guard let contentView = contentView else { return }
        contentView.removeFromSuperview()
    }
}

// MARK: -

@objc(OACardViewShadowStyle)
public enum CardViewShadowStyle: Int {
    case none
    case aqua
    case darkAqua
    case automatic
    
    fileprivate func makeShadow() -> NSShadow? {
        if #available(macOS 10.14, *) {
            if case .darkAqua = self {
                return makeShadow(for: .darkAqua)
            }
        }

        switch self {
        case .aqua:
            return makeShadow(for: .aqua)

        case .automatic:
            if #available(macOS 11, *) {
                return makeShadow(for: NSAppearance.currentDrawing().name)
            } else {
                return makeShadow(for: NSAppearance.current.name)
            }

        default:
            return nil
        }
    }

    private func makeShadow(for appearance: NSAppearance.Name) -> NSShadow? {
        func _shadowColor(for appearance: NSAppearance.Name) -> NSColor? {
            let alphaValue: CGFloat = 0.20
            if case .aqua = appearance {
                return NSColor.black.withAlphaComponent(alphaValue)
            }
            
            if #available(macOS 10.14, *) {
                if case .darkAqua = appearance {
                    return NSColor.white.withAlphaComponent(alphaValue)
                }
            }
            
            return nil
        }
        
        if let shadowColor = _shadowColor(for: appearance) {
            let shadow = NSShadow()

            shadow.shadowOffset = NSSize(width: 0, height: -3)
            shadow.shadowBlurRadius = 3
            shadow.shadowColor = shadowColor

            return shadow
        }
        
        return nil
    }
}

// MARK: -

private class CardBackgroundView: NSView {
    override public init(frame: NSRect) {
        super.init(frame: frame)
        commonInit()
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }
    
    var backgroundColor: NSColor = NSColor.white {
        didSet {
            needsDisplay = true
        }
    }

    public var shadowStyle: CardViewShadowStyle = .none {
        didSet {
            needsDisplay = true
            needsUpdateShadow = true
        }
    }

    var cornerRadius: CGFloat = CardView.defaultCornerRadius {
        didSet {
            needsDisplay = true
            needsUpdateConstraints = true
        }
    }

    // MARK: NSView subclass

    open override var wantsUpdateLayer: Bool {
        return true
    }
    
    open override func updateLayer() {
        super.updateLayer()
        
        precondition(layer != nil)
        if let layer = layer {
            layer.backgroundColor = backgroundColor.cgColor
            layer.cornerRadius = cornerRadius
            
            if needsUpdateShadow {
                needsUpdateShadow = false
                shadow = shadowStyle.makeShadow()
            }
        }
    }
    
    // MARK: Private
    
    private var needsUpdateShadow = false
    
    private func commonInit() {
        wantsLayer = true
    }
}
