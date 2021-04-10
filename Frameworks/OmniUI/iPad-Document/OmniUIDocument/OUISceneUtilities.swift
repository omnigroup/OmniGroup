// Copyright 2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

import Foundation

extension UIView {
    @objc open var sceneDelegate: OUIDocumentSceneDelegate? {
        guard let sceneDelegate = OUIDocumentSceneDelegate.init(for: self) else { return nil }
        return sceneDelegate
    }

    @objc open var sceneDocument: OUIDocument? {
        guard self.window != nil else { return nil }
        guard let sceneDelegate = sceneDelegate else { return nil }
        return sceneDelegate.document
    }
}

extension UIViewController {
    @objc open var sceneDelegate: OUIDocumentSceneDelegate? {
        return self.parent?.sceneDelegate ?? self.view.sceneDelegate
    }

    @objc open var sceneDocument: OUIDocument? {
        return self.parent?.sceneDocument ?? self.view.sceneDocument
    }
}
