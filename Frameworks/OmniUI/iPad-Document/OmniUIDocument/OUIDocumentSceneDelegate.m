// Copyright 2019-2022 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUIDocument/OUIDocumentSceneDelegate.h>

@import UIKit;
@import OmniAppKit;
@import OmniFoundation;
@import OmniUI;

#import <OmniUIDocument/OUIDocument.h>
#import <OmniUIDocument/OUIDocumentAppController.h>
#import <OmniUIDocument/OUIDocumentViewController.h>
#import <OmniUIDocument/OUIServerAccountsViewController.h>
#import <OmniUIDocument/OmniUIDocument-Swift.h>

#import "OUIDocumentInbox.h"
#import "OUIDocumentOpenAnimator.h"
#import "OUIDocumentParameters.h"
#import "OUIDocumentSyncActivityObserver.h"
#import "OUINewDocumentCreationRequest.h"

@interface OUIDocumentBrowserViewController : UIDocumentBrowserViewController
@end

@implementation OUIDocumentBrowserViewController

- (BOOL)canPerformAction:(SEL)action withSender:(id)sender;
{
    BOOL rc = [super canPerformAction:action withSender:sender];
    if (!rc) {
        return NO;
    }

    // If we have an open document, reject all key commands for the document browser itself. Otherwise, they call get merged together.
    UIScene *scene = self.containingScene;
    if ([scene.delegate isKindOfClass:[OUIDocumentSceneDelegate class]]) {
        OUIDocumentSceneDelegate *delegate = (OUIDocumentSceneDelegate *)scene.delegate;
        if (delegate.document != nil) {
            return NO;
        }
    }

    // We used to check shouldBlockDocumentBrowserActions here, but there are many things that can be presented, and often the main view controller being presented is something general like a UINavigationController.
    UIViewController *presentedViewController = self.presentedViewController;
    if (presentedViewController) {
        return NO;
    }

    return rc;
}

@end

@interface OUIDocumentSceneDelegate ()
@property (nonatomic, strong) OUIAppControllerSceneHelper *sceneHelper;
@end

@implementation OUIDocumentSceneDelegate
{
    UIDocumentBrowserViewController *_documentBrowser;
    OUIDocumentExporter *_exporter;
    BOOL _isOpeningURL; // TODO: Evaluate whether we can get rid of this
    UIView *_snapshotForDocumentRebuilding;

    UIOpenURLContext *_specialURLContextToHandle;
}

static OFPreference *showFileExtensionsPreference;

+ (void)initialize;
{
    OBINITIALIZE;

    showFileExtensionsPreference = [OFPreference preferenceForKey:@"ShowFileExtensions" defaultValue:@(NO)];
    [OFPreference addObserverForPreference:showFileExtensionsPreference usingBlock:^(OFPreference * _Nonnull preference) {
        BOOL shouldShowFileExtensions = showFileExtensionsPreference.boolValue;
        NSArray <OUIDocumentSceneDelegate *> *sceneDelegates = [OUIDocumentSceneDelegate activeSceneDelegatesMatchingConditionBlock:^BOOL(OUIDocumentSceneDelegate * _Nonnull sceneDelegate) {
            return YES;
        }];
        for (OUIDocumentSceneDelegate *sceneDelegate in sceneDelegates) {
            sceneDelegate.documentBrowser.shouldShowFileExtensions = shouldShowFileExtensions;
        }
    }];
}

+ (nullable instancetype)documentSceneDelegateForView:(UIView *)view;
{
    UIWindow *window;
    if ([view isKindOfClass:[UIWindow class]]) {
        window = (UIWindow *)view; // We just checked the validity of this cast
    } else {
        window = view.window;
    }
    UIWindowScene *windowScene = window.windowScene;
    if (!windowScene)
        return nil;

    OUIDocumentSceneDelegate *delegate = OB_CHECKED_CAST(OUIDocumentSceneDelegate, windowScene.delegate);
    assert(delegate != nil);
    assert([delegate isKindOfClass:[OUIDocumentSceneDelegate class]]);
    return delegate;
}

+ (NSArray <OUIDocumentSceneDelegate *> *)activeSceneDelegatesMatchingConditionBlock:(BOOL (^)(OUIDocumentSceneDelegate *sceneDelegate))conditionBlock;
{
    NSMutableArray <OUIDocumentSceneDelegate *> *matchingDelegates = [[NSMutableArray alloc] init];
    [self activeSceneDelegatesPerformBlock:^(OUIDocumentSceneDelegate *documentSceneDelegate) {
        if (conditionBlock(documentSceneDelegate)) {
            [matchingDelegates addObject:documentSceneDelegate];
        }
    }];
    return matchingDelegates;
}

+ (void)activeSceneDelegatesPerformBlock:(void (^)(__kindof OUIDocumentSceneDelegate *sceneDelegate))actionBlock;
{
    NSSet <UIScene *> *connectedScenes = UIApplication.sharedApplication.connectedScenes;
    Class targetClass = [self class];
    for (UIScene *scene in connectedScenes) {
        id delegate = scene.delegate;
        if (![delegate isKindOfClass:targetClass])
            continue;
        OUIDocumentSceneDelegate *documentSceneDelegate = delegate;
        actionBlock(documentSceneDelegate);
    }

}

+ (NSArray <OUIDocumentSceneDelegate *> *)documentSceneDelegatesForDocument:(OUIDocument *)document;
{
    return [self activeSceneDelegatesMatchingConditionBlock:^BOOL(OUIDocumentSceneDelegate *sceneDelegate) {
        return sceneDelegate.document == document;
    }];
}

+ (NSArray <__kindof OUIDocument *> *)activeDocumentsOfClass:(Class)class;
{
    NSMutableArray <__kindof OUIDocument *> *results = [[NSMutableArray alloc] init];
    (void)[self activeSceneDelegatesMatchingConditionBlock:^BOOL(OUIDocumentSceneDelegate *sceneDelegate) {
        OUIDocument *document = sceneDelegate.document;
        if ([sceneDelegate.document isKindOfClass:class]) {
            [results addObjectIfAbsent:document];
        }
        return NO; // We don't actually need any scene delegates
    }];
    return results;
}

+ (NSString *)defaultBaseNameForNewDocuments;
{
    return NSLocalizedStringFromTableInBundle(@"My Document", @"OmniUIDocument", OMNI_BUNDLE, @"Default base name for a new document");
}

- (instancetype)init;
{
    return [super init];
}

- (UIWindowScene *)windowScene;
{
    return self.window.windowScene;
}

- (void)openDocumentInPlace:(NSURL *)url
{
    [self openDocumentInPlace:url completionHandler:nil];
}

- (void)openDocumentInPlace:(NSURL *)url completionHandler:(void (^ _Nullable)(OUIDocument * _Nullable document, NSError * _Nullable errorOrNil))completionHandler;
{
    [self _openDocumentAtURL:url completionHandler:completionHandler];
}

