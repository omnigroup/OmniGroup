// Copyright 2010-2022 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUINewDocumentCreationRequest.h"

#import <OmniUIDocument/OUIDocumentAppController.h>
#import <OmniUIDocument/OUIDocumentSceneDelegate.h>
#import <OmniUIDocument/OmniUIDocument-Swift.h>

@import UniformTypeIdentifiers.UTCoreTypes;
@import OmniFoundation;

NS_ASSUME_NONNULL_BEGIN

static NSString *PathExtensionForFileType(NSString *fileType, BOOL *outIsPackage)
{
    OBPRECONDITION(fileType);
    
    NSString *extension = OFPreferredPathExtensionForUTI(fileType);
    OBASSERT(extension);
    OBASSERT([extension hasPrefix:@"dyn."] == NO, "UTI not registered in the Info.plist?");
    
    if (outIsPackage) {
        BOOL isPackage = OFTypeConformsTo(fileType, UTTypePackage);
        OBASSERT_IF(!isPackage, !OFTypeConformsTo(fileType, UTTypeFolder), "Types should be declared as conforming to kUTTypePackage, not kUTTypeFolder");
        *outIsPackage = isPackage;
    }
    
    return extension;
}

@interface OUINewDocumentCreationRequest ()
@end

@implementation OUINewDocumentCreationRequest
{
    __weak id <OUIDocumentCreationRequestDelegate> _weak_delegate;
    __weak UIViewController *_parentViewController;
    void (^_creationHandler)(NSURL *_Nullable urlToImport, UIDocumentBrowserImportMode importMode);
    UINavigationController *_navigationController;
}

- (instancetype)initWithDelegate:(id <OUIDocumentCreationRequestDelegate>)delegate viewController:(UIViewController *)parentViewController creationHandler:(void(^)(NSURL *_Nullable urlToImport, UIDocumentBrowserImportMode importMode))creationHandler;
{
    _weak_delegate = delegate;
    _parentViewController = parentViewController;
    _creationHandler = [creationHandler copy];
    
    return self;
}

- (void)runWithInternalTemplateDelegate:(nullable id <OUIInternalTemplateDelegate>)internalTemplateDelegate;
{
    [OUIDocumentAppController.controller unlockCreateNewDocumentInViewController:_parentViewController withCompletionHandler:^(BOOL isUnlocked) {
        // Stay alive until a template is picked or cancelled.
        OBStrongRetain(self);

        if (isUnlocked) {
            [self _runWithInternalTemplateDelegate:internalTemplateDelegate];
        } else {
            [self _finishedWithURL:nil error:nil completion:nil];
        }
    }];
}

- (void)_runWithInternalTemplateDelegate:(nullable id <OUIInternalTemplateDelegate>)internalTemplateDelegate;
{
    OBPRECONDITION(OUIDocumentAppController.controller.canCreateNewDocument); // We tested this already

    // Use a template picker if the internalTemplateDelegate is set
    if (internalTemplateDelegate != nil && [internalTemplateDelegate shouldUseTemplatePicker]) {
        OUITemplatePicker *viewController = [OUITemplatePicker newTemplatePicker];
        viewController.modalInPresentation = YES;
        viewController.navigationTitle = NSLocalizedStringWithDefaultValue(@"ouiTemplatePicker.navigationTitle", @"OmniUIDocument", OMNI_BUNDLE, @"Choose a Template", @"Navigation bar title: Choose a Template");
        viewController.internalTemplateDelegate = internalTemplateDelegate;
        viewController.templateDelegate = self;
        viewController.wantsLanguageButton = [internalTemplateDelegate wantsLanguageButton];
        // TODO: fix to support animations
        _navigationController = [[OUINavigationController alloc] initWithRootViewController:viewController];
        [_parentViewController presentViewController:_navigationController animated:YES completion:nil];
        
        return;
    }

    // Create a document w/o using a template.
    [self _newDocumentWithCompletionHandler:nil];
}

