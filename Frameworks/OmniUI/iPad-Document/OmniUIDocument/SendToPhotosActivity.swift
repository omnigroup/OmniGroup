// Copyright 2015-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

import Foundation
import Photos

public class SendToPhotosActivity : DocumentConversionActivity<OUIDocument, UIImage> {
            
    static let activityType = UIActivity.ActivityType("com.omnigroup.frameworks.OmniUIDocument.SendToPhotos")

    public override var activityType: UIActivity.ActivityType? {
        return type(of: self).activityType
    }

    public override var activityTitle: String? {
        return NSLocalizedString("Send to Photos", tableName: "OmniUIDocument", bundle: OmniUIDocumentBundle, comment: "Share option title")
    }
    
    public override var activityImage: UIImage? {
        return UIImage(systemName:"camera.fill")
    }
    
    public override func isSuitableDocumentType(_ type: OUIDocument.Type) -> Bool {
        guard super.isSuitableDocumentType(type) else { return false }
        return OBClassImplementingMethod(type, #selector(OUIDocument.pngData)) != OUIDocument.self
    }
    
    public override func convert(document: OUIDocument, handler: @escaping (Result<UIImage, Error>) -> Void) {
        do {
            let image = try document.cameraRolImage()
            handler(.success(image))
        } catch let err {
            handler(.failure(err))
        }
    }

    public override func finalize(results: [UIImage], completionHandler: @escaping (Error?) -> Void) {

        let attemptToSaveImage: (_ status: PHAuthorizationStatus) -> Void = { status in

            var error: Error? = nil
            switch status {
            case .restricted, .denied:
                // TODO: Where to display this? UIActivity doesn't provide a way to return an error or a guaranteed view controller to display on...
                let description = NSLocalizedString("Photo Library permission denied.", tableName: "OmniUIDocument", bundle: OmniUIDocumentBundle, comment: "Photo Library permisssions error description.")
                let suggestion = NSLocalizedString("This app does not have access to your Photo Library.", tableName: "OmniUIDocument", bundle: OmniUIDocumentBundle, comment: "Photo Library permisssions error suggestion.")
                error = OUIDocumentError(.photoLibraryAccessRestrictedOrDenied, userInfo: [NSLocalizedDescriptionKey: description, NSLocalizedRecoverySuggestionErrorKey: suggestion])
            default:
                for image in results {
                    UIImageWriteToSavedPhotosAlbum(image, self, #selector(SendToPhotosActivity.writeToPhotos(image:didFinishSavingWithError:contextInfo:)), nil)
                }
            }
            completionHandler(error)
        }

        let status = PHPhotoLibrary.authorizationStatus()
        switch status {
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(attemptToSaveImage)
        default:
            attemptToSaveImage(status)
        }
    }

    public override func makeProcessingViewController() -> UIViewController? {
        return nil
    }
    
    // MARK:- Private
    
    @objc private func writeToPhotos(image: UIImage, didFinishSavingWithError error: NSError?, contextInfo: UnsafeMutableRawPointer?) {
        if let error = error {
            assertionFailure("Error saving to photo library: \(error)")
        }
    }
}

extension OUIDocumentExporter {
    @objc public static var sendToPhotosActivityType: UIActivity.ActivityType {
        return SendToPhotosActivity.activityType
    }
    @objc public func makeSendToPhotosActivity() -> UIActivity {
        return SendToPhotosActivity()
    }
}