- (void)importDocumentFromURL:(NSURL *)fileURL;
{
    void (^finish)(OUIDocument *document) = [^(OUIDocument *document) {
        OBASSERT([NSThread isMainThread], "We need to be on the main thread to hide the activity indicator");

        if (!document) {
            return;
        }

        // Save the document to our temporary location
        [document saveToURL:document.fileURL forSaveOperation:UIDocumentSaveForOverwriting completionHandler:^(BOOL saveSuccess){
            // The save completion handler isn't called on the main thread; jump over *there* to start the close (subclasses want that).
            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                [document closeWithCompletionHandler:^(BOOL closeSuccess){
                    [document didClose];

                    if (!saveSuccess) {
                        return;
                    }

                    [self.documentBrowser importDocumentAtURL:document.fileURL nextToDocumentAtURL:fileURL mode:UIDocumentBrowserImportModeMove completionHandler:^(NSURL *importedURL, NSError *errorOrNil) {
                        if (importedURL) {
                            [self openDocumentInPlace:importedURL];
                        } else {
                            [OUIAppController presentError:errorOrNil fromViewController:self.documentBrowser];
                        }
                    }];
                }];
            }];
        }];
    } copy];

    OUIDocumentAppController *controller = [OUIDocumentAppController controller];
    OUINewDocumentCreationRequest *request = [[OUINewDocumentCreationRequest alloc] initWithDelegate:OB_CHECKED_CONFORM(OUIDocumentCreationRequestDelegate, controller) viewController:_documentBrowser creationHandler:^(NSURL *urlToImport, UIDocumentBrowserImportMode importMode){
        OBASSERT_NOT_REACHED("Not actually going to run this creation request");
    }];

    NSURL *temporaryURL = [request temporaryURLForCreatingNewDocumentNamed:[[fileURL lastPathComponent] stringByDeletingPathExtension]];

    OUIInteractionLock *lock = [OUIInteractionLock applicationLock];
    NSOperationQueue *queue = [[NSOperationQueue alloc] init];
    [queue addOperationWithBlock:^{
        Class cls = [controller documentClassForURL:fileURL];
        OBASSERT(OBClassIsSubclassOfClass(cls, [OUIDocument class]));

        // This reads the document immediately, which is why we dispatch to a background queue before calling it. We do file coordination on behalf of the document here since we don't get the benefit of UIDocument's efforts during our synchronous read.

        __autoreleasing NSError *readError;
        __block OUIDocument *document;

        NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
        BOOL securedURL = [fileURL startAccessingSecurityScopedResource];
        [coordinator readItemAtURL:fileURL withChanges:YES error:&readError byAccessor:^BOOL(NSURL *newURL, NSError **outError) {
            document = [[cls alloc] initWithContentsOfImportableFileAtURL:newURL toBeSavedToURL:temporaryURL error:outError];
            return (document != nil);
        }];
        if (securedURL) {
            [fileURL stopAccessingSecurityScopedResource];
        }

        if (document == nil) {
            __block NSError *reportableError = readError;
            OFMainThreadPerformBlock(^(void) {
                [OUIAppController presentError:reportableError fromViewController:self.documentBrowser];
            });
        }

        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            [lock unlock];
            finish(document);
        }];
    }];
}

- (NSUserActivity *)_createUserActivityForDocument:(OUIDocument *)document;
{
    NSURL *url = document.fileURL;
    if (url == nil)
        return nil;

    NSUserActivity *activity = [[NSUserActivity alloc] initWithActivityType:[OUIDocumentAppController.sharedController.class openDocumentUserActivityType]];
    NSString *localizedOpenFormatString = NSLocalizedStringFromTableInBundle(@"Open %@", @"OmniUIDocument", OMNI_BUNDLE, @"Open Document Shortcut Title");
    NSString *localizedFilename = nil;
    if (![url getResourceValue:&localizedFilename forKey:NSURLLocalizedNameKey error:NULL]) {
        localizedFilename = url.path.lastPathComponent.stringByDeletingPathExtension;
    }
    if (localizedOpenFormatString) {
        activity.title = [NSString stringWithFormat:localizedOpenFormatString, localizedFilename];
    }

    NSError *bookmarkError = nil;
    NSData *urlBookmark = [url bookmarkDataWithOptions:NSURLBookmarkCreationMinimalBookmark includingResourceValuesForKeys:nil relativeToURL:nil error:&bookmarkError];
    if (urlBookmark == nil) {
        NSLog(@"error creating bookmark from url %@ - %@", url, bookmarkError);
    } else {
        [activity addUserInfoEntriesFromDictionary:@{ OUIUserActivityUserInfoKeyBookmark : urlBookmark }];
        activity.requiredUserInfoKeys = [NSSet setWithObject:OUIUserActivityUserInfoKeyBookmark];
    }

    // Exposes us to Siri Shortcuts
    activity.eligibleForPrediction = YES;

    // Exposes us to Spotlight
    activity.eligibleForSearch = YES;

    // Makes us eligible for Handoff
    activity.eligibleForHandoff = YES;

    return activity;
}

- (void)_setDocument:(OUIDocument *)document;
{
    if (_document == document)
        return;

    if (_document != nil) {
        self.windowScene.title = nil;
        [self.userActivity resignCurrent];
        self.userActivity = nil;
        [[NSNotificationCenter defaultCenter] removeObserver:self name:UIDocumentStateChangedNotification object:_document];
        [_document didClose];
    }

    _document = document;

    if (document != nil) {
        self.userActivity = [self _createUserActivityForDocument:document];
        [self.userActivity becomeCurrent];
        self.windowScene.title = document.name;
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_documentStateChanged:) name:UIDocumentStateChangedNotification object:_document];
    } else {
        UISceneActivationState activationState = self.windowScene.activationState;
        switch (activationState) {
            case UISceneActivationStateForegroundActive:
            case UISceneActivationStateForegroundInactive:
                (void)[OUIAppController.sharedController showNewsInWindow:self.window];
            default:
                break;
        }
    }
}

- (void)_documentStateChanged:(NSNotification *)note;
{
    OBPRECONDITION([note object] == _document);

    UIDocumentState state = _document.documentState;
    OB_UNUSED_VALUE(state);

    DEBUG_DOCUMENT(@"State changed to %ld", state);
}

- (void)showOpenDocument:(OUIDocument *)document completionHandler:(void (^)(void))completionHandler;
{
    UIDocumentBrowserTransitionController *transitionController = [_documentBrowser transitionControllerForDocumentAtURL:document.fileURL];

    [self _showOpenDocument:document transitionController:transitionController completionHandler:completionHandler];
}

- (void)_showOpenDocument:(OUIDocument *)document transitionController:(UIDocumentBrowserTransitionController *)transitionController completionHandler:(void (^ _Nullable)(void))completionHandler;
{
    OBPRECONDITION([NSThread isMainThread]);

    [self _setDocument:document];

    UIViewController *presentFromViewController = _documentBrowser;
    UIViewController <OUIDocumentViewController> *documentViewController = _document.documentViewController;
    UIViewController *toPresent = _document.viewControllerToPresent;
    UIView *view = [documentViewController view]; // make sure the view is loaded in case -pickerAnimationViewForTarget: doesn't and return a subview thereof.

    [UIView performWithoutAnimation:^{
        [view setFrame:presentFromViewController.view.bounds];
        //[view layoutIfNeeded];  // this seems to be unnecessary and appears to screw up the initial positioning of the canvas
        // We shouldn't setup toPresent.view here, before it knows how it's going to display. We should wait for the presentation and adaptability mechanisms to cause layout.
        //        [toPresent.view setFrame:presentFromViewController.view.bounds];
        //        [toPresent.view layoutIfNeeded];
    }];

    // Wait until the document is opened to do this, which will let cache entries from opening document A be used in document B w/o being flushed.
    [OAFontDescriptor forgetUnusedInstances];

    // UIWindow will automatically create an undo manager if one isn't found along the responder chain. We want to be darn sure that don't end up getting two undo managers and accidentally splitting our registrations between them.
    OBASSERT([_document undoManager] == [_document.documentViewController undoManager], "bug:///144566 (Frameworks-iOS Unassigned: TextEditor sample app uses UITextView's undoManager for viewController's -undoManager)");
    OBASSERT([_document undoManager] == [_document.documentViewController.view undoManager], "bug:///144566 (Frameworks-iOS Unassigned: TextEditor sample app uses UITextView's undoManager for viewController's -undoManager)"); // Does your view controller implement -undoManager? We don't do this for you right now.

    OBFinishPortingLater("Figure out what to do with -restoreDocumentViewState:");
#if 0
    if ([documentViewController respondsToSelector:@selector(restoreDocumentViewState:)]) {
        OFFileEdit *fileEdit = fileItem.fileEdit;
        if (fileEdit) // New document
            [documentViewController restoreDocumentViewState:[OUIDocumentAppController documentStateForFileEdit:fileEdit]];
    }
#endif

    BOOL animateDocument = YES;
    UIWindow *window = self.window;
    if (window.rootViewController != _documentBrowser) {
        animateDocument = NO;
        window.rootViewController = _documentBrowser;
    }
    [window makeKeyAndVisible]; // Whenever we leave the document browser, make our window key (which doesn't always happen otherwise due to the interaction with the document browser's remote window)

    OUIDocumentOpenAnimator *animator = [[OUIDocumentOpenAnimator alloc] initWithTransitionController:transitionController];

    transitionController.targetView = documentViewController.documentOpenCloseTransitionView;

    OBASSERT_NOTNULL(toPresent);
    toPresent.transitioningDelegate = animator;
    toPresent.modalPresentationStyle = UIModalPresentationCustom;

    if (presentFromViewController.presentedViewController)
        [presentFromViewController dismissViewControllerAnimated:NO completion:^{}];

    completionHandler = [completionHandler copy];

    [presentFromViewController presentViewController:toPresent animated:animateDocument completion:^{
        [documentViewController becomeFirstResponder];
        if ([documentViewController respondsToSelector:@selector(documentFinishedOpening)])
            [documentViewController documentFinishedOpening];
        [document.applicationLock unlock];
        document.applicationLock = nil;

        // Ensure that when the document is closed we'll be using a filter that shows it.
        //                    [_documentPicker.selectedScopeViewController ensureSelectedFilterMatchesFileItem:fileItem];

        transitionController.targetView = nil;
        toPresent.transitioningDelegate = nil;

        [animator self]; // Make sure these sticks around until done
        [transitionController self];

        if (completionHandler) {
            completionHandler();
        }
    }];
}

