// Copyright 2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

import Foundation

extension NSBundle {
    public var displayName:String {
        if let name = localizedInfoDictionary?["CFBundleName"] as? String {
            return name
        }
        return NSFileManager.defaultManager().displayNameAtPath(self.bundlePath)
    }
}
