// Copyright 2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

import Foundation

@objc(OUILicensingAuthenticationCommand) class LicensingAuthenticationCommand: OUISpecialURLCommand {
    
    @available(iOSApplicationExtension, unavailable)
    override func invoke() {
        OUIAppController.shared().handleLicensingAuthenticationURL(url, presentationSource: self.viewControllerForPresentation)
    }
    
    override var skipsConfirmation: Bool {
        return true
    }
}
