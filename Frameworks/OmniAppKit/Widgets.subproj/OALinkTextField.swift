// Copyright 2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

import AppKit

// NSTextField must be selectable or any spans with link attributes will not be clickable. This adds cursor rects and makes them clickable anyway.
class OALinkTextField: NSTextField {

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        if !self.isSelectable {
            openClickedHyperlink(with: event)
        }
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if !self.isSelectable {
            addHyperlinkCursorRects()
        }
    }
    
    override var attributedStringValue: NSAttributedString {
        didSet {
            if !self.isSelectable {
                resetCursorRects()
            }
        }
    }

    /// Displays a hand cursor when a link is hovered over.
    private func addHyperlinkCursorRects() {
        guard let cell = cell else { return }
        let textBounds = cell.titleRect(forBounds: bounds)
        let textContainer = NSTextContainer()
        let layoutManager = NSLayoutManager()
        let textStorage = NSTextStorage()

        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)

        layoutManager.typesetterBehavior = NSLayoutManager.TypesetterBehavior.behavior_10_2_WithCompatibility

        textContainer.containerSize = textBounds.size
        textStorage.beginEditing()
        textStorage.setAttributedString(cell.attributedStringValue)
        textStorage.endEditing()

        let range = NSRange(location: 0, length: attributedStringValue.length)

        attributedStringValue.enumerateAttribute(NSAttributedString.Key.link, in: range) { value, range, _ in
            guard value != nil else {
                return
            }

            let rect = layoutManager.boundingRect(forGlyphRange: range, in: textContainer)
            addCursorRect(rect, cursor: .pointingHand)
        }
    }

    /// Opens links when clicked.
    private func openClickedHyperlink(with event: NSEvent) {
        guard let cell = cell else { return }
        let point = convert(event.locationInWindow, from: nil)

        let textBounds = cell.titleRect(forBounds: bounds)
        let textContainer = NSTextContainer()
        let layoutManager = NSLayoutManager()
        let textStorage = NSTextStorage()

        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)

        layoutManager.typesetterBehavior = NSLayoutManager.TypesetterBehavior.behavior_10_2_WithCompatibility

        textContainer.containerSize = textBounds.size
        textStorage.beginEditing()
        textStorage.setAttributedString(cell.attributedStringValue)
        textStorage.endEditing()

        let characterIndex = layoutManager.characterIndex(for: point, in: textContainer, fractionOfDistanceBetweenInsertionPoints: nil)

        guard characterIndex < attributedStringValue.length else {
            return
        }

        let attributes = attributedStringValue.attributes(at: characterIndex, effectiveRange: nil)

        guard let urlString = attributes[NSAttributedString.Key.link] as? String, let url = URL(string: urlString) else {
            return
        }

        NSWorkspace.shared.open(url)
    }

}
