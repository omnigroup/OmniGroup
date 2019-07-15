// Copyright 2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

import Foundation

@objc(OARoundRectButton) public final class RoundRectButton: NSButton {
    
    public override init(frame: NSRect) {
        super.init(frame: frame)
        
        // Closest in frame/alignment geometry to what we're doing here
        buttonCell.bezelStyle = .smallSquare
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)

        // Closest in frame/alignment geometry to what we're doing here
        buttonCell.bezelStyle = .smallSquare
    }
    
    // MARK: - Class Properties
    override public static var cellClass: AnyClass? {
        get {
            return OARoundRectButtonCell.self
        }
        set {}
    }
    
    // MARK: - NSButton Subclass
    override public var allowsMixedState: Bool {
        get {
            return false
        }
        set {}
    }
    
    override public var isBordered: Bool {
        didSet {
            updateCell(buttonCell)
        }
    }
    
    override public func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
    }
    
    private var minHeightConstraint: NSLayoutConstraint! {
        didSet {
            if minHeightConstraint == nil && oldValue != nil {
                NSLayoutConstraint.deactivate([oldValue])
            }
        }
    }
    public override func updateConstraints() {
        super.updateConstraints()
        if minHeightConstraint == nil {
            minHeightConstraint = heightAnchor.constraint(greaterThanOrEqualToConstant: 30)
        }
        NSLayoutConstraint.activate([minHeightConstraint])
    }
    
    override public var intrinsicContentSize: NSSize {
        get {
            // We want a minimum of 20 points of padding around our button's title on each side
            var size = super.intrinsicContentSize
            size.width = size.width + 40
            return size
        }
    }
    
    public override var alignmentRectInsets: NSEdgeInsets {
        get {
            // We take over the entire frame for drawing; align to the frame not an inset portion of it.
            return NSEdgeInsetsZero
        }
    }
    
    // MARK: - Implementation
    
    private var buttonCell: OARoundRectButtonCell! {
        return cell as? OARoundRectButtonCell
    }
    
    
    @IBInspectable public var textColor: NSColor! {
        set {
            let newFontColor = newValue ?? NSColor.black
            
            if font == nil || font?.pointSize != 14 {
                let fontOfSize14: NSFont
                if let font = font {
                    fontOfSize14 = NSFont(descriptor: font.fontDescriptor, size: 14)!
                } else {
                    fontOfSize14 = NSFont.systemFont(ofSize: 14)
                }
                font = fontOfSize14
            }
            
            let currentAttributes = NSMutableAttributedString(attributedString: attributedTitle)
            let range = NSMakeRange(0, currentAttributes.length)
            currentAttributes.addAttributes([.foregroundColor : newFontColor], range: range)
            self.attributedTitle = currentAttributes
            
            needsDisplay = true
        }
        get {
            return attributedTitle.attributes(at: 0, effectiveRange: nil)[.foregroundColor] as? NSColor ?? NSColor.black
        }
    }
    
    @IBInspectable public var borderColor: NSColor! {
        set {
            buttonCell.borderColor = newValue
            updateCell(buttonCell)
        }
        get {
            return buttonCell.borderColor
        }
    }
    
    @IBInspectable public var pressedBorderColor: NSColor! {
        get {
            return buttonCell.pressedBorderColor
        }
        set {
            buttonCell.pressedBorderColor = newValue
            updateCell(buttonCell)
        }
    }
    
    @IBInspectable public var backgroundColor: NSColor! {
        get {
            return buttonCell.unpressedBackgroundColor
        }
        set {
            buttonCell.unpressedBackgroundColor = newValue
            updateCell(buttonCell)
        }
    }
    
    @IBInspectable public var pressedBackgroundColor: NSColor! {
        get {
            return buttonCell.pressedBackgroundColor
        }
        set {
            buttonCell.pressedBackgroundColor = newValue
            updateCell(buttonCell)
        }
    }
    
    @IBInspectable public var borderWidth: CGFloat {
        get {
            return buttonCell.borderWidth
        }
        set {
            buttonCell.borderWidth = newValue
            updateCell(buttonCell)
        }
    }
    
    @IBInspectable var cornerRadius: CGFloat {
        get {
            return buttonCell.cornerRadius
        }
        set {
            buttonCell.cornerRadius = newValue
            updateCell(buttonCell)
        }
    }
}

public final class OARoundRectButtonCell: NSButtonCell {
    
    fileprivate var borderColor: NSColor = NSColor.gray
    fileprivate var pressedBorderColor: NSColor = NSColor.darkGray
    fileprivate var unpressedBackgroundColor: NSColor = NSColor.white
    fileprivate var pressedBackgroundColor: NSColor = NSColor.white
    fileprivate var borderWidth: CGFloat = 5
    fileprivate var cornerRadius: CGFloat = 5
    private var usesAlternateColor: Bool = false
    
    override public func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        if usesAlternateColor {
            backgroundColor = pressedBackgroundColor
        } else {
            backgroundColor = unpressedBackgroundColor
        }
        context.saveGState()
        OACGAddRoundedRect(context, cellFrame, cornerRadius, cornerRadius, cornerRadius, cornerRadius)
        context.clip()
        if isBordered, let backgroundColor = backgroundColor {
            // Default interior drawing for bordered cell does not draw background color
            backgroundColor.set()
            context.fill(cellFrame)
        }
        super.drawInterior(withFrame: cellFrame, in: controlView)
        context.restoreGState()
    }
    
    override public func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        if isBordered {
            let paddedCellFrame = cellFrame.insetBy(dx: borderWidth/2.0, dy: borderWidth/2.0)
            drawInterior(withFrame: paddedCellFrame, in: controlView)
            context.saveGState()
            OACGAddRoundedRect(context, paddedCellFrame, cornerRadius, cornerRadius, cornerRadius, cornerRadius)
            context.setLineWidth(borderWidth)
            if usesAlternateColor {
                pressedBorderColor.set()
            } else {
                borderColor.set()
            }
            context.strokePath()
            context.restoreGState()
        } else {
            drawInterior(withFrame: cellFrame, in: controlView)
        }
    }
    
    override public func highlight(_ flag: Bool, withFrame cellFrame: NSRect, in controlView: NSView) {
        usesAlternateColor = flag
        super.highlight(flag, withFrame: cellFrame, in: controlView)
    }

}
