// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUINewDocumentCreationRequest.h"

#import <OmniUIDocument/OUIDocumentAppController.h>
#import <OmniUIDocument/OmniUIDocument-Swift.h>

@import OmniFoundation;

NS_ASSUME_NONNULL_BEGIN

static NSString *PathExtensionForFileType(NSString *fileType, BOOL *outIsPackage)
{
    OBPRECONDITION(fileType);
    
    NSString *extension = OFPreferredPathExtensionForUTI(fileType);
    OBASSERT(extension);
    OBASSERT([extension hasPrefix:@"dyn."] == NO, "UTI not registered in the Info.plist?");
    
    if (outIsPackage) {
        BOOL isPackage = OFTypeConformsTo(fileType, kUTTypePackage);
        OBASSERT_IF(!isPackage, !OFTypeConformsTo(fileType, kUTTypeFolder), "Types should be declared as conforming to kUTTypePackage, not kUTTypeFolder");
        *outIsPackage = isPackage;
    }
    
    return extension;
}

@implementation OUINewDocumentCreationRequest
{
    __weak id <OUIDocumentCreationRequestDelegate> _weak_delegate;
    void (^_creationHandler)(NSURL *_Nullable urlToImport, UIDocumentBrowserImportMode importMode);
    UINavigationController *_navigationController;
}

- initWithDelegate:(id <OUIDocumentCreationRequestDelegate>)delegate creationHandler:(void(^)(NSURL *_Nullable urlToImport, UIDocumentBrowserImportMode importMode))creationHandler;
{
    _weak_delegate = delegate;
    _creationHandler = [creationHandler copy];
    
    return self;
}

- (void)runWithViewController:(UIViewController *)parentViewController internalTemplateDelegate:(nullable id <OUIInternalTemplateDelegate>)internalTemplateDelegate;
{
    [OUIDocumentAppController.controller unlockCreateNewDocumentWithCompletion:^(BOOL isUnlocked) {
        if (isUnlocked) {
            [self _runWithViewController:parentViewController internalTemplateDelegate:internalTemplateDelegate];
        } else {
            [self _finishedWithURL:nil error:nil completion:nil];
        }
    }];
}

- (void)_runWithViewController:(UIViewController *)parentViewController internalTemplateDelegate:(nullable id <OUIInternalTemplateDelegate>)internalTemplateDelegate;
{
    if (!OUIDocumentAppController.controller.canCreateNewDocument)
        return;

    // Stay alive until a template is picked or cancelled.
    OBStrongRetain(self);
    
    // Use the new template picker if the internalTemplateDelegate is set
    if (internalTemplateDelegate != nil) {
        UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"OUITemplatePicker" bundle:OMNI_BUNDLE];
        OUITemplatePicker *viewController = (OUITemplatePicker *)[storyboard instantiateViewControllerWithIdentifier:@"templatePicker"];
        viewController.modalInPresentation = YES;
        viewController.navigationTitle = NSLocalizedStringWithDefaultValue(@"ouiTemplatePicker.navigationTitle", @"OmniUIDocument", OMNI_BUNDLE, @"Choose a Template", @"Navigation bar title: Choose a Template");
        viewController.internalTemplateDelegate = internalTemplateDelegate;
        viewController.templateDelegate = self;
        
        // TODO: fix to support animations
        _navigationController = [[UINavigationController alloc] initWithRootViewController:viewController];
        [parentViewController presentViewController:_navigationController animated:YES completion:nil];
        
        return;
    }

    OBFinishPortingLater("Add support for picking a template from a list of resources (or switch other apps to use the above");
#if 0
    ODSDocumentType type = [self documentTypeForCurrentFilter];

    // Use old style template picker if delegate implements documentPickerTemplateDocumentFilter:
    id <OUIDocumentPickerDelegate> delegate = _documentPicker.delegate;
    if ([delegate respondsToSelector:@selector(documentPickerTemplateDocumentFilter:)]) {
        OBASSERT([delegate documentPickerTemplateDocumentFilter:_documentPicker], @"Need to provide an actual filter for templates if you expect to use the template picker for new documents");

        OUIDocumentCreationTemplatePickerViewController *templateChooser = [[OUIDocumentCreationTemplatePickerViewController alloc] initWithDocumentPicker:_documentPicker folderItem:_folderItem documentType:type];
        templateChooser.isReadOnly = YES;
        [parentViewController pushViewController:templateChooser animated:YES];
    } else
