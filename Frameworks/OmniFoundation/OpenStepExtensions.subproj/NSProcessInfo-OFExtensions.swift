// Copyright 2016 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$


import Foundation

extension ProcessInfo {
    public var isRunningUnitTests: Bool {
        let env = self.environment
        // Xcode 7.3 and greater doesn't include XCInjectBundle key, but does have the XCTestConfigurationFilePath key. Prefer the newer key, but have XCInjectBundle as a fallback.
        let path = env["XCTestConfigurationFilePath"] ?? env["XCInjectBundle"]
        if path != nil {
            return Bundle.allBundles.contains { $0.bundleURL.pathExtension == "xctest" }
        }
        return false
    }
}
