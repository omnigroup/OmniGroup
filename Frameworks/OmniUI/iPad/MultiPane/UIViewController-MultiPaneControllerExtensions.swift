// Copyright 2016-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

public protocol MultiPaneContentController {
    var multiPaneConfiguration: MultiPaneConfiguration? { get }
    func multiPaneConfigurationDidChange(to configuration: MultiPaneConfiguration)
}

// MARK: -

extension UIViewController: MultiPaneContentController {
    @nonobjc private static var ConfigKey = "ConfigKey"
    
    /// returns the stored MultiPaneConfiguration, walking the parent controller heirarchy trying to find a controller with a value.
    @objc /**REVIEW**/ public internal (set) var multiPaneConfiguration: MultiPaneConfiguration? {
        set (newValue) {
            objc_setAssociatedObject(self, &UIViewController.ConfigKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            if let config = newValue {
                self.multiPaneConfigurationDidChange(to: config)
            }
        }
        
        get {
            if let config = objc_getAssociatedObject(self, &UIViewController.ConfigKey) as? MultiPaneConfiguration {
                return config
            }
            
            return self.parent?.multiPaneConfiguration
        }
    }
    
    /// Informs controllers that the displayMode of the MultiPaneController has changed. This messages is sent to the UIViewControllers managed by Panes of the MultiPaneController regardless of the Pane's presentation mode. View Controllers that implement this method should not assume that they are embedded (child view controllers) in the MultiPaneController when called.
    /// clients that override should call super.
    @objc /**REVIEW**/ open func multiPaneConfigurationDidChange(to configuration: MultiPaneConfiguration) {
        for child in self.children {
            child.multiPaneConfigurationDidChange(to: configuration)
        }
    }
}

// MARK: -

@objc public protocol MultiPaneControllerFinding {
    var multiPaneController: MultiPaneController? { get }
    var presentingOrAncestorMultipaneController: MultiPaneController? { get }
}

// MARK: -

extension UIViewController: MultiPaneControllerFinding {
    // This doesn't work when the left pane is displayed as an overlay -- in that case the `parent` of the sidebar navigation controller is nil and instead the multi-pane controller is its presenting view controller.
    @objc open var multiPaneController: MultiPaneController? {
        if let multiPane = self as? MultiPaneController {
            return multiPane
        }
        
        return self.parent?.multiPaneController ?? nil
    }
    
    // This works in the case that the method above does not. However, if a parent of your multipane controller is the controller that defines the presentation context for some presented VC, this can still return nil, since the multipane controller's parent will be the presentingViewController. If you own that parent VC, you can override this method and return its child multipane controller instead.
    @objc open var presentingOrAncestorMultipaneController: MultiPaneController? {
        if let multiPane = self as? MultiPaneController {
            return multiPane
        }
        
        return self.parent?.presentingOrAncestorMultipaneController ?? self.presentingViewController?.presentingOrAncestorMultipaneController ?? nil
    }
}