- (void)_openDocumentAtURL:(NSURL *)fileURL completionHandler:(void (^)(OUIDocument *document, NSError *error))completion;
{
    OBPRECONDITION([NSThread isMainThread]);
    OBPRECONDITION(fileURL);

    __block void (^completionHandler)(OUIDocument *document, NSError *error) = [completion copy];

    if (OFISEQUAL(fileURL.path.pathExtension, @"omnipresence-config")) {
        OFXAgentActivity *agentActivity = OUIDocumentAppController.sharedController.agentActivity;
        OFXAgent *syncAgent = agentActivity.agent;
        OBASSERT(syncAgent != nil);
        [syncAgent afterAsynchronousOperationsFinish:^{
            [self _loadOmniPresenceConfigFileFromURL:fileURL];
            if (completionHandler != nil) {
                NSError *error = nil;
                OBUserCancelledError(&error);
                completionHandler(nil, error); // Not strictly an error, but we didn't produce a document
            }
        }];
        return;
    }

    OUIDocumentAppController *appController = OUIDocumentAppController.sharedController;
    [appController checkTemporaryLicensingStateInViewController:_documentBrowser withCompletionHandler:^{
        if (_document != nil && OFURLEqualsURL(_document.fileURL, fileURL)) {
            // The document we're supposed to open is already open. Let's not do anything, eh?
            if (completionHandler) {
                completionHandler(_document, nil);
            }
            return;
        }

        void (^onFail)(NSError *error) = ^(NSError *error){
            _isOpeningURL = NO;
            if (completionHandler) {
                completionHandler(nil, error);
            }
        };
        onFail = [onFail copy];

        void (^doOpen)(void) = ^{
            Class cls = [appController documentClassForURL:fileURL];
            OBASSERT(OBClassIsSubclassOfClass(cls, [OUIDocument class]));

            if ([cls shouldImportFileAtURL:fileURL]) {
                [self importDocumentFromURL:fileURL];
                return;
            }

            UIDocumentBrowserTransitionController *transitionController = [_documentBrowser transitionControllerForDocumentAtURL:fileURL];
            transitionController.loadingProgress = [[NSProgress alloc] init]; // TODO: Require documents to provide progress

            __autoreleasing NSError *error = nil;
            OUIDocument *document = [[cls alloc] initWithExistingFileURL:fileURL error:&error];

            if (!document) {
                OUI_PRESENT_ERROR_FROM(error, self.window.rootViewController);
                onFail(error);
                return;
            }

            document.applicationLock = [OUIInteractionLock applicationLock];

            [self _setDocument:document];

            [document openWithCompletionHandler:^(BOOL success){
                if (!success) {
                    [document.applicationLock unlock];
                    document.applicationLock = nil;

                    [self _setDocument:nil];

                    OBFinishPortingLater("Should OUIDocument capture the error it encountered while loading?");
                    NSError *openError;
                    OBUserCancelledError(&openError);
                    onFail(openError);

                    return;
                }

                OBASSERT([NSThread isMainThread]);
                _isOpeningURL = NO;

                [self _showOpenDocument:document transitionController:transitionController completionHandler:^{
                    if (completionHandler) {
                        completionHandler(document, nil);
                    }
                }];
            }];
        };

        if (_document) {
            // If we have a document open, wait for it to close before starting to open the new one. This can happen if the user backgrounds the app and then taps on a document in Mail or Files.

            doOpen = [doOpen copy];

            OBASSERT(_document.applicationLock == nil);
            _document.applicationLock = [OUIInteractionLock applicationLock];

            [_document closeWithCompletionHandler:^(BOOL success) {
                OUIDocument *localDoc = _document;

                [self _setDocument:nil];

                [_documentBrowser dismissViewControllerAnimated:YES completion:^{
                    doOpen();
                    [localDoc.applicationLock unlock];
                    localDoc.applicationLock = nil;
                }];
            }];
        } else {
            // Just open immediately
            doOpen();
        }
    }];
}

- (NSMutableSet *)_copyCurrentlyUsedFileNamesInFolderAtURL:(nullable NSURL *)folderURL ignoringFileURL:(NSURL *)fileURLToIgnore;
{
    if (!folderURL)
        folderURL = [self _documentsURL];

    NSMutableSet *usedFileNames = [[NSMutableSet alloc] init];

    fileURLToIgnore = [fileURLToIgnore URLByStandardizingPath];

    // <bug:///88352> (Need to deal with remotely defined package extensions when scanning our document store scopes)
    OFScanPathExtensionIsPackage isPackage = OFIsPackageWithKnownPackageExtensions(nil);
    OFScanDirectoryItemHandler itemHandler = ^(NSFileManager *fileManager, NSURL *fileURL){
        if (fileURLToIgnore && OFURLEqualsURL(fileURLToIgnore, [fileURL URLByStandardizingPath]))
            return;
        [usedFileNames addObject:[fileURL lastPathComponent]];
    };
    OFScanErrorHandler errorHandler = nil;

    OFScanDirectory(folderURL, NO/*shouldRecurse*/, OFScanDirectoryExcludeSytemFolderItemsFilter(), isPackage, itemHandler, errorHandler);

    return usedFileNames;
}

- (NSString *)_availableFileNameInFolderAtURL:(nullable NSURL *)folderURL withBaseName:(NSString *)baseName extension:(NSString *)extension counter:(NSUInteger *)ioCounter;
{
    NSSet *usedFileNames = [self _copyCurrentlyUsedFileNamesInFolderAtURL:folderURL ignoringFileURL:nil];
    NSString *fileName = [self _availableFileNameAvoidingUsedFileNames:usedFileNames withBaseName:baseName extension:extension counter:ioCounter];
    return fileName;
}