- (void)_finishedWithURL:(nullable NSURL *)fileURL error:(nullable NSError *)error completion:(void (^ _Nullable)(void))completion;
{
    completion = [completion copy];
    
    void (^finished)(void) = [^{
        if (fileURL != nil) {
            _creationHandler(fileURL, UIDocumentBrowserImportModeMove);
        } else {
            _creationHandler(nil, UIDocumentBrowserImportModeNone);
        }
        _creationHandler = nil;
        OBAutorelease(self);

        if (error != nil) {
            OUI_PRESENT_ERROR_FROM(error, _parentViewController);
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
    
    [OUIDocumentAppController.controller unlockCreateNewDocumentInViewController:_parentViewController withCompletionHandler:^(BOOL isUnlocked) {
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
    NSURL *temporaryURL = [self temporaryURLForCreatingNewDocumentNamed:documentName];

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
                document = [[cls alloc] initWithContentsOfTemplateAtURL:newURL toBeSavedToURL:temporaryURL activityViewController:context.activityViewController error:outError];
                [securedURL stopAccessingSecurityScopedResource];
                return (document != nil);
            }];
        } else {
            NSURL *blankURL = [cls builtInBlankTemplateURL]; // No coordination here since if this is non-nil it should be in the app wrapper.
            OBASSERT_IF(blankURL != nil, OFURLContainsURL([[NSBundle mainBundle] bundleURL], blankURL));
            document = [[cls alloc] initWithContentsOfTemplateAtURL:blankURL toBeSavedToURL:temporaryURL activityViewController:context.activityViewController error:&readError];
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

- (void)_newDocumentWithCompletionHandler:(void (^ _Nullable)(void))completion;
{
    OUINewDocumentCreationContext *context = [[OUINewDocumentCreationContext alloc] initWithTemplateURL:nil documentName:nil animateFromView:nil];

    [self newDocumentWithContext:context completion:completion];
}

- (nullable NSString *)documentTypeForNewFiles;
{
    id <OUIDocumentCreationRequestDelegate> delegate = _weak_delegate;

    if ([delegate respondsToSelector:@selector(documentCreationRequestDocumentTypeForNewFiles:)])
        return [delegate documentCreationRequestDocumentTypeForNewFiles:self];

    if ([delegate respondsToSelector:@selector(documentCreationRequestEditableDocumentTypes:)]) {
        NSArray *editableTypes = [delegate documentCreationRequestEditableDocumentTypes:self];

        OBASSERT([editableTypes count] < 2); // If there is more than one, we might pick the wrong one.

        return [editableTypes lastObject];
    }

    return nil;
}

- (nullable NSURL *)temporaryURLForCreatingNewDocumentNamed:(nullable NSString *)documentName;
{
    BOOL isDirectory;
    NSString *documentType = [self documentTypeForNewFiles];
    if (!documentType) {
        return nil;
    }
    
    if (OFIsEmptyString(documentName)) {
        documentName = OUIDocumentSceneDelegate.defaultBaseNameForNewDocuments;
    }
    
    NSString *pathExtension = PathExtensionForFileType(documentType, &isDirectory);
    
    NSString *temporaryFilename = [documentName stringByAppendingPathExtension:pathExtension];
    return [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:temporaryFilename] isDirectory:isDirectory];
}

#pragma mark - OUITemplatePickerDelegate

- (void)templatePicker:(OUITemplatePicker *)templatePicker didSelectTemplateURL:(NSURL *)templateURL animateFrom:(UIView *)animateFrom;
{
    OUINewDocumentCreationContext *context = [[OUINewDocumentCreationContext alloc] initWithTemplateURL:templateURL documentName:nil animateFromView:nil];
    context.activityViewController = templatePicker;
    [self _newDocumentWithContext:context completion:nil];
}

- (void)templatePickerDidCancel:(OUITemplatePicker *)templatePicker;
{
    [self _finishedWithURL:nil error:nil completion:nil];
}

- (NSArray<NSString *> *)templateUTIs;
{
    id <OUIDocumentCreationRequestDelegate> delegate = _weak_delegate;
//    if ([delegate respondsToSelector:@selector(templateUTIs)]) {
//        return [delegate templateUTIs];
   if ([delegate respondsToSelector:@selector(templateFileTypes)]) {
        return [delegate performSelector:@selector(templateFileTypes)];
    } else {
        return @[];
    }
}

@end

NS_ASSUME_NONNULL_END

