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
        return OUIDocumentExporter.printImage
    }
    
    public override func canPerform(withActivityItems activityItems: [Any]) -> Bool {
        guard UIPrintInteractionController.isPrintingAvailable else { return false }
        return super.canPerform(withActivityItems: activityItems)
    }
    
    public override func isSuitableDocumentType(_ type: OUIDocument.Type) -> Bool {
        guard super.isSuitableDocumentType(type) else { return false }
        return OBClassImplementingMethod(type, #selector(OUIDocument.print(withParentViewController:completionHandler:))) != OUIDocument.self
    }
    
    private var wrappingViewController: OUIWrappingViewController!

    public override func prepare(withActivityItems activityItems: [Any]) {
        super.prepare(withActivityItems: activityItems)
        
        self.wrappingViewController = OUIWrappingViewController()
        
        // The regular `perform()` function won't be called since we provide a view controller.
        startProcessing()
    }

    public override var activityViewController: UIViewController? {
        return wrappingViewController
    }

    public override func process(document: OUIDocument, completionHandler: @escaping () -> Void) {
        document.print(withParentViewController: wrappingViewController) { errorOrNil in
            if let error = errorOrNil {
                // TODO: Allow cancelling when printing multiple documents
                print("Error printing: \(error)")
            }
            completionHandler()
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

