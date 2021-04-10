// Copyright 2019 Omni Development, Inc. All rights reserved.
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

#import "OUILaunchViewController.h"
#import "OUINewDocumentCreationRequest.h"
#import "OUIDocumentParameters.h"
#import "OUINewDocumentCreationRequest.h"
#import "OUIDocumentInbox.h"
#import "OUIDocumentOpenAnimator.h"

@interface OUIDocumentSceneDelegate () <UIDocumentBrowserViewControllerDelegate>
@property (nonatomic, strong) OUIAppControllerSceneHelper *sceneHelper;
@end

@implementation OUIDocumentSceneDelegate
{
    UIDocumentBrowserViewController *_documentBrowser;
    OUIDocumentExporter *_exporter;
    BOOL _isOpeningURL; // TODO: Evaluate whether we can get rid of this
    UIView *_snapshotForDocumentRebuilding;
    
    NSURL *_specialURLToHandle;
}

+ (nullable instancetype)documentSceneDelegateForView:(UIView *)view;
{
    UIWindow *window = view.window;
    if (window == nil)
        return nil;

    OUIDocumentSceneDelegate *delegate = OB_CHECKED_CAST(OUIDocumentSceneDelegate, view.window.windowScene.delegate);
    assert(delegate != nil);
    assert([delegate isKindOfClass:[OUIDocumentSceneDelegate class]]);
    return delegate;
}

+ (NSArray <OUIDocumentSceneDelegate *> *)activeSceneDelegatesMatchingConditionBlock:(BOOL (^)(OUIDocumentSceneDelegate *sceneDelegate))conditionBlock;
{
    NSSet <UIScene *> *connectedScenes = UIApplication.sharedApplication.connectedScenes;
    NSMutableArray <OUIDocumentSceneDelegate *> *matchingDelegates = [[NSMutableArray alloc] init];
    Class targetClass = [self class];
    for (UIScene *scene in connectedScenes) {
        id delegate = scene.delegate;
        if (![delegate isKindOfClass:targetClass])
            continue;
        OUIDocumentSceneDelegate *documentSceneDelegate = delegate;
        if (conditionBlock(documentSceneDelegate)) {
            [matchingDelegates addObject:documentSceneDelegate];
        }
    }

    return matchingDelegates;
}

+ (NSArray <OUIDocumentSceneDelegate *> *)documentSceneDelegatesForDocument:(OUIDocument *)document;
{
    return [self activeSceneDelegatesMatchingConditionBlock:^BOOL(OUIDocumentSceneDelegate *sceneDelegate) {
        return sceneDelegate.document == document;
    }];
}

- init;
{
    return [super init];
}

- (UIWindowScene *)windowScene;
{
    return self.window.windowScene;
}

- (void)openDocumentInPlace:(NSURL *)url
{
    [self _openDocumentAtURL:url isOpeningFromPeek:NO willPresentHandler:nil completionHandler:nil];
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
                    
                    [self.documentBrowser importDocumentAtURL:document.fileURL nextToDocumentAtURL:fileURL mode:UIDocumentBrowserImportModeMove completionHandler:^(NSURL * _Nullable importedURL, NSError * _Nullable errorOrNil) {
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
    OUINewDocumentCreationRequest *request = [[OUINewDocumentCreationRequest alloc] initWithDelegate:OB_CHECKED_CONFORM(OUIDocumentCreationRequestDelegate, controller) creationHandler:^(NSURL *urlToImport, UIDocumentBrowserImportMode importMode){
        OBASSERT_NOT_REACHED("Not actually going to run this creation request");
    }];
    
    NSURL *temporaryURL = [request temporaryURLForCreatingNewDocumentNamed:[[fileURL lastPathComponent] stringByDeletingPathExtension] withType:ODSDocumentTypeNormal];
                           
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

    // <bug:///108386> (iOS-OmniGraffle Feature: Feature: Handoff support)
    // Need to determine whether or not this is an iCloud URL. If so, we can make this activity eligible for Handoff. Or, if it's not an iCloud doc, we can adopt the continuation stream APIs to give the other side the data to replicate our document.
    activity.eligibleForHandoff = NO;

    return activity;
}

- (void)_setDocument:(OUIDocument *)document;
{
    if (_document == document)
        return;

    if (_document != nil) {
        self.userActivity = nil;
        [[NSNotificationCenter defaultCenter] removeObserver:self name:UIDocumentStateChangedNotification object:_document];
        [_document didClose];
    }

    _document = document;

    if (document != nil) {
        self.userActivity = [self _createUserActivityForDocument:document];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_documentStateChanged:) name:UIDocumentStateChangedNotification object:_document];
    }
}