- (NSString *)_availableFileNameAvoidingUsedFileNames:(NSSet *)usedFileNames withBaseName:(NSString *)baseName extension:(NSString *)extension counter:(NSUInteger *)ioCounter;
{
    NSUInteger counter = *ioCounter; // starting counter

    while (YES) {
        NSString *candidateName;
        if (counter == 0) {
            candidateName = baseName;
            counter = 2; // First duplicate should be "Foo 2".
        } else {
            candidateName = [[NSString alloc] initWithFormat:@"%@ %lu", baseName, counter];
            counter++;
        }

        if (![NSString isEmptyString:extension]) { // Is nil when we are creating new folders
            OBASSERT_NOTNULL(extension);
            candidateName = [candidateName stringByAppendingPathExtension:extension];
        }

        // Not using -memeber: because it uses -isEqual: which was incorrectly returning nil with some Japanese filenames.
        NSString *matchedFileName = [usedFileNames any:^BOOL(id object) {
            NSString *usedFileName = (NSString *)object;
            if ([usedFileName localizedCaseInsensitiveCompare:candidateName] == NSOrderedSame) {
                return YES;
            }

            return NO;
        }];

        if (matchedFileName == nil) {
            *ioCounter = counter; // report how many we used
            return candidateName;
        }
    }
}

- (NSURL *)urlForNewDocumentInFolderAtURL:(nullable NSURL *)folderURL baseName:(nullable NSString *)baseName extension:(nullable NSString *)extension;
{
    NSUInteger counter = 0;

    NSURL *documentsURL = [self _documentsURL];
    if (folderURL == nil) {
        folderURL = documentsURL;
    } else {
        OBASSERT(OFURLContainsURL(documentsURL, folderURL));
    }

    if (baseName == nil) {
        baseName = OUIDocumentSceneDelegate.defaultBaseNameForNewDocuments;
    }

    if (extension == nil) {
        OUIDocumentAppController *controller = [OUIDocumentAppController controller];
        OUINewDocumentCreationRequest *request = [[OUINewDocumentCreationRequest alloc] initWithDelegate:OB_CHECKED_CONFORM(OUIDocumentCreationRequestDelegate, controller) viewController:_documentBrowser creationHandler:^(NSURL *urlToImport, UIDocumentBrowserImportMode importMode){
            OBASSERT_NOT_REACHED("Not actually going to run this creation request");
        }];

        NSURL *temporaryURL = [request temporaryURLForCreatingNewDocumentNamed:baseName];
        extension = temporaryURL.pathExtension;
    }

    NSString *availableFileName = [self _availableFileNameInFolderAtURL:folderURL withBaseName:baseName extension:extension counter:&counter];

    return [folderURL URLByAppendingPathComponent:availableFileName];
}

- (NSURL *)_documentsURL;
{
    return OUIDocumentAppController.sharedController.localDocumentsURL;
}

- (IBAction)makeNewDocument:(nullable id)sender;
{
    [self documentBrowser:_documentBrowser didRequestDocumentCreationWithHandler:^(NSURL * _Nullable urlToImport, UIDocumentBrowserImportMode importMode) {
        if (urlToImport == nil || importMode == UIDocumentBrowserImportModeNone)
            return;

        NSURL *targetURL = [self urlForNewDocumentInFolderAtURL:nil baseName:nil extension:urlToImport.pathExtension];
        BOOL success;
        NSError *error;
        switch (importMode) {
            case UIDocumentBrowserImportModeCopy:
                success = [NSFileManager.defaultManager copyItemAtURL:urlToImport toURL:targetURL error:&error];
                break;
            case UIDocumentBrowserImportModeMove:
                success = [NSFileManager.defaultManager moveItemAtURL:urlToImport toURL:targetURL error:&error];
                break;
            default:
                OBASSERT_NOT_REACHED("We already handled UIDocumentBrowserImportModeNone with a short-circuit");
        }
        if (!success) {
            OUI_PRESENT_ERROR_FROM(error, _documentBrowser);
            return;
        }
        [self openDocumentInPlace:targetURL];
    }];
}

- (IBAction)closeDocument:(nullable id)sender;
{
    if ([sender isKindOfClass:[UIKeyCommand class]] && [[UIMenuController sharedMenuController] isMenuVisible]) {
        [[UIMenuController sharedMenuController] hideMenu];
    }

    [self closeDocumentWithCompletionHandler:nil];
}

- (void)closeDocumentWithCompletionHandler:(void(^ _Nullable)(void))completionHandler;
{
    if (_document == nil) {
        if (_documentBrowser.presentedViewController) {
            [_documentBrowser dismissViewControllerAnimated:NO completion:completionHandler];
        } else if (completionHandler != nil) {
            completionHandler();
        }
        return;
    }

    completionHandler = [completionHandler copy]; // capture scope

    OUIWithoutAnimating(^{
        UIWindow *window = self.window;
        [window endEditing:YES];
        [window layoutIfNeeded];

        // Make sure -setNeedsDisplay calls (provoked by -endEditing:) have a chance to get flushed before we invalidate the document contents
        OUIDisplayNeededViews();
    });

    // Ending editing may have started opened an undo group, with the nested group stuff for autosave (see OUIDocument). Give the runloop a chance to close the nested group.
    if ([_document.undoManager groupingLevel] > 0) {
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate distantPast]];
        OBASSERT([_document.undoManager groupingLevel] == 0);
    }

    // Add Snapshot View
    UIView *viewToSave = _document.viewControllerToPresent.view;
    UIView *snapshotView = [viewToSave snapshotViewAfterScreenUpdates:NO];
    [viewToSave addSubview:snapshotView];

    // Add Closing Spinner
    UIActivityIndicatorView *closingDocumentIndicatorView = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    closingDocumentIndicatorView.color = viewToSave.window.tintColor;
    CGRect superviewBounds = viewToSave.bounds;
    closingDocumentIndicatorView.center = (CGPoint){
        .x = superviewBounds.size.width / 2,
        .y = superviewBounds.size.height / 2
    };
    [viewToSave addSubview:closingDocumentIndicatorView];
    [viewToSave bringSubviewToFront:closingDocumentIndicatorView];
    [closingDocumentIndicatorView startAnimating];


    UIDocumentBrowserTransitionController *transitionController = [_documentBrowser transitionControllerForDocumentAtURL:_document.fileURL];
    OUIDocumentOpenAnimator *animator = [[OUIDocumentOpenAnimator alloc] initWithTransitionController:transitionController];

    UIViewController <OUIDocumentViewController> *viewController = _document.documentViewController;
    UIViewController *toPresent = _document.viewControllerToPresent;

    transitionController.targetView = viewController.documentOpenCloseTransitionView;
    toPresent.transitioningDelegate = animator;

    _document.applicationLock = [OUIInteractionLock applicationLock];
    [_documentBrowser dismissViewControllerAnimated:YES completion:^{
        OBFinishPortingLater("Try to make sure the document is visible"); // This crashed when called here, so maybe need to reorder it or just stop.
        // [_documentBrowser revealDocumentAtURL:_document.fileURL importIfNeeded:NO completion:nil];

        transitionController.targetView = nil;
        toPresent.transitioningDelegate = nil;

        [animator self]; // Make sure these sticks around until done
        [transitionController self];

        OBExpectDeallocation(_document);
        OBStrongRetain(_document);
        [_document closeWithCompletionHandler:^(BOOL success) {
            [closingDocumentIndicatorView removeFromSuperview];

            // Give the document a chance to break retain cycles.
            [_document didClose];
            // self.launchAction = nil;

            // Doing the -autorelease in the completion handler wasn't late enough. This may not be either...
            OUIDocument *document = _document; // Don't race vs. _setDocument:nil below.
            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                OBASSERT([NSThread isMainThread]);
                OBStrongRelease(document);
            }];

            [_document.applicationLock unlock];
            _document.applicationLock = nil;

            [self _setDocument:nil];

            if (completionHandler)
                completionHandler();
        }];
    }];
}

