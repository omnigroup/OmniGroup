// Copyright 2017 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$


@objc public final class OUINewDocumentCreationContext: NSObject {

    // If the templateURL is not defined the default template for new documents will be used.
    @objc public var templateURL: URL?
    // Do not set unless you want the new file created to use the documentName for the new file instead of the default name for new files
    @objc public var documentName: String?
    // This is the actual view of the template we will animate from when opening the newly created file
    @objc public var animateFromView: UIView?
    @objc public let scope: ODSScope
    @objc public let store: ODSStore
    @objc public let folderItem: ODSFolderItem
    @objc public let documentType: ODSDocumentType

    @objc public init(with scope: ODSScope, store: ODSStore, folderItem: ODSFolderItem, documentType: ODSDocumentType, templateURL: URL? = nil, documentName: String? = nil, animateFromView: UIView? = nil) {
        self.scope = scope
        self.store = store
        self.folderItem = folderItem
        self.documentType = documentType
        self.templateURL = templateURL
        self.documentName = documentName
        self.animateFromView = animateFromView

        super.init()
    }
}
