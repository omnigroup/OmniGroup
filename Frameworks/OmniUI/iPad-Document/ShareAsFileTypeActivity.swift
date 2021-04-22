// Copyright 2015-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

import Foundation
import UIKit
import OmniUIDocument.Internal

private class ShareAsFileTypeActivity : DocumentProcessingActivity<OUIDocument> {
    
    static let activityType = UIActivity.ActivityType("com.omnigroup.frameworks.OmniUIDocument.ShareAsFileType")
    
    let exporter: OUIDocumentExporter
    
    init(exporter: OUIDocumentExporter) {
        self.exporter = exporter
    }
    
    public override var activityType: UIActivity.ActivityType? {
        return type(of: self).activityType
    }
    
    public override var activityTitle: String? {
        return NSLocalizedString("Share As…", tableName: "OmniUIDocument", bundle: OmniUIDocumentBundle, comment: "Share activity title")
    }

    public override var activityImage: UIImage? {
        return UIImage.init(systemName: "square.and.arrow.up")
    }

    private var exportOptionsController: OUIExportOptionsController?

    public override func canPerform(withActivityItems activityItems: [Any]) -> Bool {
        if exportOptionsController == nil {
            self.prepare(withActivityItems: activityItems) // call to determine our fileURLs
            exportOptionsController = OUIExportOptionsController(fileURLs: self.fileURLs, exporter: exporter, activity: self)
        }
        return exportOptionsController!.hasExportOptions()
    }

    // MARK:- DocumentProcessingActivity subclass

    override public func makeProcessingViewController() -> UIViewController {
        if exportOptionsController == nil {
            exportOptionsController = OUIExportOptionsController(fileURLs: self.fileURLs, exporter: exporter, activity: self)
        }
        return exportOptionsController!.viewController
    }

    // MARK:- URLProcessingActivity subclass

    override public func startProcessing() {
        // Our "processing" is just collecting the fileURLs and handing them off to the export options interface
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