- (void)revealURLInDocumentBrowser:(NSURL *)url completion:(nullable void(^)(NSURL * _Nullable revealedDocumentURL, NSError * _Nullable error))completion;
{
    // Workaround for reveal bug which appeared in iOS 13 beta 8, causing reveal to switch to Recents even though Recents might not contain the document you're trying to reveal
    NSURL *folderURL = [[url URLByStandardizingPath] URLByDeletingLastPathComponent];
    [self openFolder:folderURL];
}

- (void)_revealURLInDocumentBrowser:(NSURL *)url completion:(nullable void(^)(NSURL * _Nullable revealedDocumentURL, NSError * _Nullable error))completion;
{
    completion = [completion copy];
    [_documentBrowser revealDocumentAtURL:url importIfNeeded:NO completion:^(NSURL * _Nullable revealedDocumentURL, NSError * _Nullable revealErrorOrNil) {
#ifdef DEBUG_kc
        NSLog(@"Revealed document: %@ -> %@: error = %@", url.absoluteString, revealedDocumentURL.absoluteString, revealErrorOrNil.toPropertyList);
#endif
        if (completion != nil) {
            completion(revealedDocumentURL, revealErrorOrNil);
        }
    }];
}

- (void)openFolderForServerAccount:(OFXServerAccount *)account;
{
    [self openFolder:account.localDocumentsURL];
}

- (void)openFolder:(NSURL *)folderURL;
{
    NSFileManager *fileManager = NSFileManager.defaultManager;
    NSArray <NSURLResourceKey> *keys = @[NSURLIsDirectoryKey, NSURLIsPackageKey, NSURLIsHiddenKey];
    NSArray <NSURL *> *folderContents = [fileManager contentsOfDirectoryAtURL:folderURL includingPropertiesForKeys:keys options:0 error:nil];
    NSURL *childFolder = nil;
    for (NSURL *child in folderContents) {
        NSDictionary<NSURLResourceKey, id> *resourceValues = [child resourceValuesForKeys:keys error:NULL];
        if (resourceValues == nil)
            continue;
        if ([resourceValues boolForKey:NSURLIsDirectoryKey] && ![resourceValues boolForKey:NSURLIsPackageKey] && ![resourceValues boolForKey:NSURLIsHiddenKey]) {
            childFolder = child;
            break;
        }
    }

    BOOL shouldCreateTemporaryChild = childFolder == nil;
#ifdef DEBUG_kc
    NSLog(@"DEBUG: Should create temporary child: %@", @(shouldCreateTemporaryChild));
#endif
    if (shouldCreateTemporaryChild) {
        // The account is completely empty? Let's create a temporary folder to reveal, then remove it when we're done
        childFolder = [folderURL URLByAppendingPathComponent:@"                  "];
        if (![fileManager createDirectoryAtURL:childFolder withIntermediateDirectories:NO attributes:nil error:nil])
            shouldCreateTemporaryChild = NO; // Don't remove a folder unless we created it!
    }
    [self _revealURLInDocumentBrowser:childFolder completion:^(NSURL * _Nullable revealedDocumentURL, NSError * _Nullable error) {
        if (shouldCreateTemporaryChild) {
            // Now that our otherwise-empty account folder has been opened, we can remove our temporary target
            [fileManager removeItemAtURL:childFolder error:nil];
        }
    }];
}

- (void)openLocalDocumentsFolder;
{
    [self openFolder:OUIDocumentAppController.sharedController.localDocumentsURL];
}

- (void)performOpenURL:(NSURL *)url options:(OUIDocumentPerformOpenURLOptions)options;
{
    if (options & OUIDocumentPerformOpenURLOptionsImport) {
        [self importDocumentFromURL:url];
    } else if (OFIsInInbox(url)) { // move file for sure

        [OUIDocumentInbox takeInboxItem:url completionHandler:^(NSURL *newFileURL, NSError *errorOrNil) {
            main_async(^{
                if (!newFileURL) {
                    OUI_PRESENT_ERROR_IN_SCENE(errorOrNil, self.windowScene);
                    return;
                }

                // We might be getting a plug-in or other type that we can't actually open but know about as a valid type in our CFBundleDocumentTypes.
                BOOL canView = NO;
                __autoreleasing NSError *fileTypeError;
                NSString *fileType = OFUTIForFileURLPreferringNative(newFileURL, &fileTypeError);
                if (!fileType) {
                    [fileTypeError log:@"Error determining file type of %@", newFileURL];
                } else {
                    OUIDocumentAppController *controller = [OUIDocumentAppController controller];
                    canView = [controller canViewFileTypeWithIdentifier:fileType];
                }

                if (!canView || (options & OUIDocumentPerformOpenURLOptionsRevealInBrowser)) {
                    [self closeDocumentWithCompletionHandler:^{
                        [_documentBrowser revealDocumentAtURL:newFileURL importIfNeeded:NO completion:^(NSURL * _Nullable revealedDocumentURL, NSError * _Nullable revealErrorOrNil){}];
                    }];
                } else {
                    [self openDocumentInPlace:newFileURL];
                }
            });
        }];
    } else if (options & OUIDocumentPerformOpenURLOptionsOpenInPlaceAllowed) {
        [self openDocumentInPlace:url];
        return;
    } else {
        OBASSERT_NOT_REACHED("Will the system ever give us a non-inbox item that we can't open in place?");
    }
}

- (void)documentWillRebuildViewController:(OUIDocument *)document;
{
    OBPRECONDITION(document == _document);
    OBPRECONDITION(_snapshotForDocumentRebuilding == nil);

    UIWindow *window = self.window;
    _snapshotForDocumentRebuilding = [window snapshotViewAfterScreenUpdates:NO];
    [window insertSubview:_snapshotForDocumentRebuilding atIndex:window.subviews.count];
    window.userInteractionEnabled = NO;
}

- (void)documentDidRebuildViewController:(OUIDocument *)document;
{
    OBPRECONDITION(document == _document);
    OBPRECONDITION(_snapshotForDocumentRebuilding != nil);

    [UIView transitionWithView:_snapshotForDocumentRebuilding duration:kOUIDocumentPickerRevertAnimationDuration options:0
                    animations:^{
                        _snapshotForDocumentRebuilding.alpha = 0;
                    }
                    completion:^(BOOL finished) {
                        self.window.userInteractionEnabled = YES;
                        [_snapshotForDocumentRebuilding removeFromSuperview];
                        _snapshotForDocumentRebuilding = nil;
                    }];
}

- (void)documentDidFailToRebuildViewController:(OUIDocument *)document;
{
    self.window.userInteractionEnabled = YES;
    [_snapshotForDocumentRebuilding removeFromSuperview];
    _snapshotForDocumentRebuilding = nil;
}


- (UIResponder *)defaultFirstResponder;
{
    return _document.defaultFirstResponder;
}

@synthesize closeDocumentBarButtonItem = _closeDocumentBarButtonItem;
- (UIBarButtonItem *)closeDocumentBarButtonItem;
{
    if (!_closeDocumentBarButtonItem) {
        NSString *closeDocumentTitle = NSLocalizedStringWithDefaultValue(@"Documents <back button>", @"OmniUIDocument", OMNI_BUNDLE, @"Documents", @"Toolbar button title for returning to list of documents.");
        _closeDocumentBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:closeDocumentTitle style:UIBarButtonItemStylePlain target:self action:@selector(closeDocument:)];
        _closeDocumentBarButtonItem.accessibilityIdentifier = @"BackToDocuments"; // match with compact edition below for consistent screenshot script access.
    }
    return _closeDocumentBarButtonItem;
}

