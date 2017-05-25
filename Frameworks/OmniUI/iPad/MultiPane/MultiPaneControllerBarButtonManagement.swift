// Copyright 2016-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

public protocol MultiPaneChildViewController {
    var backButtonTitle: String? {get}
}

extension UIViewController: MultiPaneChildViewController {
    open var backButtonTitle: String? { return self.title }
}

extension UINavigationController {
    override open var backButtonTitle: String? {
        return self.topViewController?.backButtonTitle
    }
}

