// Copyright 2015-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

import Foundation
import UIKit

// A UIActivity class that accepts file URLs mapping to a given document type and sequentially processes them.

open class URLProcessingActivity : UIActivity {
    
    private(set) var fileURLs = [URL]()
    private var nextFileIndex = 0

    open func isSuitableURL(_ url: URL) -> Bool {
        fatalError("Subclasses must override")
    }
    
    // This is useful for subclasses that provide a view controller, in which case the `perform()` function is not called. Subclasses can then choose to call this from their `prepare(withActivityItems:)` or possibly from the view controller when it is presented.
    open func startProcessing() {
        processNextURL()
    }
    
    // Called once all the inputs are processed. The default implementation finishes the activity. Subclasses can continue doing work and call this later.
    open func finishedProcessing(_ completed: Bool) {
        OperationQueue.main.addOperation {
            self.activityDidFinish(completed)
        }
    }
    
    // MARK:- UIActivity subclass
    
    open override func canPerform(withActivityItems activityItems: [Any]) -> Bool {
        return !suitableURLs(items: activityItems).isEmpty
    }
    
    open override func prepare(withActivityItems activityItems: [Any]) {
        // We can end up getting re-used since sometimes when we call activityDidFinish() the activity view controller is not dismissed.
        fileURLs = suitableURLs(items: activityItems)
        nextFileIndex = 0
    }
    
    open override func perform() {
        processNextURL()
    }
    
    // MARK:- Subclass responsibility

    open func process(url: URL, completionHandler: @escaping () -> Void) {
        fatalError("Subclasses must override")
    }

    // MARK:- Private
    
    private func suitableURLs(items: [Any]) -> [URL] {
        return items.compactMap { item in
            guard let url = item as? URL else { return nil }
            return isSuitableURL(url) ? url : nil
        }
    }
    
    private func processNextURL() {
        dispatchPrecondition(condition: .onQueue(.main))
        
        guard nextFileIndex < fileURLs.count else {
            finishedProcessing(true)
            return
        }
        
        let fileURL = fileURLs[nextFileIndex]
        nextFileIndex += 1
        
        process(url: fileURL) {
            self.processNextURL()
        }
    }
}

open class DocumentProcessingActivity<DocumentType: OUIDocument> : URLProcessingActivity {

    // This will be invoked from prepare(withActivityItems:) and the result will be returned as the activityViewController.
    open func makeProcessingViewController() -> UIViewController? {
        // Default to a vanilla view controller that other view controllers can be presented atop.
        return OUIWrappingViewController()
    }

    // MARK:- URLProcessingActivity subclass
    
    open override func isSuitableURL(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        guard let documentClass = OUIDocumentAppController.shared().documentClass(for: url) else { return false }
        guard let cls = documentClass as? DocumentType.Type else { return false }
        return isSuitableDocumentType(cls)
    }
    
    open func isSuitableDocumentType(_ type: DocumentType.Type) -> Bool {
        return true
    }
    
    // MARK:- Subclass responsibility

    open func process(document: DocumentType, completionHandler: @escaping () -> Void) {
        fatalError("Subclasses must override")
    }
    
    // MARK:- URLProcessingActivity subclass
    
    open override func process(url: URL, completionHandler: @escaping () -> Void) {
        guard let documentType = OUIDocumentAppController.shared().documentClass(for: url) as? DocumentType.Type else {
            assertionFailure("Should have been filtered out already")
            completionHandler()
            return
        }
        
        // TODO: Allow passing already open documents to avoid opening a second copy if we are exporting from an open document? The system UIActivity classes would probably be unamused and we'd need to add the fileURL too (and then here we'd need to unique them).
        let document: DocumentType
        do {
            document = try documentType.init(existingFileURL: url)
            document.activityViewController = processingViewController
        } catch let err {
            // TODO: Capture errors and report them somewhere?
            print("Error creating document for \(url): \(err)")
            completionHandler()
            return
        }
        
        // Let the document know it can avoid work that isn't needed if the document isn't going to be presented to the user to edit.
        document.forExportOnly = true
        
        document.open { success in
            dispatchPrecondition(condition: .onQueue(.main))

            guard success else {
                completionHandler()
                return
            }
            
            self.process(document: document) {
                dispatchPrecondition(condition: .onQueue(.main))

                document.close { success in
                    assert(success)
                }
                
                completionHandler() // if you try to close a document that has been closed already, it won't call the completion handler, which is why this happens afterwards. the completion here isn't dependent on the document's closing being done, so this shouldn't be a problem.

            }
        }
    }

