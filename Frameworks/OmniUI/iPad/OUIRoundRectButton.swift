// Copyright 2018-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

@objc(OUIRoundRectButton)
open class RoundRectButton: UIButton {
    open class var defaultCornerRadius: CGFloat {
        return 10
    }
    
    open class var defaultPadding: UIEdgeInsets {
        let horizontalPadding = min(20, defaultCornerRadius)
        return UIEdgeInsets(top: 0, left: horizontalPadding, bottom: 0, right: horizontalPadding)
    }
    
    // MARK: Instance API
    
    public var cornerRadius: CGFloat {
        didSet {
            mask?.layer.cornerRadius = cornerRadius
        }
    }

    public var padding: UIEdgeInsets {
        didSet {
            invalidateIntrinsicContentSize()
        }
    }

    private var backgroundColorByState: [UInt: UIColor] = [:]
    
    @objc(backgroundColorForState:)
    public func backgroundColor(for state: UIControl.State) -> UIColor? {
        return backgroundColorByState[state.rawValue]
    }
    
    @objc(setBackgroundColor:forState:)
    public func setBackgroundColor(_ color: UIColor?, for state: UIControl.State) {
        backgroundColorByState[state.rawValue] = color
        updateBackgroundColorForCurrentState()
    }
    
    open func updateMaskView() {
        guard cornerRadius > 0 else {
            mask = nil
            return
        }

        mask = UIView(frame: bounds)
        mask?.backgroundColor = UIColor.black
        mask?.layer.cornerRadius = cornerRadius
    }
    
    // MARK: UIButton

    public override init(frame: CGRect) {
        cornerRadius = type(of: self).defaultCornerRadius
        padding = type(of: self).defaultPadding

        super.init(frame: frame)

        updateMaskView()
        setBackgroundColor(UIColor.white, for: .normal)
    }
    
    public required init?(coder: NSCoder) {
        cornerRadius = type(of: self).defaultCornerRadius
        padding = type(of: self).defaultPadding

        super.init(coder: coder)

        updateMaskView()
        setBackgroundColor(self.backgroundColor, for: .normal)

        guard buttonType == .custom else {
            fatalError("\(self) should be configured as a custom button in its nib/storyboard.")
        }
    }
    
    open override var bounds: CGRect {
        get {
            return super.bounds
        }
        set {
            super.bounds = newValue
            mask?.frame = backgroundRect(forBounds: bounds)
        }
    }
    
    open override var isHighlighted: Bool {
        get {
            return super.isHighlighted
        }
        set {
            super.isHighlighted = newValue
            updateBackgroundColorForCurrentState()
        }
    }
    
    open override var isSelected: Bool {
        get {
            return super.isSelected
        }
        set {
            super.isSelected = newValue
            updateBackgroundColorForCurrentState()
        }
    }
    
    open override var isEnabled: Bool {
        get {
            return super.isEnabled
        }
        set {
            super.isEnabled = newValue
            updateBackgroundColorForCurrentState()
        }
    }
    
    open override func contentRect(forBounds bounds: CGRect) -> CGRect {
        var rect = bounds
        rect.origin.x += padding.left
        rect.origin.y += padding.top
        rect.size.width -= (padding.left + padding.right)
        rect.size.height -= (padding.top + padding.bottom)
        return rect
    }
    
    // MARK: UIView
    
    open override var intrinsicContentSize: CGSize {
        get {
            var size = super.intrinsicContentSize
            size.width += (padding.left + padding.right)
            size.height += (padding.top + padding.bottom)
            return size
        }
    }
    
    private var minimumHeightConstraint: NSLayoutConstraint? = nil
    
    open override func updateConstraints() {
        super.updateConstraints()
        
        if minimumHeightConstraint == nil {
            let minimumHeightConstraint = heightAnchor.constraint(greaterThanOrEqualToConstant: 40)
            NSLayoutConstraint.activate([minimumHeightConstraint])
            self.minimumHeightConstraint = minimumHeightConstraint
        }
    }
    
    open override func layoutSubviews() {
        super.layoutSubviews()
        mask?.frame = bounds
    }

    // MARK: Utilities
    
    @objc public class func blendedColor(from colors: [UIColor]) -> UIColor {
        let colorspace = CGColorSpaceCreateDeviceRGB()
        let cgColors = colors.map { $0.cgColor }
        let compositeColor = OACreateCompositeColorFromColors(colorspace, cgColors)
        
        return UIColor(cgColor: compositeColor)
    }

    // MARK: Private
    
    private var baseStateForCurrentState: State {
        let baseState: State
        if !isEnabled {
            baseState = .disabled
        } else if isSelected {
            baseState = .selected
        } else if isHighlighted {
            baseState = .highlighted
        } else {
            baseState = .normal
        }
        
        return baseState
    }
    
    private func updateBackgroundColorForCurrentState() {
        let backgroundColor: UIColor?
        if let colorForState = self.backgroundColor(for: state) {
            backgroundColor = colorForState
        } else {
            let baseState = baseStateForCurrentState
            backgroundColor = self.backgroundColor(for: baseState)
        }
        
        if let backgroundColor = backgroundColor {
            self.backgroundColor = backgroundColor
        } else {
            let computedBackgroundColor: UIColor?

            if !isEnabled {
                computedBackgroundColor = self.backgroundColor(for: .normal)?.withAlphaComponent(0.25)
            } else if isSelected {
                // REVIEW: What is a reasonable computed color for the selected state?
                computedBackgroundColor = self.backgroundColor(for: .normal)
            } else if isHighlighted {
                if let backgroundColor = self.backgroundColor(for: .normal) {
                    let overlayColor = UIColor(white: 0.0, alpha: 0.175)
                    computedBackgroundColor = RoundRectButton.blendedColor(from: [backgroundColor, overlayColor])
                } else {
                    computedBackgroundColor = UIColor(white: 0.0, alpha: 0.175)
                }
            } else {
                computedBackgroundColor = nil
            }

            self.backgroundColor = computedBackgroundColor
        }
    }
}
