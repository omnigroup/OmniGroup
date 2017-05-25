// Copyright 2016-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

struct MultiPaneLayout {
    /// Returns the layout constraints for the given set of panes. These contraints are not activated
    /// expects and array of panes, that will be ordered from L -> R in their superview.
    static let leadingConstraintID = "main-leading"
    static let trailingConstraintID = "main-trailing"
    
    static func layout(forPanes panes: [Pane]) -> [NSLayoutConstraint] {
        guard panes.count > 0 else {
            // If we end up here, we need to know why. The layout should get called with at least one pane.
            assertionFailure("expected at least 1 pane to layout, got 0")
            return []
        }
        
        var constraints = [NSLayoutConstraint]()
        var horizontalFormat = "H:|"
        var viewsDict: [String : UIView] = [:]
        
        var shouldShowLeft = false
        var shouldShowRight = false
        
        var leftPane: Pane?
        var rightPane: Pane?
        
        panes.forEach { (pane) in
            let nameKey = pane.location.description
            let format = "[\(nameKey)]"
            horizontalFormat += format
            viewsDict[nameKey] = pane.viewController.view
            
            constraints.append(contentsOf: self.verticalConstraints(pane: pane))
            
            if pane.location == .left {
                leftPane = pane
                if pane.visibleWhenEmbedded {
                    shouldShowLeft = true
                }
            }
            if pane.location == .right {
                rightPane = pane
                if pane.visibleWhenEmbedded {
                    shouldShowRight = true
                }
            }
        }
        
        horizontalFormat += "|"
        let horizontalConstraints = NSLayoutConstraint.constraints(withVisualFormat: horizontalFormat, options: [], metrics: nil, views: viewsDict)
        constraints.append(contentsOf: horizontalConstraints)
        
        constraints.forEach { (constraint) in
            if constraint.firstAttribute == .leading && constraint.secondAttribute == .leading {
                constraint.identifier = leadingConstraintID
                if let leftPane = leftPane, !shouldShowLeft {
                    constraint.constant = leftPane.viewController.view.bounds.width * -1
                }
            }
            if constraint.firstAttribute == .trailing && constraint.secondAttribute == .trailing {
                constraint.identifier = trailingConstraintID
                if let rightPane = rightPane, !shouldShowRight {
                    constraint.constant = rightPane.viewController.view.bounds.width * -1
                }
            }
        }
        
        return constraints
    }
    
    static private func verticalConstraints(pane: Pane) -> [NSLayoutConstraint] {
        let topAndBottom = "V:|[view]|"
        return NSLayoutConstraint.constraints(withVisualFormat: topAndBottom, options: [], metrics: nil, views: ["view" : pane.viewController.view])
    }
    
    /// The leading constraint between the given view and its superview
    static func leadingConstraint(forView view: UIView) -> NSLayoutConstraint? {
        return view.constraintWithIdentifier(identifier: self.leadingConstraintID)
    }
    
    /// the trailing constraint between the given view and its superview
    static func trailingConstraint(forView view: UIView) -> NSLayoutConstraint? {
        return view.constraintWithIdentifier(identifier: self.trailingConstraintID)
    }
}

typealias UIViewLayoutConstraintHelper = UIView
extension UIViewLayoutConstraintHelper {
    func constraintWithIdentifier(identifier: String) -> NSLayoutConstraint? {
        return self.constraints.first { $0.identifier == identifier }
    }
}