#endif
    {
        // Create a document w/o using a template.
        [self newDocumentWithDocumentType:ODSDocumentTypeNormal preserveDocumentName:NO completion:nil];
    }
}

- (void)_finishedWithURL:(nullable NSURL *)fileURL error:(nullable NSError *)error completion:(void (^ _Nullable)(void))completion;
{
    completion = [completion copy];
    
    void (^finished)(void) = [^{
        if (fileURL) {
            _creationHandler(fileURL, UIDocumentBrowserImportModeMove);
        } else {
            _creationHandler(nil, UIDocumentBrowserImportModeNone);
        }
        _creationHandler = nil;
        OBAutorelease(self);

        if (error) {
            OBFinishPortingWithNote("<bug:///176686> (Frameworks-iOS Unassigned: OBFinishPorting: Display errors when creating new document)");
        }
        
        if (completion) {
            completion();
        }
    } copy];
    
    if (_navigationController) {
        [_navigationController dismissViewControllerAnimated:YES completion:^{
            finished();
            _navigationController = nil;
        }];
    } else {
        // Creating from a nil template.
        finished();
    }
}

- (void)newDocumentWithContext:(OUINewDocumentCreationContext *)context completion:(void (^ _Nullable)(void))completion;
{
    completion = [completion copy];
    
    [OUIDocumentAppController.controller unlockCreateNewDocumentWithCompletion:^(BOOL isUnlocked) {
        if (isUnlocked) {
            [self _newDocumentWithContext:context completion:completion];
        } else {
            [self _finishedWithURL:nil error:nil completion:completion];
        }
    }];
}