@synthesize compactCloseDocumentBarButtonItem = _compactCloseDocumentBarButtonItem;
- (UIBarButtonItem *)compactCloseDocumentBarButtonItem;
{
    if (!_compactCloseDocumentBarButtonItem) {
        UIImage *image = [UIImage systemImageNamed:@"folder"];
        if (image == nil) {
            image = [UIImage imageNamed:@"OUIToolbarDocuments" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil];
        }
        _compactCloseDocumentBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"OUIToolbarDocuments" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil] style:UIBarButtonItemStylePlain target:self action:@selector(closeDocument:)];
        _compactCloseDocumentBarButtonItem.accessibilityIdentifier = @"BackToDocuments";
    }
    return _compactCloseDocumentBarButtonItem;
}

@synthesize infoBarButtonItem = _infoBarButtonItem;
- (UIBarButtonItem *)infoBarButtonItem;
{
    if (_infoBarButtonItem == nil) {
        _infoBarButtonItem = [self uniqueInfoBarButtonItem];
    }
    return _infoBarButtonItem;
}

- (UIBarButtonItem *)uniqueInfoBarButtonItem;
{
    UIBarButtonItem *infoBarButtonItem = [OUIInspector inspectorOUIBarButtonItemWithTarget:self action:@selector(_showInspector:)];
    infoBarButtonItem.accessibilityLabel = NSLocalizedStringFromTableInBundle(@"Info", @"OmniUIDocument", OMNI_BUNDLE, @"Info item accessibility label");

    if (OUIAppController.sharedController.useCompactBarButtonItemsIfApplicable) {
        BOOL isHorizontallyCompact = self.document.documentViewController.traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassCompact;
        BOOL isVerticallyCompact = self.document.documentViewController.traitCollection.verticalSizeClass == UIUserInterfaceSizeClassCompact;
        UIImage *image = [UIImage systemImageNamed:@"info.circle"];
        if (image == nil) {
            NSString *imageName = (isHorizontallyCompact || isVerticallyCompact) ? @"OUIToolbarInfo-Compact" : @"OUIToolbarInfo";
            image = [UIImage imageNamed:imageName inBundle:[OUIInspector bundle] compatibleWithTraitCollection:NULL];
        }
        infoBarButtonItem.image = image;
    }

    return infoBarButtonItem;
}

- (OUIAppControllerSceneHelper *)sceneHelper;
{
    if (_sceneHelper != nil)
        return _sceneHelper;
    _sceneHelper = [[OUIAppControllerSceneHelper alloc] init];
    _sceneHelper.window = self.window;
    return _sceneHelper;
}

- (UIBarButtonItem *)newAppMenuBarButtonItem;
{
    return self.sceneHelper.newAppMenuBarButtonItem;
}

- (void)_showInspector:(id)sender;
{
    OUIDocument *document = _document;
    if ([document respondsToSelector:@selector(multiPaneController)]) {
        OUIMultiPaneController *multiPaneController = [(id)document multiPaneController];
        [multiPaneController toggleRightPane];
    }
}

#pragma mark - UIResponder subclass

- (NSArray *)keyCommands;
{
    return [OUIKeyCommands keyCommandsForCategories:[NSMutableOrderedSet<NSString *> orderedSetWithObject:@"document-controller"]];
}

- (BOOL)canPerformAction:(SEL)action withSender:(id)sender;
{
    if (action == @selector(undo:))
        return [_document.undoManager canUndo];

    if (action == @selector(redo:))
        return [_document.undoManager canRedo];

    if (action == @selector(makeNewDocument:)) {
        OBFinishPortingLater("This seems to be for cmd-n support in OUIDocumentPicker, but UIDocumentBrowserViewController needs to initiate this probably");
        return _document == nil && [_documentBrowser allowsDocumentCreation];
    }

    if (action == @selector(closeDocument:))
        return _document != nil;

    return [super canPerformAction:action withSender:sender];
}

#pragma mark - OUISceneDelegate

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions;
{
    OUIDocumentAppController *appController = OUIDocumentAppController.sharedController;

    UIWindow *window = self.window;
    if (window == nil) {
        window = [appController makeMainWindowForScene:OB_CHECKED_CAST(UIWindowScene, scene)];
        self.window = window;
    } else {
        // resize xib window to the current screen size
        [window setFrame:[[UIScreen mainScreen] bounds]];
    }

    NSArray <UTType *> *viewableTypes = [appController.viewableFileTypes arrayByPerformingBlock:^id _Nonnull(NSString *identifier) {
        UTType *fileType = [UTType typeWithIdentifier:identifier];
        OBASSERT_NOTNULL(fileType, "No UTType for %@", identifier);
        return fileType;
    }];
    _documentBrowser = [[OUIDocumentBrowserViewController alloc] initForOpeningContentTypes:viewableTypes];
    _documentBrowser.delegate = self;
    _documentBrowser.shouldShowFileExtensions = showFileExtensionsPreference.boolValue;

    [self updateBrowserToolbarItems];

    _exporter = [OUIDocumentExporter exporter];

    window.rootViewController = _documentBrowser;

    NSUserActivity *userActivity = session.stateRestorationActivity;
    if (userActivity != nil) {
        [self _restoreStateFromUserActivity:userActivity];
    } else {
        // Restore previous state
        [self _restoreStateFromUserActivities:connectionOptions.userActivities];

        // Handle quick actions from shortcuts (.shortcutItem)
        UIApplicationShortcutItem *shortcutItem = connectionOptions.shortcutItem;
        if (shortcutItem) {
            if (OFISEQUAL(shortcutItem.type, OUIShortcutTypeNewDocument)) {
                [self closeDocumentWithCompletionHandler:^{
                    [self makeNewDocument:nil];
                }];
            } else {
                OBASSERT_NOT_REACHED("Shortcut item not handled \"%@\"", shortcutItem.type);
            }
        } else {
            // Open URLs (.URLContexts)
            [self _openURLContexts:connectionOptions.URLContexts];

            // TODO: Respond to a handoff request (.handoffUserActivityType)

            // TODO: Handle the user's response to a notification (.notificationResponse)
        }
    }

    [window makeKeyAndVisible];
}

- (void)sceneDidBecomeActive:(UIScene *)scene;
{
    // When command-tabbing, our window loses first responder status. Unfortunately, if we do this right now, it gets overridden by some private class becoming first responder. Doing this via NSOperationQueue doesn't work when there are two scenes being restored -- our fixup would fire between the two scenes and then UIKit would clobber one of the scenes's first responder.

    __weak OUIDocumentSceneDelegate *weakSelf = self;
    OFAfterDelayPerformBlock(0.15, ^{
        OUIDocumentSceneDelegate *strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        [strongSelf.defaultFirstResponder becomeFirstResponder];
    });

    [self.userActivity becomeCurrent];
}

- (void)sceneWillResignActive:(UIScene *)scene;
{
    [self.userActivity resignCurrent];
}

- (void)sceneWillEnterForeground:(UIScene *)scene;
{
    if (self.document == nil) {
        (void)[OUIAppController.sharedController showNewsInWindow:self.window];
    }
}

- (void)sceneDidDisconnect:(UIScene *)scene;
{
    [self closeDocumentWithCompletionHandler:^{
        _documentBrowser = nil;
        _window = nil;
    }];
}

- (nullable NSUserActivity *)stateRestorationActivityForScene:(UIScene *)scene;
{
    NSUserActivity *userActivity = self.userActivity;
#ifdef DEBUG_kc
    NSLog(@"-[%@ %@]: scene=%@, userActivity=%@", OBShortObjectDescription(self), NSStringFromSelector(_cmd), scene, userActivity);
#endif
    return userActivity;
}

- (BOOL)_restoreStateFromUserActivities:(NSSet <NSUserActivity *> *)userActivities;
{
    for (NSUserActivity *userActivity in userActivities) {
        if ([self _restoreStateFromUserActivity:userActivity]) {
            return YES;
        }
    }
    return NO;
}

