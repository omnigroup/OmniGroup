// Copyright 2016-2017 Omni Development, Inc. All rights reserved.
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

extension UIViewController: MultiPaneContentController {
    @nonobjc private static var ConfigKey = "ConfigKey"
    
    /// returns the stored MultiPaneConfiguration, walking the parent controller heirarchy trying to find a controller with a value.
    public internal (set) var multiPaneConfiguration: MultiPaneConfiguration? {
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
    open func multiPaneConfigurationDidChange(to configuration: MultiPaneConfiguration) {
        for child in self.childViewControllers {
            child.multiPaneConfigurationDidChange(to: configuration)
        }
    }
}

public extension UIViewController {
    public var multiPaneController: MultiPaneController? {
        if let mulitPane = self as? MultiPaneController {
            return mulitPane
        }
        
        return self.parent?.multiPaneController ?? nil
    }
}

