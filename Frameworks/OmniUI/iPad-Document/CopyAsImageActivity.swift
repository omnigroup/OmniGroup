// Copyright 2015-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

import Foundation

public class CopyAsImageActivity : DocumentConversionActivity<OUIDocument, [String:Data]> {
            
    static let activityType = UIActivity.ActivityType("com.omnigroup.frameworks.OmniUIDocument.CopyAsImage")

    public override var activityType: UIActivity.ActivityType? {
        return type(of: self).activityType
    }

    public override var activityTitle: String? {
        return NSLocalizedString("Copy as Image", tableName: "OmniUIDocument", bundle: OmniUIDocumentBundle, comment: "Share option title")
    }
    
    public override var activityImage: UIImage? {
        return UIImage(systemName:"crop")
    }
    
    public override func isSuitableDocumentType(_ type: OUIDocument.Type) -> Bool {
        guard super.isSuitableDocumentType(type) else { return false }
        return OBClassImplementingMethod(type, #selector(OUIDocument.pngData)) != OUIDocument.self
    }
    
    public override func convert(document: OUIDocument, handler: @escaping (Result<[String : Data], Error>) -> Void) {
        do {
            let data = try document.pngData()
            handler(.success([kUTTypePNG as String:data]))
        } catch let err {
            handler(.failure(err))
        }
    }
    
    public override func finalize(results: [[String : Data]], completionHandler: @escaping (Error?) -> Void) {
        UIPasteboard.general.items = results
        completionHandler(nil)
    }

    // we don't need to present any UI and this creates a shadow that looks weird without any views, if it's non-nil
    public override func makeProcessingViewController() -> UIViewController? {
        return nil
    }
}

extension OUIDocumentExporter {
    @objc public static var copyAsImageActivityType: UIActivity.ActivityType {
        return CopyAsImageActivity.activityType
    }
    @objc public func makeCopyAsImageActivity() -> UIActivity {
        return CopyAsImageActivity()
    }
}