- (BOOL)_restoreStateFromUserActivity:(NSUserActivity *)userActivity;
{
#ifdef DEBUG_kc
    NSLog(@"-[%@ %@]: userActivity=%@", OBShortObjectDescription(self), NSStringFromSelector(_cmd), userActivity);
#endif
    NSString *activityType = userActivity.activityType;
    if (OFISEQUAL(activityType, [OUIDocumentAppController.sharedController.class openDocumentUserActivityType])) {
        return [self _restoreOpenDocumentUserActivity:userActivity];
    } else {
        return NO;
    }
}

- (BOOL)_restoreOpenDocumentUserActivity:(NSUserActivity *)userActivity;
{
    NSData *urlBookmark = userActivity.userInfo[OUIUserActivityUserInfoKeyBookmark];
    if (urlBookmark == nil)
        return NO;

    NSURL *documentURL = [NSURL URLByResolvingBookmarkData:urlBookmark options:NSURLBookmarkResolutionWithoutUI relativeToURL:nil bookmarkDataIsStale:NULL error:NULL];
    if (documentURL == nil)
        return NO;

    [self openDocumentInPlace:documentURL];
    return YES;
}

//

- (void)_dismissSyncFileListController:(UIViewController *)sender;
{
    [_documentBrowser dismissViewControllerAnimated:YES completion:nil];
}

- (void)_openSyncAccountsForBrowsing:(BOOL)isForBrowsing;
{
    OFXAgentActivity *agentActivity = [[OUIDocumentAppController sharedController] agentActivity];

    UIViewController *rootViewController = nil;

    if (isForBrowsing) {
        // Don't bother asking them to choose an account if they only have one and it is in working order
        NSArray <OFXServerAccount *> *validCloudSyncAccounts = agentActivity.agent.accountRegistry.validCloudSyncAccounts;
        if (validCloudSyncAccounts.count == 1) {
            OFXServerAccount *onlyAccount = validCloudSyncAccounts[0];
            if (onlyAccount.lastError == nil) {
                [self openFolderForServerAccount:onlyAccount];
                OUIDocumentSyncActivityObserver *observer = [[OUIDocumentSyncActivityObserver alloc] initWithAgentActivity:agentActivity];
                rootViewController = [OUIDocumentServerAccountFileListViewFactory fileListViewControllerWithServerAccount:onlyAccount observer:observer];
                rootViewController.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(_dismissSyncFileListController:)];
            }
        }
    }

    if (rootViewController == nil) {
        rootViewController = [[OUIServerAccountsViewController alloc] initWithAgentActivity:agentActivity forBrowsing:isForBrowsing];
    }

    UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:rootViewController];
    navController.modalTransitionStyle = UIModalTransitionStyleCoverVertical;
    navController.modalPresentationStyle = UIModalPresentationFormSheet;

    [_documentBrowser presentViewController:navController animated:YES completion:nil];
}

- (void)configureSyncAccounts;
{
    [self _openSyncAccountsForBrowsing:NO];
}

- (void)showSyncAccounts;
{
    [self updateBrowserToolbarItems];
    [self _openSyncAccountsForBrowsing:YES];
}

- (BOOL)_loadOmniPresenceConfigFileFromURL:(NSURL *)url;
{
    BOOL securedURL = [url startAccessingSecurityScopedResource];
    NSDictionary *config = [[NSDictionary alloc] initWithContentsOfURL:url];
    if (securedURL) {
        [url stopAccessingSecurityScopedResource];
    }

    if (config == nil)
        return NO;

    OFXServerAccountType *accountType = [OFXServerAccountType accountTypeWithIdentifier:[config objectForKey:@"accountType" defaultObject:OFXWebDAVServerAccountTypeIdentifier]];
    if (accountType == nil) {
        OBFinishPortingLater("<bug:///147835> (iOS-OmniOutliner Bug: OUIDocumentAppController.m:1949 - Should we display an alert when asked to open a config file with an unrecognized account type?)");
        return NO;
    }

    OUIServerAccountSetupViewController *setup = [[OUIServerAccountSetupViewController alloc] initWithAgentActivity:OUIDocumentAppController.sharedController.agentActivity creatingAccountType:accountType usageMode:OFXServerAccountUsageModeCloudSync];
    setup.location = [config objectForKey:@"location" defaultObject:setup.location];
    setup.accountName = [config objectForKey:@"accountName" defaultObject:setup.accountName];
    setup.password = [config objectForKey:@"password" defaultObject:setup.password];
    setup.nickname = [config objectForKey:@"nickname" defaultObject:setup.nickname];

    UIViewController *presentFromViewController = nil;
    if (self.document) {
        presentFromViewController = self.document.viewControllerToPresent;
    } else {
        presentFromViewController = _documentBrowser;
    }

    setup.finished = ^(OUIServerAccountSetupViewController *vc, NSError *errorOrNil) {
        OBPRECONDITION([NSThread isMainThread]);

#ifdef OMNI_ASSERTIONS_ON
        OFXServerAccount *account = errorOrNil ? nil : vc.account;
#endif
        OBASSERT_IF(account != nil & account.usageMode == OFXServerAccountUsageModeCloudSync, [[[OFXServerAccountRegistry defaultAccountRegistry] validCloudSyncAccounts] containsObject:account]);
        OBASSERT_IF(account != nil && account.usageMode == OFXServerAccountUsageModeImportExport, [[[OFXServerAccountRegistry defaultAccountRegistry] validImportExportAccounts] containsObject:account]);
        [vc dismissViewControllerAnimated:YES completion:nil];
    };

    UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:setup];
    navigationController.modalPresentationStyle = UIModalPresentationFormSheet;
    navigationController.modalTransitionStyle = UIModalTransitionStyleCoverVertical;

    [presentFromViewController presentViewController:navigationController animated:YES completion:nil];

    return YES;
}

- (void)scene:(UIScene *)scene openURLContexts:(NSSet<UIOpenURLContext *> *)URLContexts;
{
    DEBUG_LAUNCH(1, @"scene: %@ openURLContexts: %@", scene, URLContexts);
    [self _openURLContexts:URLContexts];
}

- (void)_openURLContexts:(NSSet <UIOpenURLContext *> *)URLContexts;
{
    OUIDocumentAppController *controller = [OUIDocumentAppController controller];

    for (UIOpenURLContext *openContext in URLContexts) {
        // NOTE: If we are suspending launch actions (possibly due to handling a crash), _didFinishLaunching will be NO and we'd drop this on the ground. So, we add this as launch action as well. We could try to preflight the URL to see if it is certain we can't open it, but we'd have a hard time getting an accurate answer (many of the actions are async anyway).

        // If this is NO, we must copy the document to maintain access to it
        OUIDocumentPerformOpenURLOptions options = openContext.options.openInPlace ? OUIDocumentPerformOpenURLOptionsOpenInPlaceAllowed : 0;
        NSURL *url = openContext.URL;
        DEBUG_LAUNCH(1, @"url %@", url);


        // If we can't actually edit the file we should copy it to our local scope so that we can save it to a new URL without destroying the original. (i.e., this is an import)
        if (options & OUIDocumentPerformOpenURLOptionsOpenInPlaceAllowed) {
            OBASSERT(url.isFileURL);
            Class cls = [controller documentClassForURL:url];
            OBASSERT(OBClassIsSubclassOfClass(cls, [OUIDocument class]));
            if ([cls shouldImportFileAtURL:url]) {
                options |= OUIDocumentPerformOpenURLOptionsImport;
            }
        }


        if ([controller isSpecialURL:url]) {
            _specialURLContextToHandle = openContext;
            if (self.window.rootViewController == _documentBrowser) {
                [self handleCachedSpecialURLIfNeeded];
            }
            return;
        }

        // Only attempt to open handle as an Inbox item if the URL is a file URL.
        if (url.isFileURL) {
            _isOpeningURL = YES;
            // Have to wait for the document store to awake again (if we were backgrounded), initiated by -applicationWillEnterForeground:. <bug:///79297> (Bad animation closing file opened from another app)

            // If we got multiple URLs in one pass, we are most likely getting multiple files shared and don't want to try to open them all.
            if ([URLContexts count] > 1) {
                options |= OUIDocumentPerformOpenURLOptionsRevealInBrowser;
            }

            [self performOpenURL:url options:options];
        }
    }
}

