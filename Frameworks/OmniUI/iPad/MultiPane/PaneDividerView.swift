// Copyright 2016-2017 Omni Development, Inc. All rights reserved.
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
            self.widthConstraint?.constant = width
        }
    }
    
    // divider width when editing, chanages take effect when editing state changes
    var editingWidth: CGFloat = 6.0
    
    // non-editing divider color
    var color: UIColor = UIColor.lightGray {
        didSet {
            self.backgroundColor = color
        }
    }
    
    // divider color when editing, changes take effect when editing state changes
    var editingColor: UIColor = UIColor.darkGray
    
    var editStateChanged: (EditState) -> () = { _ in } {
        didSet {
            // only setup a gesture recongnizer if client wants state events.
            let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress))
            longPress.debugIdentifier = "MultiPane resize"
            self.addGestureRecognizer(longPress)
            self.longPressGesture = longPress
        }
    }
    
    private var longPressGesture: UILongPressGestureRecognizer?
    private var widthConstraint: NSLayoutConstraint?
    
    private(set) var isEditing = false {
        didSet {
            self.editStateChanged((isEditing ? .Started : .Ended))
        }
    }
    
    lazy private var dragHandle: UIView = { [unowned self] in
        let view = UIView()
        self.addSubview(view)
        view.layer.cornerRadius = 2.0
        view.backgroundColor = UIColor.white
        view.isHidden = true
        
        view.translatesAutoresizingMaskIntoConstraints = false
        view.centerXAnchor.constraint(equalTo: self.centerXAnchor).isActive = true
        view.centerYAnchor.constraint(equalTo: self.centerYAnchor).isActive = true
        // make the handle width slightly less than the view's editingWidth
        view.widthAnchor.constraint(equalToConstant: self.editingWidth - 1).isActive = true
        view.heightAnchor.constraint(equalToConstant: 40.0).isActive = true
        return view
        }()
    
    
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
        if point.x >= -offset && point.x <= self.bounds.width + offset {
            return true
        }
        return false
    }
    
    @objc private func handleLongPress(gesture: UIGestureRecognizer) {
        switch gesture.state {
        case .began:
            self.update(forEditingState: true)
            break
        case .changed:
            self.editStateChanged(.Changed(gesture.location(in: self).x))
            break
        case .ended:
            self.update(forEditingState: false)
            break
        default:
            // cancelled/failed should just end editing and cleanup.
            self.update(forEditingState: false)
            break
        }
    }
    
    private func update(forEditingState editing: Bool) {
        if editing {
            self.widthConstraint?.constant = self.editingWidth
            self.backgroundColor = self.editingColor
            self.dragHandle.isHidden = false
            self.isEditing = true
        } else {
            self.widthConstraint?.constant = self.width
            self.backgroundColor = self.color
            self.dragHandle.isHidden = true
            self.isEditing = false
        }
    }
}

