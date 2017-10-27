// Copyright 2015-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

import Foundation

extension Bundle {
    @objc public var displayName:String {
        if let name = localizedInfoDictionary?["CFBundleName"] as? String {
            return name
        }
        return FileManager.default.displayName(atPath: self.bundlePath)
    }
    
    @objc public func contains(_ bundle: Bundle) -> Bool {
        do {
            let otherURL = bundle.bundleURL
            let fileManager = FileManager.default
            
            var relationship: FileManager.URLRelationship = .same
            try fileManager.getRelationship(&relationship, ofDirectoryAt: bundleURL, toItemAt: otherURL)
            return relationship == .contains
        } catch {
            return false
        }
    }
}
