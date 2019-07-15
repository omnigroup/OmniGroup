// Copyright 2016-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

import UIKit

class PaneDividerView: UIView {
    enum EditState {
        case Started
        case Changed(CGFloat)
        case Ended
    }
    
    // non-editing divider width
    var width: CGFloat = 0.5 {
        didSet {
            widthConstraint?.constant = width
        }
    }
    
    static var defaultColor = UIColor.lightGray
    static var defaultEditingColor = UIColor.darkGray

    // divider width when editing, chanages take effect when editing state changes
    var editingWidth: CGFloat = 6.0
    
    // non-editing divider color
    var color: UIColor = PaneDividerView.defaultColor {
        didSet {
            backgroundColor = color
        }
    }
    
    // divider color when editing, changes take effect when editing state changes
    var editingColor: UIColor = PaneDividerView.defaultEditingColor
    
    var editStateChanged: (EditState) -> () = { _ in } {
        didSet {
            // only setup a gesture recongnizer if client wants state events.
            let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress))
            longPress.debugIdentifier = "MultiPane resize"
            addGestureRecognizer(longPress)
            longPressGesture = longPress
        }
    }
    
    private var longPressGesture: UILongPressGestureRecognizer?
    private var widthConstraint: NSLayoutConstraint?
    
    private(set) var isEditing = false {
        didSet {
            editStateChanged((isEditing ? .Started : .Ended))
        }
    }
    
    lazy private var dragHandle: UIView = makeDragHandle()
        
    private func makeDragHandle() -> UIView {
        let view = UIView()
        addSubview(view)
        view.layer.cornerRadius = 2.0
        view.backgroundColor = UIColor.white
        view.isHidden = true
        
        view.translatesAutoresizingMaskIntoConstraints = false
        view.centerXAnchor.constraint(equalTo: centerXAnchor).isActive = true
        view.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
        // make the handle width slightly less than the view's editingWidth
        view.widthAnchor.constraint(equalToConstant: editingWidth - 1).isActive = true
        view.heightAnchor.constraint(equalToConstant: 40.0).isActive = true
        return view
    }

    override init(frame: CGRect) {
        super.init(frame: CGRect.zero)
        self.backgroundColor = self.color
        
        let constraint = self.widthAnchor.constraint(equalToConstant: self.width)
        constraint.isActive = true
        self.widthConstraint = constraint
        
        self.clipsToBounds = false
    }
    
    convenience init() {
        self.init(frame: CGRect())
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // adjust the tap target for this view to allow for touches that are slightly off to either side
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        let offset:CGFloat = 7
        if point.x >= -offset && point.x <= bounds.width + offset {
            return true
        }
        return false
    }
    
    @objc private func handleLongPress(gesture: UIGestureRecognizer) {
        switch gesture.state {
        case .began:
            update(forEditingState: true)
            break

        case .changed:
            editStateChanged(.Changed(gesture.location(in: self).x))
            break

        case .ended:
            update(forEditingState: false)
            break

        default:
            // cancelled/failed should just end editing and cleanup.
            update(forEditingState: false)
            break
        }
    }
    
    private func update(forEditingState editing: Bool) {
        if editing {
            widthConstraint?.constant = editingWidth
            backgroundColor = editingColor
            dragHandle.isHidden = false
            isEditing = true
        } else {
            widthConstraint?.constant = width
            backgroundColor = color
            dragHandle.isHidden = true
            isEditing = false
        }
    }
}

