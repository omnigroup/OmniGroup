// Copyright 2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

import Foundation

public final class RoundRectButton: NSButton {
    public override init(frame: NSRect) {
        RoundRectButton.registerCellClassIfNeeded()
        super.init(frame: frame)
        commonInit()
    }
    
    public required init?(coder: NSCoder) {
        RoundRectButton.registerCellClassIfNeeded()
        super.init(coder: coder)
        commonInit()
        
        if backgroundColor == nil {
            backgroundColor = NSColor.lightGray
        }
        
        if textColor == nil {
            textColor = NSColor.controlTextColor
        }
    }
    
    private static func registerCellClassIfNeeded() {
        let isRegistered = cellClass is RoundRectButtonCell.Type
        if !isRegistered {
            cellClass = RoundRectButtonCell.self
        }
    }
    
    private func commonInit() {
        // Match the configuration of +[NSButton _buttonWithTitle:image:target:action:], overriding bad attributes configured in IB…
        //
        //    [r14 setImagePosition:rbx];
        //    [r14 setImageScaling:0x0];
        //    [r14 setBezelStyle:0x1];
        //    [r14 setButtonType:0x7];
        //    [r14 setLineBreakMode:0x4];

        imagePosition = .noImage
        imageScaling = .scaleNone
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        lineBreakMode = .byTruncatingTail
    }

    private var buttonCell: RoundRectButtonCell {
        return cell as! RoundRectButtonCell
    }

    public override var alignmentRectInsets: NSEdgeInsets {
        get {
            // We take over the entire frame for drawing; align to the frame not an inset portion of it.
            return NSEdgeInsetsZero
        }
    }

    @objc public var cornerRadius: CGFloat {
        get {
            return buttonCell.cornerRadius
        }
        set {
            buttonCell.cornerRadius = newValue
            needsDisplay = true
        }
    }
    
    @objc public var borderWidth: CGFloat {
        get {
            return buttonCell.borderWidth
        }
        set {
            buttonCell.borderWidth = newValue
            needsDisplay = true
        }
    }

    @objc public var textColor: NSColor? {
        get {
            return buttonCell.textColor
        }
        set {
            buttonCell.textColor = newValue
            needsDisplay = true
        }
    }
    
    @objc public var borderColor: NSColor? {
        set {
            buttonCell.borderColor = newValue
            needsDisplay = true
        }
        get {
            return buttonCell.borderColor
        }
    }
    
    @objc public var backgroundColor: NSColor? {
        get {
            return buttonCell.backgroundColor
        }
        set {
            buttonCell.backgroundColor = newValue
            needsDisplay = true
        }
    }

    @objc public var highlightColor: NSColor? {
        get {
            return buttonCell.highlightColor
        }
        set {
            buttonCell.highlightColor = newValue
            needsDisplay = true
        }
    }
}

// MARK: -

public final class RoundRectButtonCell: NSButtonCell {
    public var cornerRadius: CGFloat = 6
    public var borderWidth: CGFloat = 0
    public var borderColor: NSColor? = nil
    public var textColor: NSColor? = nil
    public var highlightColor: NSColor? = nil

    public override var isBordered: Bool {
        get {
            return super.isBordered
        }
        set {
            assert(newValue == false, "To suppress the border, set borderColor to nil or clear.")
            super.isBordered = newValue
        }
    }
    
    public override var cellSize: NSSize {
        var cellSize = super.cellSize
        
        if isBordered && borderWidth > 0 {
            cellSize.height += 2 * borderWidth
            cellSize.width += 2 * borderWidth
        }
        
        // Add required padding around the title if needed
        if !isBordered {
            cellSize.width += 2 * 15
            cellSize.height += 2 * 6
        }
        
        // Enforce a minimum height
        cellSize.height = max(cellSize.height, 30)
        
        return cellSize
    }
    
    override public func drawBezel(withFrame frame: NSRect, in controlView: NSView) {
        let bezelPath = self.bezelPath(forBounds: frame, insetForBorderIfNeeded: true)

        if let backgroundColor = backgroundColor {
            backgroundColor.setFill()
            bezelPath.fill()
            
            if isHighlighted {
                effectiveHighlightColor.setFill()
                bezelPath.fill()
            }
        }
        
        if isBordered, borderWidth > 0, let borderColor = borderColor {
            borderColor.setStroke()
            bezelPath.lineWidth = borderWidth
            bezelPath.stroke()
        }
    }

    override public func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        let verticalOffset: CGFloat = isBordered ? 1 : -1
        let titleRect = self.titleRect(forBounds: cellFrame).offsetBy(dx: 0, dy: verticalOffset)
        drawTitle(effectiveAttributedTitle, withFrame: titleRect, in: controlView)
    }

    override public func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        drawBezel(withFrame: cellFrame, in: controlView)
        drawInterior(withFrame: cellFrame, in: controlView)
    }
    
    // MARK: Private
    
    private func bezelPath(forBounds cellFrame: NSRect, insetForBorderIfNeeded: Bool) -> NSBezierPath {
        var pathRect = cellFrame

        if insetForBorderIfNeeded && isBordered && borderWidth > 0 && borderColor != nil {
            let halfBorder = (borderWidth / 2.0)
            pathRect = pathRect.insetBy(dx: halfBorder, dy: halfBorder)
        }
        
        return NSBezierPath(roundedRect: pathRect, xRadius: cornerRadius, yRadius: cornerRadius)
    }
    
    private var effectiveHighlightColor: NSColor {
        if let highlightColor = highlightColor {
            return highlightColor
        } else {
            return NSColor(white: 0.0, alpha: 0.125)
        }
    }
    
    private var effectiveTextColor: NSColor {
        if isEnabled {
            if let textColor = textColor {
                return textColor
            } else if let backgroundColor = backgroundColor {
                return backgroundColor.isLightColor ? NSColor.black : NSColor.white
            } else {
                return NSColor.black
            }
        } else {
            return textColor?.withAlphaComponent(0.4) ?? NSColor.disabledControlTextColor
        }
    }
    
    /// The attributed title used for drawing. This would be slightly nicer if we could override/augment _textAttributes.
    private var effectiveAttributedTitle: NSAttributedString {
        let attributedTitle = super.attributedTitle.mutableCopy() as! NSMutableAttributedString
        let textColor = effectiveTextColor
        
        attributedTitle.enumerateAttributes(in: NSMakeRange(0, attributedTitle.length), options: []) { (attributes, range, outStop) in
            guard attributes[.backgroundColor] == nil else { return }
            let foregroundColor = attributes[.foregroundColor] as? NSColor
            let shouldReplaceForegroundColor: Bool
            
            switch foregroundColor {
            case NSColor.controlTextColor, NSColor.selectedControlTextColor, NSColor.alternateSelectedControlTextColor, NSColor.disabledControlTextColor:
                shouldReplaceForegroundColor = true
                
            case nil:
                shouldReplaceForegroundColor = true
                
            default:
                shouldReplaceForegroundColor = false
            }
            
            if shouldReplaceForegroundColor {
                attributedTitle.addAttribute(.foregroundColor, value: textColor, range: range)
            }
        }
        
        return attributedTitle
    }
}