- (void)_newDocumentWithContext:(OUINewDocumentCreationContext *)context completion:(void (^ _Nullable)(void))completion;
{
    completion = [completion copy];
    
    if (!OUIDocumentAppController.controller.canCreateNewDocument) {
        if (completion != NULL)
            completion();
        return;
    }

    OBFinishPortingLater("May not need this UI lock any more");
    OUIInteractionLock *lock = [OUIInteractionLock applicationLock];

    ODSDocumentType type = context.documentType;
    NSURL *templateURL = context.templateURL;
    NSString *documentName = context.documentName;
    //UIView *animateFromView = context.animateFromView;

    OBFinishPortingLater("show activity");
    OUIActivityIndicator *activityIndicator = nil;
//    if (animateFromView) {
//        activityIndicator = [OUIActivityIndicator showActivityIndicatorInView:animateFromView withColor:UIColor.whiteColor bezelColor:[UIColor.darkGrayColor colorWithAlphaComponent:0.9]];
//    } else {
//        UIView *view = _documentPicker.navigationController.topViewController.view;
//        activityIndicator = [OUIActivityIndicator showActivityIndicatorInView:view withColor:UIColor.whiteColor];
//    }

    // Instead of duplicating the template file item's URL (if we have one), we always read it into a OUIDocument and save it out, letting the document know that this is for the purposes of instantiating a new document. The OUIDocument may do extra work in this case that wouldn't get done if we just cloned the file (and this lets the work be done atomically by saving the new file to a temporary location before moving to a visible location).
    NSURL *temporaryURL = [self temporaryURLForCreatingNewDocumentNamed:documentName withType:type];

    completion = [completion copy];
    void (^cleanup)(void) = [^{
        [activityIndicator hide];
        [lock unlock];
    } copy];

    void (^finish)(NSURL *, NSError *) = [^(NSURL *createdFileURL, NSError *error) {
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            [self _finishedWithURL:createdFileURL error:error completion:completion];
            cleanup();
        }];
    } copy];
    
    OBFinishPortingLater("Record the creation user activity");
    // Let the app controller know we're about to create a new document
    // [[OUIDocumentAppController controller] documentPickerViewController:self willCreateNewDocumentFromTemplateAtURL:templateURL inStore:documentStore];

    NSOperationQueue *queue = [[NSOperationQueue alloc] init];
    [queue addOperationWithBlock:^{
        OUIDocumentAppController *controller = [OUIDocumentAppController controller];
        Class cls = [controller documentClassForURL:temporaryURL];

        // This reads the document immediately, which is why we dispatch to a background queue before calling it. We do file coordination on behalf of the document here since we don't get the benefit of UIDocument's efforts during our synchronous read.

        __block OUIDocument *document;
        __autoreleasing NSError *readError;

        if (templateURL != nil) {
            NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
            [coordinator readItemAtURL:templateURL withChanges:YES error:&readError byAccessor:^BOOL(NSURL *newURL, NSError **outError) {
                NSURL *securedURL = nil;
                if ([newURL startAccessingSecurityScopedResource])
                    securedURL = newURL;
                document = [[cls alloc] initWithContentsOfTemplateAtURL:newURL toBeSavedToURL:temporaryURL error:outError];
                [securedURL stopAccessingSecurityScopedResource];
                return (document != nil);
            }];
        } else {
            NSURL *blankURL = [cls builtInBlankTemplateURL]; // No coordination here since if this is non-nil it should be in the app wrapper.
            OBASSERT_IF(blankURL != nil, OFURLContainsURL([[NSBundle mainBundle] bundleURL], blankURL));
            document = [[cls alloc] initWithContentsOfTemplateAtURL:blankURL toBeSavedToURL:temporaryURL error:&readError];
        }

        if (!document) {
            finish(nil, readError);
            return;
        }

        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            // Save the document to our temporary location
            [document saveToURL:document.fileURL forSaveOperation:UIDocumentSaveForOverwriting completionHandler:^(BOOL saveSuccess){
                // The save completion handler isn't called on the main thread; jump over *there* to start the close (subclasses want that).
                [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                    [document closeWithCompletionHandler:^(BOOL closeSuccess){
                        [document didClose];

                        if (!saveSuccess) {
                            // The document instance should have gotten the real error presented some other way
                            NSError *cancelledError = [NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError userInfo:nil];
                            finish(nil, cancelledError);
                            return;
                        }

                        finish(temporaryURL, nil);
                    }];
                }];
            }];
        }];
    }];
}

- (void)newDocumentWithDocumentType:(ODSDocumentType)type preserveDocumentName:(BOOL)preserveDocumentName completion:(void (^ _Nullable)(void))completion;
{
    if (preserveDocumentName) {
        OBFinishPortingWithNote("<bug:///176687> (Frameworks-iOS Unassigned: OBFinishPorting: Handle the preserveDocumentName argument in OUINewDocumentCreationRequest)");
    }
    //NSString *documentName = preserveDocumentName ? templateFileItem.name : nil;

    OUINewDocumentCreationContext *context = [[OUINewDocumentCreationContext alloc] initWithDocumentType:ODSDocumentTypeNormal templateURL:nil documentName:nil animateFromView:nil];

    [self newDocumentWithContext:context completion:completion];
}

//- (void)newDocumentWithTemplateFileItem:(ODSFileItem *)templateFileItem documentType:(ODSDocumentType)type completion:(void (^ _Nullable)(void))completion;
//{
//    [self newDocumentWithTemplateFileItem:templateFileItem documentType:type preserveDocumentName:NO completion:completion];
//}
//
//- (void)newDocumentWithTemplateFileItem:(ODSFileItem *)templateFileItem;
//{
//    [self newDocumentWithTemplateFileItem:templateFileItem documentType:ODSDocumentTypeNormal completion:NULL];
//}