    // MARK:- UIActivity subclass

    // Some subclasses may need a view controller to provide details on opening documents (for example, a passphrase for decryption)

    public var processingViewController: UIViewController?

    public override func prepare(withActivityItems activityItems: [Any]) {
        super.prepare(withActivityItems: activityItems)

        if processingViewController == nil {
            processingViewController = makeProcessingViewController()
        }

        if processingViewController != nil {
            // The regular `perform()` function won't be called since we provide a view controller.
            startProcessing()
        }
    }

    public override var activityViewController: UIViewController? {
        return processingViewController
    }

}

// A document processing activity that converts the document to a different content type and collects the results.

open class DocumentConversionActivity<DocumentType: OUIDocument, OutputType> : DocumentProcessingActivity<DocumentType> {
    
    public typealias ResultHandler = (Result<OutputType, Error>) -> Void

    private(set) var results = [OutputType]()
        
    
    // MARK:- UIActivity subclass

    open override func prepare(withActivityItems activityItems: [Any]) {
        results = []
        super.prepare(withActivityItems: activityItems)
    }
        
    // MARK:- DocumentProcessingActivity subclass
    
    public override func finishedProcessing(_ completed: Bool) {
        if completed && !results.isEmpty {
            finalize(results: results) { error in
                if let error: NSError = error as NSError? {
                    OperationQueue.main.addOperation {
                        if let activityVC = self.activityViewController, let window = OUIAppController.window(for: activityVC.containingScene, options: [])  {
                            let rootViewController = window.rootViewController;

                            let isPermissionError = error.hasUnderlyingErrorDomain(OUIDocumentErrorDomain, code: 3) //OUIDocumentErrorPhotoLibraryAccessRestrictedOrDenied

                            var actionTitle: String? = nil
                            var action: ((OUIExtendedAlertAction) -> Void)? = nil

                            if (isPermissionError) {
                                actionTitle = "Show Settings"
                                action = { (action: OUIExtendedAlertAction) in
                                    if let openURL = URL(string: UIApplication.openSettingsURLString) {
                                        UIApplication.shared.open(openURL)
                                    }
                                    action.extendedActionComplete() // this is important, don't delete.
                                }
                            }

                            OUIAppController.presentError(error, from: rootViewController, cancelButtonTitle: "OK", optionalActionTitle: actionTitle, optionalAction: action) {
                                super.finishedProcessing(completed)
                            }

                        } else {
                            super.finishedProcessing(completed)
                        }
                    }
                } else {
                    super.finishedProcessing(completed)
                }
            }
        } else {
            super.finishedProcessing(completed)
        }
    }

    public override func process(document: DocumentType, completionHandler: @escaping () -> Void) {
        convert(document: document) { result in
            switch result {
            case .success(let output):
                self.results.append(output)
            case .failure(let error):
                OperationQueue.main.addOperation { // this case may need to look like above, but since i'm not sure how to invoke an error at this point, i'm not sure how to test.
                    OUIAppController.presentError(error)
                }
            }
            completionHandler()
        }
    }

    // MARK:- Subclass responsibility
    
    open func convert(document: DocumentType, handler: @escaping ResultHandler) {
        fatalError("Subclasses must override")
    }
    open func finalize(results: [OutputType], completionHandler: @escaping (Error?) -> Void) {
        fatalError("Subclasses must override")
    }

    // MARK:- Private
    
}

