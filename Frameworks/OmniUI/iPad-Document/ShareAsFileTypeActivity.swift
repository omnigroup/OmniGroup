// Copyright 2015-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

import Foundation
import UIKit

import OmniUIDocument.Internal

private class ShareAsFileTypeActivity : DocumentConversionActivity<OUIDocument, FileWrapper> {
    
    static let activityType = UIActivity.ActivityType("com.omnigroup.frameworks.OmniUIDocument.ShareAsFileType")
    
    let exporter: OUIDocumentExporter
    
    init(exporter: OUIDocumentExporter) {
        self.exporter = exporter
    }
    
    public override var activityType: UIActivity.ActivityType? {
        return type(of: self).activityType
    }
    
    public override var activityTitle: String? {
        return NSLocalizedString("Share as ...", tableName: "OmniUIDocument", bundle: OmniUIDocumentBundle, comment: "Share activity title")
    }

    public override var activityImage: UIImage? {
        return UIImage(named: "OUIMenuItemSendToApp", in: OmniUIDocumentBundle, with: nil)
    }
    
    public override func canPerform(withActivityItems activityItems: [Any]) -> Bool {
        // TODO: Check with our exporter if there are convertible output types for the inputs
        return true
    }
    
    private var exportOptionsController: OUIExportOptionsController!
    private var exportViewController: UIViewController!
    
    public override func prepare(withActivityItems activityItems: [Any]) {
        super.prepare(withActivityItems: activityItems)
        
        exportOptionsController = OUIExportOptionsController(fileURLs: self.fileURLs, exporter: exporter, activity: self)
        exportViewController = exportOptionsController.viewController
    }
    
    public override var activityViewController: UIViewController? {
        return exportViewController
    }
}

extension OUIDocumentExporter {
    @objc public static var shareAsActivityType: UIActivity.ActivityType {
        return ShareAsFileTypeActivity.activityType
    }
    @objc public func makeShareAsActivity() -> UIActivity {
        return ShareAsFileTypeActivity(exporter: self)
    }
}