- (nullable NSString *)documentTypeForNewFilesOfType:(ODSDocumentType)type;
{
    id <OUIDocumentCreationRequestDelegate> delegate = _weak_delegate;

    switch (type) {
        case ODSDocumentTypeNormal:
            if ([delegate respondsToSelector:@selector(documentCreationRequestDocumentTypeForNewFiles:)])
                return [delegate documentCreationRequestDocumentTypeForNewFiles:self];
            break;
        case ODSDocumentTypeTemplate:
            if ([delegate respondsToSelector:@selector(documentCreationRequestDocumentTypeForNewTemplateFiles:)])
                return [delegate documentCreationRequestDocumentTypeForNewTemplateFiles:self];
            break;
        case ODSDocumentTypeOther:
            if ([delegate respondsToSelector:@selector(documentCreationRequestDocumentTypeForNewOtherFiles:)])
                return [delegate documentCreationRequestDocumentTypeForNewOtherFiles:self];
            break;
        default:
            OBFinishPortingLater("Is there a new document type we don't know about?");
            break;
    }

    if ([delegate respondsToSelector:@selector(documentCreationRequestEditableDocumentTypes:)]) {
        NSArray *editableTypes = [delegate documentCreationRequestEditableDocumentTypes:self];

        OBASSERT([editableTypes count] < 2); // If there is more than one, we might pick the wrong one.

        return [editableTypes lastObject];
    }

    return nil;
}


- (NSString *)documentTypeForNewFiles;
{
    return [self documentTypeForNewFilesOfType:ODSDocumentTypeNormal];
}

- (NSURL *)temporaryURLForCreatingNewDocumentNamed:(NSString *)documentName withType:(ODSDocumentType)type;
{
    BOOL isDirectory;
    NSString *documentType = [self documentTypeForNewFilesOfType:type];
    if (!documentType) {
        return nil;
    }
    
    if (OFIsEmptyString(documentName)) {
        documentName = @"My Document";
    }
    
    NSString *pathExtension = PathExtensionForFileType(documentType, &isDirectory);
    
    NSString *temporaryFilename = [documentName stringByAppendingPathExtension:pathExtension];
    return [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:temporaryFilename] isDirectory:isDirectory];
}

#pragma mark - OUITemplatePickerDelegate

+ (NSArray <OUITemplateItem *> *)_generalTemplatesInTemplatePicker:(OUITemplatePicker *)templatePicker {
    OBFinishPortingLater("Find templates");
    return @[];
        /*
        var items = [OUITemplateItem]()
        if let templateChooser = OUIDocumentCreationTemplatePickerViewController(documentPicker: templatePicker.documentPicker, folderItem: templatePicker.folderItem, documentType: OUIDocumentPickerViewController.documentTypeForCurrentFilter(with: templatePicker.documentPicker)) {
            templateChooser.isReadOnly = true
            templateChooser.selectedFilterChanged()

            if let fileItems = templateChooser.sortedFilteredItems() {
                for fileItem in fileItems {
                    if let fileEdit = fileItem.fileEdit {
                        let templateItem = OUITemplateItem(fileURL: fileItem.fileURL, fileEdit: fileEdit, displayName: fileItem.name())
                        items.append(templateItem)
                    }
                }
            }
        }

        return items
 */
 }

- (NSArray<OUITemplateItem *> *)generalTemplatesInTemplatePicker:(OUITemplatePicker *)templatePicker;
{
    return [[self class] _generalTemplatesInTemplatePicker:templatePicker];
}

- (void)templatePicker:(OUITemplatePicker *)templatePicker didSelectTemplateURL:(NSURL *)templateURL animateFrom:(UIView *)animateFrom;
{
    OUINewDocumentCreationContext *context = [[OUINewDocumentCreationContext alloc] initWithDocumentType:ODSDocumentTypeNormal templateURL:templateURL documentName:nil animateFromView:nil];
    [self _newDocumentWithContext:context completion:nil];
}

- (void)templatePickerDidCancel:(OUITemplatePicker *)templatePicker;
{
    [self _finishedWithURL:nil error:nil completion:nil];
}

@end

NS_ASSUME_NONNULL_END