- (void)_documentStateChanged:(NSNotification *)note;
{
    OBPRECONDITION([note object] == _document);

    UIDocumentState state = _document.documentState;
    OB_UNUSED_VALUE(state);

    DEBUG_DOCUMENT(@"State changed to %ld", state);
}

- (void)openDocumentAtURL:(NSURL *)fileURL fromPeekWithWillPresentHandler:(void (^)(OUIDocumentOpenAnimator *openAnimator))willPresentHandler completionHandler:(void (^)(void))completionHandler;
{
    [self _openDocumentAtURL:fileURL isOpeningFromPeek:YES willPresentHandler:willPresentHandler completionHandler:completionHandler];
}

- (void)_openDocumentAtURL:(NSURL *)fileURL isOpeningFromPeek:(BOOL)isOpeningFromPeek willPresentHandler:(void (^)(OUIDocumentOpenAnimator *openAnimator))willPresent completionHandler:(void (^)(void))completion;
{
    OBPRECONDITION([NSThread isMainThread]);
    OBPRECONDITION(fileURL);

    // TODO: Check downloaded?
    //OBPRECONDITION(fileItemToOpen.isDownloaded);

    __block void (^willPresentHandler)(OUIDocumentOpenAnimator *openAnimator) = [willPresent copy];
    __block void (^completionHandler)(void) = [completion copy];

    OUIDocumentAppController *appController = OUIDocumentAppController.sharedController;
    [appController checkTemporaryLicensingStateWithCompletionHandler:^{
        if (_document != nil && OFURLEqualsURL(_document.fileURL, fileURL)) {
            // The document we're supposed to open is already open. Let's not do anything, eh?
            if (completionHandler) {
                completionHandler();
            }
            return;
        }


//        if (!isOpeningFromPeek) {
//            [_documentPicker navigateToContainerForItem:fileItemToOpen dismissingAnyOpenDocument:YES animated:NO];
//        }

        void (^onFail)(void) = ^{
            if (!isOpeningFromPeek) {
                // Not sure this is needed, and it also misbehaves in iOS 13; if you are looking at the document in "Browse" mode, this will switch to Recents for no reason.
                // [self.documentBrowser revealDocumentAtURL:fileURL importIfNeeded:NO completion:^(NSURL *url, NSError *error){}]; // Crashes in iOS13b5 if the completion handler is nil
            }
            _isOpeningURL = NO;
        };
        onFail = [onFail copy];

        OUIActivityIndicator *activityIndicator = nil;
        if (!isOpeningFromPeek) {
            OBFinishPortingLater("Show an activity indicator");
#if 0
            OUIDocumentPickerFileItemView *fileItemView = [_documentPicker.selectedScopeViewController.mainScrollView fileItemViewForFileItem:fileItemToRevealFrom];
            if (fileItemView) {
                activityIndicator = [OUIActivityIndicator showActivityIndicatorInView:fileItemView withColor:UIColor.whiteColor bezelColor:[UIColor.darkGrayColor colorWithAlphaComponent:0.9]];
            }
            else if (self.window.rootViewController == _documentPicker) {
                activityIndicator = [OUIActivityIndicator showActivityIndicatorInView:_documentPicker.view withColor:UIColor.whiteColor];
            }
#endif
        }

        onFail = [onFail copy];


        void (^doOpen)(void) = ^{
            Class cls = [appController documentClassForURL:fileURL];
            OBASSERT(OBClassIsSubclassOfClass(cls, [OUIDocument class]));

            if ([cls shouldImportFileAtURL:fileURL]) {
                [self importDocumentFromURL:fileURL];
                [activityIndicator hide];
                return;
            }

            __autoreleasing NSError *error = nil;
            OUIDocument *document = [[cls alloc] initWithExistingFileURL:fileURL error:&error];

            if (!document) {
                OUI_PRESENT_ERROR_FROM(error, self.window.rootViewController);
                onFail();
                return;
            }

            document.applicationLock = [OUIInteractionLock applicationLock];

            [self _setDocument:document];

            [document openWithCompletionHandler:^(BOOL success){
                if (!success) {
                    OUIDocumentHandleDocumentOpenFailure(document, nil);

                    [activityIndicator hide];
                    [document.applicationLock unlock];
                    document.applicationLock = nil;

                    [self _setDocument:nil];

                    onFail();
                    return;
                }

                OBASSERT([NSThread isMainThread]);
                _isOpeningURL = NO;

                OBFinishPortingLater("Use UIDocumentBrowserViewController's support for animated open/close");
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

                OBASSERT(![document hasUnsavedChanges]); // We just loaded our document and created our view, we shouldn't have any view state that needs to be saved. If we do, we should probably investigate to prevent bugs like <bug:///80514> ("Document Updated" on (null) alert is still hanging around), perhaps discarding view state changes if we can't prevent them.

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
                    [window makeKeyAndVisible];

                    OBFinishPortingLater("Figure out who's handling special URLs");
                    // [self handleCachedSpecialURLIfNeeded];
                }

                UIDocumentBrowserTransitionController *transitionController = [_documentBrowser transitionControllerForDocumentAtURL:fileURL];
                OUIDocumentOpenAnimator *animator = [[OUIDocumentOpenAnimator alloc] initWithTransitionController:transitionController];
                
                transitionController.targetView = documentViewController.documentOpenCloseTransitionView;
                
//                animator.isOpeningFromPeek = isOpeningFromPeek;
//                animator.backgroundSnapshotView = nil;
//                animator.previewSnapshotView = nil;
//                animator.previewRect = CGRectZero;

                if (isOpeningFromPeek && willPresentHandler) {
                    OBFinishPortingWithNote("<bug:///176696> (Frameworks-iOS Unassigned: OBFinishPorting: Handle or remove isOpeningFromPeek flag in _openDocumentAtURL:isOpeningFromPeek:willPresentHandler: in OUIDocumentAppController)");
                    //willPresentHandler(animator);
                }

                OBASSERT_NOTNULL(toPresent);
                toPresent.transitioningDelegate = animator;
                toPresent.modalPresentationStyle = UIModalPresentationCustom;

                [presentFromViewController presentViewController:toPresent animated:animateDocument completion:^{
                    if ([documentViewController respondsToSelector:@selector(documentFinishedOpening)])
                        [documentViewController documentFinishedOpening];
                    [activityIndicator hide];
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

- (IBAction)makeNewDocument:(nullable id)sender;
{
    OBFinishPorting;
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
    if (!_document) {
        if (completionHandler)
            completionHandler();
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

        OBStrongRetain(_document);
        [_document closeWithCompletionHandler:^(BOOL success) {
            [closingDocumentIndicatorView removeFromSuperview];

            // Give the document a chance to break retain cycles.
            [_document didClose];
            // self.launchAction = nil;

            // Doing the -autorelease in the completion handler wasn't late enough. This may not be either...
            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                OBASSERT([NSThread isMainThread]);
                OBStrongRelease(_document);
            }];

            [_document.applicationLock unlock];
            _document.applicationLock = nil;

            if (completionHandler)
                completionHandler();

            [self _setDocument:nil];
        }];
    }];
}


- (void)performOpenURL:(NSURL *)url options:(OUIDocumentPerformOpenURLOptions)options;
{
    if (options & OUIDocumentPerformOpenURLOptionsImport) {
        [self importDocumentFromURL:url];
    } else if (ODSIsInInbox(url)) { // move file for sure
        
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
        OBFinishPortingWithNote("<bug:///176703> (Frameworks-iOS Unassigned: OBFinishPorting: Port or remove fallback path for non-inbox, non-in place open request)");
#if 0
        OBASSERT_NOT_REACHED("Will the system ever give us a non-inbox item that we can't open in place?");
        ODSFileItem *fileItem = [_documentStore fileItemWithURL:url];
        OBASSERT(fileItem);
        if (fileItem)
            [self openDocument:fileItem];
#endif
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
        NSString *imageName = (isHorizontallyCompact || isVerticallyCompact) ? @"OUIToolbarInfo-Compact" : @"OUIToolbarInfo";
        infoBarButtonItem.image = [UIImage imageNamed:imageName inBundle:[OUIInspector bundle] compatibleWithTraitCollection:NULL];
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

    _documentBrowser = [[UIDocumentBrowserViewController alloc] initForOpeningFilesWithContentTypes:appController.viewableFileTypes];
    _documentBrowser.delegate = self;

    {
        // Add a top-level OmniPresence bar button item for now (similar to where it will go when we switch to using the iOS document browser.
        UIImage *image = [UIImage imageNamed:@"OmniPresenceToolbarIcon" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil];
        UIBarButtonItem *syncItem = [[UIBarButtonItem alloc] initWithImage:image style:UIBarButtonItemStylePlain target:self action:@selector(_showSyncAccounts:)];

        UIBarButtonItem *appMenuItem = self.newAppMenuBarButtonItem;

        _documentBrowser.additionalTrailingNavigationBarButtonItems = @[appMenuItem, syncItem];
    }

    _exporter = [OUIDocumentExporter exporter];
    
#if 0
    OUILaunchViewController *launchViewController = [[OUILaunchViewController alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge color:appController.launchActivityIndicatorColor];
    UINavigationController *launchNavController = [[UINavigationController alloc] initWithRootViewController:launchViewController];
#endif
    window.rootViewController = _documentBrowser;

    NSUserActivity *userActivity = session.stateRestorationActivity;
    if (userActivity != nil) {
        [self _restoreStateFromUserActivity:userActivity];
    } else {
        [self _restoreStateFromUserActivities:connectionOptions.userActivities];
    }

    [window makeKeyAndVisible];
}

- (void)sceneDidDisconnect:(UIScene *)scene;
{
}

- (nullable NSUserActivity *)stateRestorationActivityForScene:(UIScene *)scene;
{
    NSUserActivity *userActivity = self.userActivity;
#ifdef DEBUG_kc
    NSLog(@"-[%@ %@]: scene=%@, userActivity=%@", OBShortObjectDescription(self), NSStringFromSelector(_cmd), scene, userActivity);
#endif
    return userActivity;
}

- (void)_restoreStateFromUserActivities:(NSSet <NSUserActivity *> *)userActivities;
{
    for (NSUserActivity *userActivity in userActivities) {
        if ([self _restoreStateFromUserActivity:userActivity]) {
            return;
        }
    }
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

- (void)_showSyncAccounts:(id)sender;
{
    OFXAgentActivity *agentActivity = [[OUIDocumentAppController sharedController] agentActivity];
    OUIServerAccountsViewController *accountsViewController = [[OUIServerAccountsViewController alloc] initWithAgentActivity:agentActivity];

    UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:accountsViewController];
    navController.modalTransitionStyle = UIModalTransitionStyleCoverVertical;
    navController.modalPresentationStyle = UIModalPresentationFormSheet;

    [_documentBrowser presentViewController:navController animated:YES completion:nil];
}

- (BOOL)_loadOmniPresenceConfigFileFromURL:(NSURL *)url;
{
    OBFinishPortingWithNote("<bug:///176701> (Frameworks-iOS Unassigned: OBFinishPorting: Handle _loadOmniPresenceConfigFileFromURL: in OUIDocumentAppController)");
#if 0
    NSDictionary *config = [[NSDictionary alloc] initWithContentsOfURL:url];
    if (ODSIsInInbox(url)) {
        // Now that we've finished reading this config file, we don't need to leave it lying around
        __autoreleasing NSError *deleteError = nil;
        if (![[NSFileManager defaultManager] removeItemAtURL:url error:&deleteError])
            NSLog(@"Unable to delete %@: %@", [url absoluteString], [deleteError toPropertyList]);
    }

    if (config == nil)
        return NO;

    OFXServerAccountType *accountType = [OFXServerAccountType accountTypeWithIdentifier:[config objectForKey:@"accountType" defaultObject:OFXWebDAVServerAccountTypeIdentifier]];
    if (accountType == nil) {
        OBFinishPortingLater("<bug:///147835> (iOS-OmniOutliner Bug: OUIDocumentAppController.m:1949 - Should we display an alert when asked to open a config file with an unrecognized account type?)");
        return NO;
    }

    OUIServerAccountSetupViewController *setup = [[OUIServerAccountSetupViewController alloc] initWithAgentActivity:_agentActivity creatingAccountType:accountType usageMode:OFXServerAccountUsageModeCloudSync];
    setup.location = [config objectForKey:@"location" defaultObject:setup.location];
    setup.accountName = [config objectForKey:@"accountName" defaultObject:setup.accountName];
    setup.password = [config objectForKey:@"password" defaultObject:setup.password];
    setup.nickname = [config objectForKey:@"nickname" defaultObject:setup.nickname];

    UIViewController *presentFromViewController = nil;
    if (self.document) {
        presentFromViewController = self.document.viewControllerToPresent;
    }
    else {
        presentFromViewController = _documentPicker;
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

    // Doing this during launch?
    UIWindow *window = self.window;
    if (window.rootViewController != _documentPicker) {
        [_documentPicker showDocuments];
        window.rootViewController = _documentPicker;
        [window makeKeyAndVisible];
        
        [self handleCachedSpecialURLIfNeeded];
    }

    UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:setup];
    navigationController.modalPresentationStyle = UIModalPresentationFormSheet;
    navigationController.modalTransitionStyle = UIModalTransitionStyleCoverVertical;
    
    [presentFromViewController presentViewController:navigationController animated:YES completion:nil];

    return YES;
#endif
}

- (void)scene:(UIScene *)scene openURLContexts:(NSSet<UIOpenURLContext *> *)URLContexts;
{
    DEBUG_LAUNCH(1, @"scene: %@ openURLContexts: %@", scene, URLContexts);

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
            OBFinishPortingWithNote("<bug:///176704> (Frameworks-iOS Unassigned: OBFinishPorting: Handle special URLs in OUIDocumentAppController)");
#if 0
            _specialURLToHandle = [url copy];
            if (self.window.rootViewController == _documentPicker) {
                [self handleCachedSpecialURLIfNeeded];
            }
#endif
            return;
        }
        
        if ([url isFileURL] && OFISEQUAL([[url path] pathExtension], @"omnipresence-config")) {
            OBFinishPortingLater("Handle OmniPresence config files");
#if 0
            OBASSERT(_syncAgent != nil);
            [_syncAgent afterAsynchronousOperationsFinish:^{
                [self _loadOmniPresenceConfigFileFromURL:url];
            }];
#endif
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

- (void)handleCachedSpecialURLIfNeeded
{
    if (_specialURLToHandle != nil) {
        UIViewController *viewController = self.window.rootViewController;
        UIViewController *presentedViewController;
        while ((presentedViewController = viewController.presentedViewController)) {
            viewController = presentedViewController;
        }
        
        [[OUIDocumentAppController controller] handleSpecialURL:_specialURLToHandle presentingFromViewController:viewController];
        _specialURLToHandle = nil;
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

    [self openDocumentInPlace:documentURL];
}

- (void)documentBrowser:(UIDocumentBrowserViewController *)controller didRequestDocumentCreationWithHandler:(void(^)(NSURL *_Nullable urlToImport, UIDocumentBrowserImportMode importMode))importHandler;
{
    OUIDocumentAppController *appController = OUIDocumentAppController.sharedController;
    OBASSERT([appController conformsToProtocol:@protocol(OUIDocumentCreationRequestDelegate)]);
    OUINewDocumentCreationRequest *request = [[OUINewDocumentCreationRequest alloc] initWithDelegate:(id <OUIDocumentCreationRequestDelegate>)appController creationHandler:importHandler];

    id <OUIInternalTemplateDelegate> internalTemplateDelegate = nil;
    if ([appController conformsToProtocol:@protocol(OUIInternalTemplateDelegate)]) {
        internalTemplateDelegate = (id <OUIInternalTemplateDelegate>)appController;
    }
    [request runWithViewController:controller internalTemplateDelegate:internalTemplateDelegate];
}

- (void)documentBrowser:(UIDocumentBrowserViewController *)controller didImportDocumentAtURL:(NSURL *)sourceURL toDestinationURL:(NSURL *)destinationURL;
{
    [self openDocumentInPlace:destinationURL];
}

- (void)documentBrowser:(UIDocumentBrowserViewController *)controller failedToImportDocumentAtURL:(NSURL *)documentURL error:(NSError * _Nullable)error;
{
    OBFinishPortingWithNote("<bug:///176706> (Frameworks-iOS Unassigned: OBFinishPorting: Handle documentBrowser:failedToImportDocumentAtURL:error: in OUIDocumentAppController)");
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