- (void)scene:(UIScene *)scene continueUserActivity:(NSUserActivity *)userActivity;
{
    [self _restoreStateFromUserActivity:userActivity];
}

#pragma mark -

- (NSArray <UIBarButtonItem *> *)currentBrowserToolbarItems;
{
    NSArray <UIBarButtonItem *> *toolbarItems;
    UIBarButtonItem *appMenuItem = self.newAppMenuBarButtonItem;

    // Add a top-level OmniPresence bar button item for now (similar to where it will go when we switch to using the iOS document browser.
    UIImage *image = OUIDocumentAppController.sharedController.agentStatusImage;
    if (image == nil) {
        toolbarItems = @[appMenuItem];
    } else {
        UIBarButtonItem *syncItem = [[UIBarButtonItem alloc] initWithImage:image style:UIBarButtonItemStylePlain target:self action:@selector(showSyncAccounts)];
        toolbarItems = @[appMenuItem, syncItem];
    }

    return toolbarItems;
}

- (void)updateBrowserToolbarItems;
{
    _documentBrowser.additionalTrailingNavigationBarButtonItems = [self currentBrowserToolbarItems];
}

- (void)handleCachedSpecialURLIfNeeded
{
    if (_specialURLContextToHandle != nil) {
        UIViewController *viewController = self.window.rootViewController;
        UIViewController *presentedViewController;
        while ((presentedViewController = viewController.presentedViewController)) {
            viewController = presentedViewController;
        }

        [[OUIDocumentAppController controller] handleSpecialURL:_specialURLContextToHandle.URL senderBundleIdentifier:_specialURLContextToHandle.options.sourceApplication presentingFromViewController:viewController];
        _specialURLContextToHandle = nil;
    }
}

#pragma mark - UIWindowSceneDelegate

- (void)windowScene:(UIWindowScene *)windowScene performActionForShortcutItem:(UIApplicationShortcutItem *)shortcutItem completionHandler:(void (^)(BOOL succeeded))completionHandler
{
    if (completionHandler == nil)
        completionHandler = ^(BOOL _succeeded) {};

    if (OFISEQUAL(shortcutItem.type, OUIShortcutTypeNewDocument)) {
        [self closeDocumentWithCompletionHandler:^{
            [self makeNewDocument:nil];
            completionHandler(YES);
        }];
    } else {
        completionHandler(NO);
    }
}

#pragma mark - UIDocumentBrowserViewControllerDelegate

- (void)documentBrowser:(UIDocumentBrowserViewController *)controller didPickDocumentsAtURLs:(NSArray <NSURL *> *)documentURLs;
{
    OBPRECONDITION(documentURLs.count == 1);

    NSURL *documentURL = documentURLs.firstObject;
    if (!documentURL) {
        return;
    }

#if 1 && defined(DEBUG_bungi)
    BOOL crashBasedOnFilename = YES;
#else
    BOOL crashBasedOnFilename = [[NSUserDefaults standardUserDefaults] boolForKey:@"OUIDocumentSceneShouldCrashBasedOnFileName"];
#endif
    if (crashBasedOnFilename) {
        OBRecordBacktrace("crashing intentionally", OBBacktraceBuffer_Generic);
        OBRecordBacktraceWithContext("crashing intentionally w/context", OBBacktraceBuffer_Generic, (__bridge void *)self);

        NSString *crashType = [[documentURL lastPathComponent] stringByDeletingPathExtension];
        if ([crashType isEqual:@"crash-abort"])
            abort();
        if ([crashType isEqual:@"crash-null"])
            NSLog(@"%d", *(int *)(intptr_t)[@"0" intValue]);
        if ([crashType isEqual:@"crash-exception"])
            [NSException raise:NSGenericException reason:@"testing unhandled exception"];
        if ([crashType isEqual:@"crash-signal"])
            raise(SIGTRAP); // really the same as abort since it raises SIGABRT
#if 0
        if ([crashType isEqual:@"crash-report"]) {
            NSData *reportData = [[PLCrashReporter sharedReporter] generateLiveReport];
            PLCrashReport *report = [[PLCrashReport alloc] initWithData:reportData error:NULL];

            NSString *reportText = [PLCrashReportTextFormatter stringValueForCrashReport:report withTextFormat:PLCrashReportTextFormatiOS];
            NSURL *reportURL = [[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:@"crash-report.txt"];

            __autoreleasing NSError *error = nil;
            if (![reportText writeToURL:reportURL atomically:NO encoding:NSUTF8StringEncoding error:&error]) {
                [error log:@"Error writing report to %@", reportURL];

            }

            return;
        }
#endif
    }

    [self openDocumentInPlace:documentURL];
}

- (void)documentBrowser:(UIDocumentBrowserViewController *)controller didRequestDocumentCreationWithHandler:(void(^)(NSURL *_Nullable urlToImport, UIDocumentBrowserImportMode importMode))importHandler;
{
    OUIDocumentAppController *appController = OUIDocumentAppController.sharedController;
    OBASSERT([appController conformsToProtocol:@protocol(OUIDocumentCreationRequestDelegate)]);
    OUINewDocumentCreationRequest *request = [[OUINewDocumentCreationRequest alloc] initWithDelegate:(id <OUIDocumentCreationRequestDelegate>)appController viewController:controller creationHandler:importHandler];

    id <OUIInternalTemplateDelegate> internalTemplateDelegate = nil;
    if ([self conformsToProtocol:@protocol(OUIInternalTemplateDelegate)]) {
        internalTemplateDelegate = (id <OUIInternalTemplateDelegate>)self;
    }
    [request runWithInternalTemplateDelegate:internalTemplateDelegate];
}

- (void)documentBrowser:(UIDocumentBrowserViewController *)controller didImportDocumentAtURL:(NSURL *)sourceURL toDestinationURL:(NSURL *)destinationURL;
{
    [self openDocumentInPlace:destinationURL];
}

- (void)documentBrowser:(UIDocumentBrowserViewController *)controller failedToImportDocumentAtURL:(NSURL *)documentURL error:(NSError * _Nullable)error;
{
    NSString *title = NSLocalizedStringFromTableInBundle(@"Unable to open file.", @"OmniUIDocument", OMNI_BUNDLE, @"error title");
    NSString *localizedDescription = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"While attempting to open %@, received an error from the system", @"OmniUIDocument", OMNI_BUNDLE, @"error description"), documentURL.lastPathComponent];
    NSString *detailedDescription = [NSString stringWithFormat:@"%@:\n\n%@\n\n%@", localizedDescription, error.localizedDescription, error.localizedFailureReason];
    OUIDocumentError(&error, OUIDocumentErrorImportFailed, title, detailedDescription);
    OFMainThreadPerformBlock(^(void) {
        [OUIAppController presentError:error fromViewController:self.documentBrowser];
    });
}

- (NSArray<__kindof UIActivity *> *)documentBrowser:(UIDocumentBrowserViewController *)controller applicationActivitiesForDocumentURLs:(NSArray <NSURL *> *)documentURLs;
{
    return _exporter.supportedActivities;
}

#pragma mark - OUIUndoBarButtonItemTarget

- (id)targetForAction:(SEL)action withSender:(id)sender;
{
    return [_document.documentViewController targetForAction:action withSender:sender];
}

- (void)undo:(id)sender;
{
    [_document undo:sender];
}

- (void)redo:(id)sender;
{
    [_document redo:sender];
}

@end

NSString * const OUIUserActivityUserInfoKeyBookmark = @"URL_bookmark";
