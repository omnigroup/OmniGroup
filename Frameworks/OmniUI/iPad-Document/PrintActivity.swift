// Copyright 2015-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

import Foundation
import Photos

public class PrintActivity : DocumentProcessingActivity<OUIDocument> {
            
    static let activityType = UIActivity.ActivityType("com.omnigroup.frameworks.OmniUIDocument.Print")

    public override var activityType: UIActivity.ActivityType? {
        return type(of: self).activityType
    }

    public override var activityTitle: String? {
        return NSLocalizedString("Print", tableName: "OmniUIDocument", bundle: OmniUIDocumentBundle, comment: "Share option title")
    }
    
    public override var activityImage: UIImage? {
        return UIImage.init(systemName: "printer")
    }
    
    public override func canPerform(withActivityItems activityItems: [Any]) -> Bool {
        guard UIPrintInteractionController.isPrintingAvailable else { return false }
        return super.canPerform(withActivityItems: activityItems)
    }
    
    public override func isSuitableDocumentType(_ type: OUIDocument.Type) -> Bool {
        guard super.isSuitableDocumentType(type) else { return false }
        return OBClassImplementingMethod(type, #selector(OUIDocument.print(withParentViewController:completionHandler:))) != OUIDocument.self
    }

    public override func makeProcessingViewController() -> UIViewController? {
        return nil
    }

    public override func process(document: OUIDocument, completionHandler: @escaping () -> Void) {

        let viewController: UIViewController
        viewController = OUIWrappingViewController()
        viewController.view = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: 0))

        document.print(withParentViewController: viewController) { errorOrNil in
            if let error = errorOrNil {
                OUIAppController.presentError(error, from: self.processingViewController, file: #file, line: #line, cancelButtonTitle: nil, optionalActions: nil, completionHandler: completionHandler)
            } else {
                completionHandler()
            }
        }
    }
    
    // MARK:- Private
    
    @objc private func writeToPhotos(image: UIImage, didFinishSavingWithError error: NSError?, contextInfo: UnsafeMutableRawPointer?) {
        if let error = error {
            assertionFailure("Error saving to photo library: \(error)")
        }
    }
}

extension OUIDocumentExporter {
    @objc public static var printActivityType: UIActivity.ActivityType {
        return PrintActivity.activityType
    }
    @objc public func makePrintActivity() -> UIActivity {
        return PrintActivity()
    }
}

