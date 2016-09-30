// Copyright 2010-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUIDocument/OUIDocumentAppController.h>

#import <MobileCoreServices/MobileCoreServices.h>
#import <CoreSpotlight/CoreSpotlight.h>
#import <OmniAppKit/OAFontDescriptor.h>
#import <OmniBase/OmniBase.h>
#import <OmniDAV/ODAVErrors.h>
#import <OmniDAV/ODAVFileInfo.h>
#import <OmniDocumentStore/ODSErrors.h>
#import <OmniDocumentStore/ODSExternalScope.h>
#import <OmniDocumentStore/ODSFileItem.h>
#import <OmniDocumentStore/ODSFolderItem.h>
#import <OmniDocumentStore/ODSLocalDirectoryScope.h>
#import <OmniDocumentStore/ODSScope-Subclass.h>
#import <OmniDocumentStore/ODSStore.h>
#import <OmniDocumentStore/ODSUtilities.h>
#import <OmniFileExchange/OmniFileExchange.h>
#import <OmniFoundation/NSDictionary-OFExtensions.h>
#import <OmniFoundation/NSFileManager-OFSimpleExtensions.h>
#import <OmniFoundation/NSMutableArray-OFExtensions.h>
#import <OmniFoundation/NSObject-OFExtensions.h>
#import <OmniFoundation/NSSet-OFExtensions.h>
#import <OmniFoundation/NSString-OFExtensions.h>
#import <OmniFoundation/NSURL-OFExtensions.h>
#import <OmniFoundation/NSDate-OFExtensions.h>
#import <OmniFoundation/NSError-OFExtensions.h>
#import <OmniFoundation/OFBackgroundActivity.h>
#import <OmniFoundation/OFBindingPoint.h>
#import <OmniFoundation/OFCredentials.h>
#import <OmniFoundation/OFFileEdit.h>
#import <OmniFoundation/OFPreference.h>
#import <OmniFoundation/OFUTI.h>
#import <OmniUI/OUIActivityIndicator.h>
#import <OmniUI/OUIAppController+SpecialURLHandling.h>
#import <OmniUI/OUIBarButtonItem.h>
#import <OmniUI/OUICertificateTrustAlert.h>
#import <OmniUI/OUIInspector.h>
#import <OmniUI/OUIInteractionLock.h>
#import <OmniUI/OUIKeyCommands.h>
#import <OmniUI/OUIMenuController.h>
#import <OmniUI/OUIMenuOption.h>
#import <OmniUI/OUIWebViewController.h>
#import <OmniUI/UIView-OUIExtensions.h>
#import <OmniUIDocument/OUIDocument.h>
#import <OmniUIDocument/OUIDocumentPicker.h>
#import <OmniUIDocument/OUIDocumentPickerViewController.h>
#import <OmniUIDocument/OUIDocumentPickerFileItemView.h>
#import <OmniUIDocument/OUIDocumentPreview.h>
#import <OmniUIDocument/OUIDocumentPreviewGenerator.h>
#import <OmniUIDocument/OUIDocumentPreviewView.h>
#import <OmniUIDocument/OUIDocumentProviderPreferencesViewController.h>
#import <OmniUIDocument/OUIDocumentViewController.h>
#import <OmniUIDocument/OUIDocumentCreationTemplatePickerViewController.h>
#import <OmniUIDocument/OUIServerAccountSetupViewController.h>
#import <OmniUIDocument/OUIToolbarTitleButton.h>
//#import <CrashReporter/CrashReporter.h>

#import "OUIImportExportAccountListViewController.h"
#import "OUIDocument-Internal.h"
#import "OUIDocumentAppController-Internal.h"
#import "OUIDocumentExternalScopeManager.h"
#import "OUIDocumentInbox.h"
#import "OUIDocumentParameters.h"
#import "OUIDocumentPicker-Internal.h"
#import "OUIDocumentPickerViewController-Internal.h"
#import "OUIDocumentPickerItemView-Internal.h"
#import "OUIRestoreSampleDocumentListController.h"
#import "OUIDocumentOpenAnimator.h"
#import "OUIWebDAVSyncListController.h"
#import "OUILaunchViewController.h"
#import <OmniFoundation/OFBackgroundActivity.h>


RCS_ID("$Id$");

// OUIDocumentConflictResolutionViewControllerDelegate is gone
OBDEPRECATED_METHOD(-conflictResolutionPromptForFileItem:);
OBDEPRECATED_METHOD(-conflictResolutionCancelled:);

OBDEPRECATED_METHOD(-documentStore:fileWithURL:andDate:willCopyToURL:);
OBDEPRECATED_METHOD(-documentStore:fileWithURL:andDate:finishedCopyToURL:andDate:successfully:);

OBDEPRECATED_METHOD(-conflictResolutionFinished:);

static NSString * const OpenAction = @"open";

static NSString * const ODSShortcutTypeNewDocument = @"com.omnigroup.framework.OmniUIDocument.shortcut-items.new-document";
static NSString * const ODSShortcutTypeOpenRecent = @"com.omnigroup.framework.OmniUIDocument.shortcut-items.open-recent";

static NSString * const ODSOpenRecentDocumentShortcutFileKey = @"ODSFileItemURLStringKey";


static OFDeclareDebugLogLevel(OUIApplicationLaunchDebug);
#define DEBUG_LAUNCH(level, format, ...) do { \
    if (OUIApplicationLaunchDebug >= (level)) \
        NSLog(@"APP: " format, ## __VA_ARGS__); \
    } while (0)

static OFDeclareDebugLogLevel(OUIBackgroundFetchDebug);
#define DEBUG_FETCH(level, format, ...) do { \
    if (OUIBackgroundFetchDebug >= (level)) \
        NSLog(@"FETCH: " format, ## __VA_ARGS__); \
    } while (0)

static OFDeclareTimeInterval(OUIBackgroundFetchTimeout, 15, 5, 600);

@interface OUIDocumentAppController (/*Private*/) <OUIDocumentPreviewGeneratorDelegate, OUIDocumentPickerDelegate, OUIWebViewControllerDelegate, UIDocumentPickerDelegate>

@property(nonatomic,copy) NSArray *launchAction;

@property (nonatomic, strong) NSArray *leftItems;
@property (nonatomic, strong) NSArray *rightItems;

@property (nonatomic, weak) OUIWebViewController *webViewController;
@property (nonatomic,readonly) UIBarButtonItem *editButtonItem;
@property (nonatomic, strong) void (^externalPickerCompletionBlock)(NSURL *);
@property (nonatomic) BOOL readyToShowNews;

@end

static unsigned SyncAgentRunningAccountsContext;

@implementation OUIDocumentAppController
{
    UIWindow *_window;
    
    dispatch_once_t _roleByFileTypeOnce;
    NSDictionary *_roleByFileType;
    
    NSArray *_editableFileTypes;

    OUIDocument *_document;
    
    BOOL _didFinishLaunching;
    BOOL _isOpeningURL;

    OFXAgent *_syncAgent;
    BOOL _syncAgentForegrounded; // Keep track of whether we have told the sync agent to run. We might get backgrounded while starting up (when handling a crash alert, for example).
    
    ODSStore *_documentStore;
    ODSLocalDirectoryScope *_localScope;
    OUIDocumentExternalScopeManager *_externalScopeManager;
    OUIDocumentPreviewGenerator *_previewGenerator;
    BOOL _previewGeneratorForegrounded;
    
    UIView *_snapshotForDocumentRebuilding;
    NSURL *_specialURLToHandle;
    OFBackgroundActivity *_backgroundFlushActivity;
}

+ (void)initialize;
{
    OBINITIALIZE;
    
#if 0 && defined(DEBUG) && OUI_GESTURE_RECOGNIZER_DEBUG
    [UIGestureRecognizer enableStateChangeLogging];
#endif
    
#if 0 && defined(DEBUG)
    sleep(3); // see the default image
#endif
}

- (void)dealloc;
{
    [self _setDocument:nil];
}

// UIApplicationDelegate has an @optional window property. Our superclass conforms to this protocol, so clang assumes we already have the property, it seems (even though we redeclare it).
@synthesize window = _window;

// Called at app startup if the main xib didn't have a window outlet hooked up.
- (UIWindow *)makeMainWindow;
{
    NSString *windowClassName = [[OFPreference preferenceForKey:@"OUIMainWindowClass"] stringValue];
    Class windowClass = ![NSString isEmptyString:windowClassName] ? NSClassFromString(windowClassName) : [UIWindow class];
    OBASSERT(OBClassIsSubclassOfClass(windowClass, [UIWindow class]));
    
    UIWindow *window = [[windowClass alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    window.backgroundColor = [UIColor whiteColor];
    return window;
}

- (BOOL)useCompactBarButtonItemsIfApplicable;
{
    return NO;
}

@synthesize closeDocumentBarButtonItem = _closeDocumentBarButtonItem;
- (UIBarButtonItem *)closeDocumentBarButtonItem;
{
    if (!_closeDocumentBarButtonItem) {
        NSString *closeDocumentTitle = NSLocalizedStringWithDefaultValue(@"Documents <back button>", @"OmniUIDocument", OMNI_BUNDLE, @"Documents", @"Toolbar button title for returning to list of documents.");
        _closeDocumentBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:closeDocumentTitle
                                                                        style:UIBarButtonItemStylePlain target:self action:@selector(closeDocument:)];
        _closeDocumentBarButtonItem.accessibilityIdentifier = @"BackToDocuments"; // match with compact edition below for consistent screenshot script access.
    }
    return _closeDocumentBarButtonItem;
}

@synthesize compactCloseDocumentBarButtonItem = _compactCloseDocumentBarButtonItem;
- (UIBarButtonItem *)compactCloseDocumentBarButtonItem;
{
    if (!_compactCloseDocumentBarButtonItem) {
        _compactCloseDocumentBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"OUIToolbarDocumentClose" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil]
                                                                       style:UIBarButtonItemStylePlain target:self action:@selector(closeDocument:)];
        _compactCloseDocumentBarButtonItem.accessibilityIdentifier = @"BackToDocuments";
    }
    return _compactCloseDocumentBarButtonItem;
}

@synthesize infoBarButtonItem = _infoBarButtonItem;
- (UIBarButtonItem *)infoBarButtonItem;
{
    if (!_infoBarButtonItem) {
        _infoBarButtonItem = [OUIInspector inspectorBarButtonItemWithTarget:self action:@selector(_showInspector:)];
        _infoBarButtonItem.accessibilityLabel = NSLocalizedStringFromTableInBundle(@"Info", @"OmniUIDocument", OMNI_BUNDLE, @"Info item accessibility label");
    }
    if (self.useCompactBarButtonItemsIfApplicable) {
        BOOL isHorizontallyCompact = self.document.documentViewController.traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassCompact;
        BOOL isVerticallyCompact = self.document.documentViewController.traitCollection.verticalSizeClass == UIUserInterfaceSizeClassCompact;
        NSString *imageName = (isHorizontallyCompact || isVerticallyCompact) ? @"OUIToolbarInfo-Compact" : @"OUIToolbarInfo";
        _infoBarButtonItem.image = [UIImage imageNamed:imageName inBundle:[OUIInspector bundle] compatibleWithTraitCollection:NULL];
    }
    return _infoBarButtonItem;
}

- (UIBarButtonItem *)uniqueInfoBarButtonItem;
{
    UIBarButtonItem *infoBarButtonItem = [OUIInspector inspectorOUIBarButtonItemWithTarget:self action:@selector(_showInspector:)];
    infoBarButtonItem.accessibilityLabel = NSLocalizedStringFromTableInBundle(@"Info", @"OmniUIDocument", OMNI_BUNDLE, @"Info item accessibility label");

    if (self.useCompactBarButtonItemsIfApplicable) {
        BOOL isHorizontallyCompact = self.document.documentViewController.traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassCompact;
        BOOL isVerticallyCompact = self.document.documentViewController.traitCollection.verticalSizeClass == UIUserInterfaceSizeClassCompact;
        NSString *imageName = (isHorizontallyCompact || isVerticallyCompact) ? @"OUIToolbarInfo-Compact" : @"OUIToolbarInfo";
        infoBarButtonItem.image = [UIImage imageNamed:imageName inBundle:[OUIInspector bundle] compatibleWithTraitCollection:NULL];
    }

    return infoBarButtonItem;
}

- (IBAction)makeNewDocument:(id)sender;
{
    if ([self canPerformAction:_cmd withSender:sender])
        [_documentPicker.selectedScopeViewController newDocument:sender];
}

- (void)closeDocument:(id)sender;
{
    if ([sender isKindOfClass:[UIKeyCommand class]] && [[UIMenuController sharedMenuController] isMenuVisible]) {
        [[UIMenuController sharedMenuController] setMenuVisible:NO animated:YES];
    }
    
    // Update the modification date in case the doc picker is sorting by date and the file save hasn't landed yet.
    if (self.document.hasUnsavedChanges) {
        self.document.fileItem.userModificationDate = [NSDate date];
    }
    
    [self closeDocumentWithCompletionHandler:^{
        [_documentPicker dismissViewControllerAnimated:YES completion:nil];
    }];
}

- (void)closeAndDismissDocumentWithCompletionHandler:(void (^)(void))completionHandler
{
    [self closeDocumentWithCompletionHandler:^{
        [_documentPicker dismissViewControllerAnimated:YES completion:completionHandler];
    }];
}

- (void)closeDocumentWithCompletionHandler:(void(^)(void))completionHandler;
{
    OBPRECONDITION(_document);
    
    if (!_document) {
        if (completionHandler)
            completionHandler();
        return;
    }
    
    completionHandler = [completionHandler copy]; // capture scope
    
    OUIWithoutAnimating(^{
        [_window endEditing:YES];
        [_window layoutIfNeeded];
        
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
    UIActivityIndicatorView *closingDocumentIndicatorView = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    closingDocumentIndicatorView.color = viewToSave.window.tintColor;
    CGRect superviewBounds = viewToSave.bounds;
    closingDocumentIndicatorView.center = (CGPoint){
        .x = superviewBounds.size.width / 2,
        .y = superviewBounds.size.height / 2
    };
    [viewToSave addSubview:closingDocumentIndicatorView];
    [viewToSave bringSubviewToFront:closingDocumentIndicatorView];
    [closingDocumentIndicatorView startAnimating];

    OUIInteractionLock *lock = [OUIInteractionLock applicationLock];
    [_documentPicker navigateToContainerForItem:_document.fileItem dismissingAnyOpenDocument:NO animated:NO];
    
    OBStrongRetain(_document);
    [_document closeWithCompletionHandler:^(BOOL success){
        [closingDocumentIndicatorView removeFromSuperview];
        
        // Give the document a chance to break retain cycles.
        [_document didClose];
        self.launchAction = nil;
        
        // Doing the -autorelease in the completion handler wasn't late enough. This may not be either...
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            OBASSERT([NSThread isMainThread]);
            OBStrongRelease(_document);
        }];
        
        // If the document was saved, it will have already updated *its* previews, if we were launched into a document w/o the document picker ever being visible, we might not have previews loaded for other documents
        [OUIDocumentPreview populateCacheForFileItems:_documentStore.mergedFileItems completionHandler:^{
            [lock unlock];
            
            if (completionHandler)
                completionHandler();
            
            [self _setDocument:nil];
            [_previewGenerator documentClosed];
        }];
    }];
}

- (void)documentDidDisableEnditing:(OUIDocument *)document;
{
    OBPRECONDITION(document.editingDisabled == YES); // When we end editing, we'll look at this and ignore the rename request.
    
    OUIWithoutAnimating(^{
        // <bug:///93505> (Not explicitly ending editing of in-document rename text field on -[OUIDocument disableEditing]) - We used to explicitly end editing of the in-document rename text field when we recieved -[OUIDocumnet disableEditing] via a call to [[OUIDocumentAppController controller] documentDidDisableEnditing:self]. After some testing, it looks like when we set self.viewControllerToPresent.view.userInteractionEnabled = NO in -[OUIDocument disableEditing] that goes thourgh and calls resignFirstResponder for us on the textField. Do we still need to do it explicitly or just trust that disableing a view's userInteraction will do it for us?
//        [_documentTitleTextField endEditing:YES];
    });
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

- (OUIDocument *)document;
{
    return _document;
}

- (void)invalidateDocumentPreviews;
{
    [OUIDocumentPreview invalidateDocumentPreviewsWithCompletionHandler:^{
        [_previewGenerator enqueuePreviewUpdateForFileItemsMissingPreviews:_documentStore.mergedFileItems];
    }];
}

- (void)openDocument:(ODSFileItem *)fileItem;
{
    [self _openDocument:fileItem fileItemToRevealFrom:fileItem isOpeningFromPeek:NO willPresentHandler:nil completionHandler:nil];
}

- (void)openDocument:(ODSFileItem *)fileItem fromPeekWithWillPresentHandler:(void (^)(OUIDocumentOpenAnimator *openAnimator))willPresentHandler completionHandler:(void (^)(void))completionHandler;
{
    [self _openDocument:fileItem fileItemToRevealFrom:nil isOpeningFromPeek:YES willPresentHandler:willPresentHandler completionHandler:completionHandler];
}

- (void)_openDocument:(ODSFileItem *)fileItemToOpen fileItemToRevealFrom:(nullable ODSFileItem *)fileItemToRevealFrom isOpeningFromPeek:(BOOL)isOpeningFromPeek willPresentHandler:(void (^)(OUIDocumentOpenAnimator *openAnimator))willPresentHandler completionHandler:(void (^)(void))completionHandler;
{
    OBPRECONDITION([NSThread isMainThread]);
    OBPRECONDITION(fileItemToOpen);
    OBPRECONDITION(fileItemToOpen.isDownloaded);
    
    if (!isOpeningFromPeek) {
        [_documentPicker navigateToContainerForItem:fileItemToOpen dismissingAnyOpenDocument:YES animated:NO];
        [_documentPicker.selectedScopeViewController _applicationWillOpenDocument];
    }
    
    void (^onFail)(void) = ^{
        if (!isOpeningFromPeek) {
            [self _fadeInDocumentPickerScrollingToFileItem:fileItemToOpen];
        }
        _isOpeningURL = NO;
    };
    onFail = [onFail copy];

    NSString *symlinkDestination = [[NSFileManager defaultManager] destinationOfSymbolicLinkAtPath:[fileItemToOpen.fileURL path] error:NULL];
    if (symlinkDestination != nil) {
        NSString *originalPath = [fileItemToOpen.fileURL path];
        NSString *targetPath = [originalPath stringByResolvingSymlinksInPath];
        if (targetPath == nil || OFISEQUAL(targetPath, originalPath)) {
            onFail();
            return;
        }

        // Look for the target in the fileItem's scope
        NSURL *targetURL = [NSURL fileURLWithPath:targetPath];
        ODSScope *originalScope = fileItemToOpen.scope;
        if (![originalScope isFileInContainer:targetURL]) {
            onFail();
            return;
        }

        ODSFileItem *targetItem = [originalScope fileItemWithURL:targetURL];
        [self _openDocument:targetItem fileItemToRevealFrom:targetItem isOpeningFromPeek:NO willPresentHandler:nil completionHandler:nil];
        return;
    }
    
    OUIActivityIndicator *activityIndicator = nil;
    if (!isOpeningFromPeek) {
        OUIDocumentPickerFileItemView *fileItemView = [_documentPicker.selectedScopeViewController.mainScrollView fileItemViewForFileItem:fileItemToRevealFrom];
        if (fileItemView) {
            activityIndicator = [OUIActivityIndicator showActivityIndicatorInView:fileItemView withColor:self.window.tintColor];
        }
        else if (self.window.rootViewController == _documentPicker) {
            activityIndicator = [OUIActivityIndicator showActivityIndicatorInView:_documentPicker.view withColor:self.window.tintColor];
        }
    }
    
    onFail = [onFail copy];
    willPresentHandler = [willPresentHandler copy];
    completionHandler = [completionHandler copy];
    
    void (^doOpen)(void) = ^{
        Class cls = [self documentClassForURL:fileItemToOpen.fileURL];
        OBASSERT(OBClassIsSubclassOfClass(cls, [OUIDocument class]));

        __autoreleasing NSError *error = nil;
        OUIDocument *document = [[cls alloc] initWithExistingFileItem:fileItemToOpen error:&error];
        if (!document) {
            OUI_PRESENT_ERROR_FROM(error, self.window.rootViewController);
            onFail();
            return;
        }

        OUIInteractionLock *lock = [OUIInteractionLock applicationLock];

        [document openWithCompletionHandler:^(BOOL success){
            if (!success) {
                OUIDocumentHandleDocumentOpenFailure(document, nil);

                [activityIndicator hide];
                [lock unlock];

                onFail();
                return;
            }
            
            OBASSERT([NSThread isMainThread]);
            [self _setDocument:document];
            _isOpeningURL = NO;
            
            UIViewController *presentFromViewController = _documentPicker;
            if (!presentFromViewController)
                presentFromViewController = _documentPicker;
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

            [self mainThreadFinishedLoadingDocument:document];
            
            // Might be a newly created document that was never edited and trivially returns YES to saving. Make sure there is an item before overwriting our last default value.
            NSURL *url = _document.fileURL;
            ODSFileItem *fileItem = [_documentStore fileItemWithURL:url];
            if (fileItem) {
                self.launchAction = [NSArray arrayWithObjects:OpenAction, [url absoluteString], nil];
            }
            
            // Wait until the document is opened to do this, which will let cache entries from opening document A be used in document B w/o being flushed.
            [OAFontDescriptor forgetUnusedInstances];
            
            // UIWindow will automatically create an undo manager if one isn't found along the responder chain. We want to be darn sure that don't end up getting two undo managers and accidentally splitting our registrations between them.
            OBASSERT([_document undoManager] == [_document.documentViewController undoManager]);
            OBASSERT([_document undoManager] == [_document.documentViewController.view undoManager]); // Does your view controller implement -undoManager? We don't do this for you right now.
            
            if ([documentViewController respondsToSelector:@selector(restoreDocumentViewState:)]) {
                OFFileEdit *fileEdit = fileItem.fileEdit;
                if (fileEdit) // New document
                    [documentViewController restoreDocumentViewState:[OUIDocumentAppController documentStateForFileEdit:fileEdit]];
            }
            
            BOOL animateDocument = YES;
            if (_window.rootViewController != _documentPicker) {
                [_documentPicker showDocuments];
                _window.rootViewController = _documentPicker;
                [_window makeKeyAndVisible];
                
                [self handleCachedSpecialURLIfNeeded];
                animateDocument = NO;
            }
            
            OUIDocumentOpenAnimator *animator = [OUIDocumentOpenAnimator sharedAnimator];
            animator.documentPicker = _documentPicker;
            animator.fileItem = fileItemToRevealFrom;
            animator.actualFileItem = fileItem;
            
            animator.isOpeningFromPeek = isOpeningFromPeek;
            animator.backgroundSnapshotView = nil;
            animator.previewSnapshotView = nil;
            animator.previewRect = CGRectZero;
            
            if (isOpeningFromPeek && willPresentHandler) {
                willPresentHandler(animator);
            }
            
            toPresent.transitioningDelegate = animator;
            toPresent.modalPresentationStyle = UIModalPresentationFullScreen;
            
            [presentFromViewController presentViewController:toPresent animated:animateDocument completion:^{
                if ([documentViewController respondsToSelector:@selector(documentFinishedOpening)])
                    [documentViewController documentFinishedOpening];
                [activityIndicator hide];
                [lock unlock];
                
                // Ensure that when the document is closed we'll be using a filter that shows it.
                [_documentPicker.selectedScopeViewController ensureSelectedFilterMatchesFileItem:fileItem];
                
                if (completionHandler) {
                    completionHandler();
                }
            }];
        }];
    };
    
    if (_document) {
        // If we have a document open, wait for it to close before starting to open the new one. This can happen if the user backgrounds the app and then taps on a document in Mail.
        doOpen = [doOpen copy];
        
        OUIInteractionLock *lock = [OUIInteractionLock applicationLock];
        
        [_document closeWithCompletionHandler:^(BOOL success) {
            [self _setDocument:nil];
            UINavigationController *topLevelNavController = self.documentPicker.topLevelNavigationController;
            if ([topLevelNavController presentedViewController]) {
                [topLevelNavController dismissViewControllerAnimated:NO completion:^{
                    doOpen();
                    [lock unlock];
                }];
            } else {
                doOpen();
                [lock unlock];
            }
        }];
    } else {
        // Just open immediately
        doOpen();
    }
}

- (BOOL)shouldOpenOnlineHelpOnFirstLaunch;
{
    // Apps may wish to override this behavior in a subclass
    
    // Screenshot automation should pass a launch arg to request special behavior—in this case, not showing the help on very first launch, to keep it more consistent with subsequent launches and give us one less thing to special case.
     if ([[NSUserDefaults standardUserDefaults] boolForKey:@"TAKING_SCREENSHOTS"]) {
         return NO;
     } else {
         return YES;
     }
}

#pragma mark -
#pragma mark Sample documents

- (NSInteger)builtInResourceVersion;
{
    return 1;
}

- (NSString *)sampleDocumentsDirectoryTitle;
{
    return NSLocalizedStringFromTableInBundle(@"Restore Sample Documents", @"OmniUIDocument", OMNI_BUNDLE, @"Restore Sample Documents Title");
}

- (NSURL *)sampleDocumentsDirectoryURL;
{
    return [[NSBundle mainBundle] URLForResource:@"Samples" withExtension:@""];
}

- (NSPredicate *)sampleDocumentsFilterPredicate;
{
    // For subclasses to overide.
    return nil;
}

- (void)copySampleDocumentsToUserDocumentsWithCompletionHandler:(void (^)(NSDictionary *nameToURL))completionHandler;
{
    OBPRECONDITION(_localScope);
    
    NSURL *samplesDirectoryURL = [self sampleDocumentsDirectoryURL];
    if (!samplesDirectoryURL) {
        if (completionHandler)
            completionHandler(@{});
        return;
    }
        
    [self copySampleDocumentsFromDirectoryURL:samplesDirectoryURL toScope:_localScope stringTableName:[self stringTableNameForSampleDocuments] completionHandler:completionHandler];
}

- (void)copySampleDocumentsFromDirectoryURL:(NSURL *)sampleDocumentsDirectoryURL toScope:(ODSScope *)scope stringTableName:(NSString *)stringTableName completionHandler:(void (^)(NSDictionary *nameToURL))completionHandler;
{
    // This should be called as part of an after-scan action so we can properly unique names.
    OBPRECONDITION(scope);
    OBPRECONDITION(scope);
    OBPRECONDITION(scope.hasFinishedInitialScan);
    
    completionHandler = [completionHandler copy];
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    __autoreleasing NSError *directoryContentsError = nil;
    NSArray *sampleURLs = [fileManager contentsOfDirectoryAtURL:sampleDocumentsDirectoryURL includingPropertiesForKeys:nil options:0 error:&directoryContentsError];
    if (!sampleURLs) {
        NSLog(@"Unable to find sample documents at %@: %@", sampleDocumentsDirectoryURL, [directoryContentsError toPropertyList]);
        if (completionHandler)
            completionHandler(nil);
        return;
    }
    
    NSDate *lastInstallDate = [[NSDate alloc] initWithXMLString:[[NSUserDefaults standardUserDefaults] stringForKey:@"SampleDocumentsHaveBeenCopiedToUserDocumentsDate"]];

    NSOperationQueue *callingQueue = [NSOperationQueue currentQueue];
    NSMutableDictionary *nameToURL = [NSMutableDictionary dictionary];
    
    for (NSURL *sampleURL in sampleURLs) {
        NSString *sampleName = [[sampleURL lastPathComponent] stringByDeletingPathExtension];
        
        NSString *localizedTitle = [[NSBundle mainBundle] localizedStringForKey:sampleName value:sampleName table:stringTableName];
        if ([NSString isEmptyString:localizedTitle]) {
            OBASSERT_NOT_REACHED("No localization available for sample document name");
            localizedTitle = sampleName;
        }
        NSURL *existingFileURL = [scope.documentsURL URLByAppendingPathComponent:scope.rootFolder.relativePath isDirectory:YES];
        existingFileURL = [existingFileURL URLByAppendingPathComponent:localizedTitle];
        existingFileURL = [existingFileURL URLByAppendingPathExtension:[sampleURL pathExtension]];

        void (^addAction)(void) = ^{
            [scope addDocumentInFolder:scope.rootFolder baseName:localizedTitle fromURL:sampleURL option:ODSStoreAddByCopyingSourceToAvailableDestinationURL completionHandler:^(ODSFileItem *duplicateFileItem, NSError *error){
                if (!duplicateFileItem) {
                    NSLog(@"Failed to copy sample document %@: %@", sampleURL, [error toPropertyList]);
                    return;
                }
                [callingQueue addOperationWithBlock:^{
                    BOOL skipBackupAttributeSuccess = [[NSFileManager defaultManager] addExcludedFromBackupAttributeToItemAtURL:duplicateFileItem.fileURL error:NULL];
#ifdef OMNI_ASSERTIONS_ON
                    OBPOSTCONDITION(skipBackupAttributeSuccess);
#else
                    (void)skipBackupAttributeSuccess;
#endif
                    OBASSERT([nameToURL objectForKey:sampleName] == nil);
                    [nameToURL setObject:duplicateFileItem.fileURL forKey:sampleName];
                }];
            }];
        };

        if ([fileManager fileExistsAtPath:[existingFileURL path]]) {
            NSDictionary *oldResourceAttributes = [fileManager attributesOfItemAtPath:[existingFileURL path] error:NULL];
            NSDate *oldResourceDate = [oldResourceAttributes fileModificationDate];
            ODSFileItem *existingFileItem = [scope fileItemWithURL:existingFileURL];
            // We are going to treat all sample documents which were previously copied over by our pre-universal apps as customized.  The logic here differs from what we do on the Mac.  On the Mac we use if (lastInstallDate != nil && ...
            if (!lastInstallDate || [oldResourceDate isAfterDate:lastInstallDate]) {
                NSString *customizedTitle = [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"CustomizedSampleDocumentName", @"OmniUIDocument", OMNI_BUNDLE, @"%@ Customized", @"moved aside custom sample document name"), localizedTitle];
                __block ODSScope *blockScope = scope;
                [scope addDocumentInFolder:scope.rootFolder baseName:customizedTitle fromURL:existingFileURL option:ODSStoreAddByCopyingSourceToAvailableDestinationURL completionHandler:^(ODSFileItem *duplicateFileItem, NSError *error){
                    [blockScope deleteItems:[NSSet setWithObject:existingFileItem] completionHandler:^(NSSet *deletedFileItems, NSArray *errorsOrNil) {
                        addAction();
                    }];
                }];
            } else {
                [scope deleteItems:[NSSet setWithObject:existingFileItem] completionHandler:^(NSSet *deletedFileItems, NSArray *errorsOrNil) {
                    addAction();
                }];
            }
        } else {
            addAction();
        }

    }
    
    // Wait for all the copies to finish
    [scope afterAsynchronousFileAccessFinishes:^{
        // Wait for the updates of the nameToURL dictionary
        [callingQueue addOperationWithBlock:^{
            if (completionHandler)
                completionHandler(nameToURL);
        }];
    }];
}

- (NSString *)stringTableNameForSampleDocuments;
{
    return @"SampleNames";
}

- (NSString *)localizedNameForSampleDocumentNamed:(NSString *)documentName;
{
    return [[NSBundle mainBundle] localizedStringForKey:documentName value:documentName table:[self stringTableNameForSampleDocuments]];
}

- (NSURL *)URLForSampleDocumentNamed:(NSString *)name ofType:(NSString *)fileType;
{
    NSString *extension = OFPreferredPathExtensionForUTI(fileType);
    if (!extension)
        OBRequestConcreteImplementation(self, _cmd); // UTI not registered in the Info.plist?
    
    NSString *fileName = [name stringByAppendingPathExtension:extension];
    
    return [[self sampleDocumentsDirectoryURL] URLByAppendingPathComponent:fileName];
}

#pragma mark - Background fetch

- (NSArray <ODSFileItem *> *)recentlyEditedFileItems
{
    ODSScope *trashScope = [ODSScope trashScope];
    NSArray *localItems = [[_documentStore mergedFileItems] sortedArrayUsingDescriptors:[OUIDocumentPickerViewController sortDescriptorsForSortType:OUIDocumentPickerItemSortByDate]];
    localItems = [localItems filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(ODSFileItem *  _Nonnull fileItem, NSDictionary <NSString *,id> * _Nullable bindings) {
        return (fileItem.scope != trashScope);
    }]];
    
    if ([_document hasUnsavedChanges]) {
        // quick fix for backgrounding with a document open doesn't reliably put the open document at the top of the list
        NSUInteger index = [localItems indexOfObject:_document.fileItem];
        if (index != NSNotFound && index != 0) {
            NSMutableArray *mutableItems = [localItems mutableCopy];
            [mutableItems removeObject:_document.fileItem];
            [mutableItems insertObject:_document.fileItem atIndex:0];
            localItems = mutableItems;
        }
    }
    
    NSUInteger numberOfItemsToReturn = 5;
    if (localItems.count > numberOfItemsToReturn){
        localItems = [localItems subarrayWithRange:NSMakeRange(0, numberOfItemsToReturn)];
    }
    
    return localItems;
}

static OFPreference *_recentlyOpenedBookmarksPreference(void)
{
    static dispatch_once_t onceToken;
    static OFPreference *preference = nil;
    
    dispatch_once(&onceToken, ^{
        preference = [OFPreference preferenceForKey:@"OUIRecentlyOpenedDocuments" defaultValue:@[]];
    });
    return preference;
}

static NSMutableArray *_arrayByRemovingBookmarksMatchingURL(NSArray <NSData *> *bookmarks, NSURL *url)
{
    NSMutableArray *result = [NSMutableArray array];
    for (NSData *bookmarkData in bookmarks) {
        NSURL *resolvedURL = [NSURL URLByResolvingBookmarkData:bookmarkData options:0 relativeToURL:nil bookmarkDataIsStale:NULL error:NULL];
        if (OFNOTEQUAL(resolvedURL, url)) {
            [result addObject:bookmarkData];
        }
    }
    return result;
}

- (void)_noteRecentlyOpenedDocumentURL:(NSURL *)url;
{
    if (url == nil)
        return;

    NSURL *securedURL = nil;
    if ([url startAccessingSecurityScopedResource])
        securedURL = url;

    NSError *bookmarkError = nil;
    NSData *bookmarkData = [url bookmarkDataWithOptions:0 /* docs say to use NSURLBookmarkCreationWithSecurityScope, but SDK says not available on iOS */ includingResourceValuesForKeys:nil relativeToURL:nil error:&bookmarkError];
    [securedURL stopAccessingSecurityScopedResource];
    if (bookmarkData != nil) {
        NSArray *filteredBookmarks = _arrayByRemovingBookmarksMatchingURL([_recentlyOpenedBookmarksPreference() arrayValue], url); // We're replacing any existing bookmarks to this URL
        NSMutableArray *recentlyOpenedBookmarks = [[NSMutableArray alloc] initWithArray:filteredBookmarks];
        [recentlyOpenedBookmarks insertObject:bookmarkData atIndex:0];
        const NSUInteger archiveBookmarkLimit = 20; // We don't display all of these in our menu, but we archive extras in case some have gone missing
        if (recentlyOpenedBookmarks.count > archiveBookmarkLimit)
            [recentlyOpenedBookmarks removeObjectsInRange:NSMakeRange(archiveBookmarkLimit, recentlyOpenedBookmarks.count - archiveBookmarkLimit)];
        [_recentlyOpenedBookmarksPreference() setArrayValue:recentlyOpenedBookmarks];
        [self _updateShortcutItems];
    } else {
#ifdef DEBUG
        NSLog(@"Unable to create bookmark for %@: %@", url, [bookmarkError toPropertyList]);
#endif
    }
}

- (NSArray <ODSFileItem *> *)recentlyOpenedFileItems;
{
    NSArray *recentlyOpenedBookmarks = [_recentlyOpenedBookmarksPreference() arrayValue];
    NSMutableArray *recentlyOpenedFileItems = [[NSMutableArray alloc] init];
    for (NSData *bookmarkData in recentlyOpenedBookmarks) {
        NSURL *resolvedURL = [NSURL URLByResolvingBookmarkData:bookmarkData options:0 relativeToURL:nil bookmarkDataIsStale:NULL error:NULL];
        if (resolvedURL != nil) {
            ODSFileItem *fileItem = [_documentStore fileItemWithURL:resolvedURL];
            if (fileItem != nil && !fileItem.scope.isTrash) {
                [recentlyOpenedFileItems addObjectIfAbsent:fileItem];
            }
        }
    }

    return recentlyOpenedFileItems;
}

// OmniPresence-enabled applications should implement -application:performFetchWithCompletionHandler: to call this. We cannot name this method -application:performFetchWithCompletionHandler: since UIKit will throw an exception if you declare 'fetch' in your UIBackgroundModes.
- (void)performFetchWithCompletionHandler:(void (^)(UIBackgroundFetchResult result))completionHandler_;
{
    OBPRECONDITION([[UIApplication sharedApplication] isProtectedDataAvailable], "Otherwise we'll need to delay this sync attempt, wait for data protection to become available, timeout if it doesn't soon enough, etc.");
    
    DEBUG_FETCH(1, @"Fetch requested by system");
    if (_syncAgent == nil) {
        OBASSERT_NOT_REACHED("Should always create the sync agent, or the app should not have requested background fetching?"); // Or maybe there are multiple subsystems that might need to fetch -- we need some coordination of when to call the completion handler in that case.
        if (completionHandler_)
            completionHandler_(UIBackgroundFetchResultNoData);
        return;
    }
    
    // We need to reply to the completion handler we were given promptly.
    // We'll clear this once we've called it so that other calls can be avoided.
    __block typeof(completionHandler_) handler = [completionHandler_ copy];

    // Reply to the completion handler as soon as possible if a transfer starts rather than waiting for the whole sync to finish
    // '__block' here is so that the -removeObserver: in the block will not capture the initial 'nil' value.
    __block id transferObserver = [[NSNotificationCenter defaultCenter] addObserverForName:OFXAccountTransfersNeededNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note){
        if (handler) {
            DEBUG_FETCH(1, @"Found new data -- %@", [note userInfo][OFXAccountTransfersNeededDescriptionKey]);
            handler(UIBackgroundFetchResultNewData);
            handler = nil;
        }
        [[NSNotificationCenter defaultCenter] removeObserver:transferObserver];
    }];

    // If we don't hear anything back from the sync for a significant time, report that there is no data (though we let the sync keep running until it times out or we get put back to sleep/killed).
    OFAfterDelayPerformBlock(OUIBackgroundFetchTimeout, ^{
        if (handler) {
            DEBUG_FETCH(1, @"Timed out");
            handler(UIBackgroundFetchResultNoData);
            handler = nil;
        }
     });
    
    [_syncAgent sync:^{
        // This is ugly for our purposes here, but the -sync: completion handler can return before any transfers have started. Making the completion handler be after all this work is even uglier. In particular, automatic download of small docuemnts is controlled by OFXDocumentStoreScope. Wait for a bit longer for stuff to filter through the systems.
        // Note also, that OFXAgentActivity will keep us alive while transfers are happening.
        
        if (!handler)
            return; // Status already reported
        
        DEBUG_FETCH(1, @"Sync request completed -- waiting for a bit to determine status");
        OFAfterDelayPerformBlock(5.0, ^{
            // If we have two accounts and one is offline, we'll let the 'new data' win on the other account (if there is new data).
            if (handler) {
                BOOL foundError = NO;
                for (OFXServerAccount *account in _syncAgent.accountRegistry.validCloudSyncAccounts) {
                    if (account.lastError) {
                        DEBUG_FETCH(1, @"Fetch for account %@ encountered error %@", [account shortDescription], [account.lastError toPropertyList]);
                        foundError = YES;
                    }
                }
                
                if (foundError) {
                    DEBUG_FETCH(1, @"Sync resulted in error");
                    handler(UIBackgroundFetchResultFailed);
                } else {
                    DEBUG_FETCH(1, @"Sync finished without any changes");
                    handler(UIBackgroundFetchResultNoData);
                }
                handler = nil;
            }
        });
    }];
}

#pragma mark - OUIAppController subclass

- (UIResponder *)defaultFirstResponder;
{
    return [_document defaultFirstResponder];
    // <bug:///93506> (Should we override defaultFirstResponder in OUIDocumentAppController anymore?)
    // Make the document picker or the application supplied document view controller the fallback for getting first responder status.
//    return _mainViewController.innerViewController;
    return [super defaultFirstResponder];
}

- (void)importFromExternalContainer:(id)sender;
{
    UIDocumentPickerViewController *pickerViewController = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:[self _expandedTypesFromPrimaryTypes:[self _viewableFileTypes]] inMode:UIDocumentPickerModeImport];
    [self _presentExternalDocumentPicker:pickerViewController completionBlock:^(NSURL *url) {
        [_externalScopeManager importExternalDocumentFromURL:url];
    }];
}

- (void)linkDocumentFromExternalContainer:(id)sender;
{
    UIDocumentPickerViewController *pickerViewController = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:[self _expandedTypesFromPrimaryTypes:[self editableFileTypes]] inMode:UIDocumentPickerModeOpen];
    [self _presentExternalDocumentPicker:pickerViewController completionBlock:^(NSURL *url) {
        [_externalScopeManager linkExternalDocumentFromURL:url];
    }];
}

- (NSArray *)additionalAppMenuOptionsAtPosition:(OUIAppMenuOptionPosition)position;
{
    NSMutableArray *options = [NSMutableArray arrayWithArray:[super additionalAppMenuOptionsAtPosition:position]];
    
    // Add ways to get more documents only if we are in a valid scope, for now.
    OUIDocumentPickerViewController *scopeViewController = _documentPicker.selectedScopeViewController;
    if (scopeViewController != nil && scopeViewController.canAddDocuments && !scopeViewController.selectedScope.isExternal) {
        switch (position) {
            case OUIAppMenuOptionPositionAfterReleaseNotes:
            {
                UIImage *image = [[UIImage imageNamed:@"OUIMenuItemRestoreSampleDocuments" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
                [options addObject:[OUIMenuOption optionWithFirstResponderSelector:@selector(restoreSampleDocuments:) title:[[OUIDocumentAppController controller] sampleDocumentsDirectoryTitle] image:image]];
                break;
            }

            case OUIAppMenuOptionPositionAtEnd:
            {
                UIImage *importImage = [[UIImage imageNamed:@"OUIMenuItemImport" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];

                // Import from WebDAV
                OUIMenuOption *importOption = [OUIMenuOption optionWithTitle:NSLocalizedStringFromTableInBundle(@"Copy from WebDAV", @"OmniUIDocument", OMNI_BUNDLE, @"gear menu item") image:importImage action:^{
                    OUIImportExportAccountListViewController *accountList = [[OUIImportExportAccountListViewController alloc] initForExporting:NO];
                    accountList.title = NSLocalizedStringFromTableInBundle(@"Import", @"OmniUIDocument", OMNI_BUNDLE, @"import sheet title");
                    UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:accountList];
                    accountList.finished = ^(OFXServerAccount *account) {
                        if (!account) {
                            [navigationController dismissViewControllerAnimated:YES completion:nil];
                        } else {
                            __autoreleasing NSError *error;
                            OUIWebDAVSyncListController *webDavList = [[OUIWebDAVSyncListController alloc] initWithServerAccount:account exporting:NO error:&error];
                            if (!webDavList)
                                OUI_PRESENT_ERROR_FROM(error, navigationController);
                            else {
                                [navigationController pushViewController:webDavList animated:YES];
                            }
                        }
                    };
                    
                    navigationController.modalPresentationStyle = UIModalPresentationFormSheet;
                    [self.window.rootViewController presentViewController:navigationController animated:YES completion:nil];
                }];
                [options addObject:importOption];

                if ([[OUIDocumentProviderPreferencesViewController shouldEnableDocumentProvidersPreference] boolValue] == YES) {
                    // Import from external container via document picker
                    [options addObject:[OUIMenuOption optionWithFirstResponderSelector:@selector(importFromExternalContainer:) title:NSLocalizedStringFromTableInBundle(@"Copy from…", @"OmniUIDocument", OMNI_BUNDLE, @"gear menu item") image:importImage]];
                }

                break;
            }

            default:
                OBASSERT_NOT_REACHED("Unknown possition");
                break;
        }
    }

    return options;
}

- (OUIWebViewController *)showNewsURLString:(NSString *)urlString evenIfShownAlready:(BOOL)showNoMatterWhat
{
    if (self.readyToShowNews) {
        return [super showNewsURLString:urlString evenIfShownAlready:showNoMatterWhat];
        
    } else {
        self.newsURLStringToShowWhenReady = urlString;
        return nil;
    }
}

- (void)handleCachedSpecialURLIfNeeded
{
    if (_specialURLToHandle != nil)
    {
        [self handleSpecialURL:_specialURLToHandle];
        _specialURLToHandle = nil;
    }
}

#pragma mark - UIResponder subclass

- (NSArray *)keyCommands;
{
    return [OUIKeyCommands keyCommandsWithCategories:@"document-controller"];
}

- (BOOL)canPerformAction:(SEL)action withSender:(id)sender;
{
    if (action == @selector(undo:))
        return [_document.undoManager canUndo];
    
    if (action == @selector(redo:))
        return [_document.undoManager canRedo];
    
    if (action == @selector(makeNewDocument:))
        return _document == nil && [_documentPicker.selectedScopeViewController canPerformAction:@selector(newDocument:) withSender:sender];

    if (action == @selector(closeDocument:))
        return _document != nil;
    
    return [super canPerformAction:action withSender:sender];
}

#pragma mark - API

- (NSArray *)_expandedTypesFromPrimaryTypes:(NSArray *)primaryTypes;
{
    NSMutableArray *expandedTypes = [NSMutableArray array];
    [expandedTypes addObjectsFromArray:primaryTypes];
    for (NSString *primaryType in primaryTypes) {
        NSArray *fileExtensions = CFBridgingRelease(UTTypeCopyAllTagsWithClass((__bridge CFStringRef)primaryType, kUTTagClassFilenameExtension));
        for (NSString *fileExtension in fileExtensions) {
            NSString *expandedType = (NSString *)CFBridgingRelease(UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, (__bridge CFStringRef)fileExtension, NULL));
            if (expandedType != nil && ![expandedTypes containsObject:expandedType]) {
                [expandedTypes addObject:expandedType];
            }
        }
    }
    return expandedTypes;
}

- (NSArray *)editableFileTypes;
{
    if (!_editableFileTypes) {
        NSMutableArray *editableFileTypes = [NSMutableArray array];
        
        NSArray *documentTypes = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleDocumentTypes"];
        for (NSDictionary *documentType in documentTypes) {
            NSString *role = [documentType objectForKey:@"CFBundleTypeRole"];
            OBASSERT([role isEqualToString:@"Editor"] || [role isEqualToString:@"Viewer"]);
            if ([role isEqualToString:@"Editor"]) {
                NSArray *contentTypes = [documentType objectForKey:@"LSItemContentTypes"];
                for (NSString *contentType in contentTypes)
                    [editableFileTypes addObject:[contentType lowercaseString]];
            }
        }

        _editableFileTypes = [editableFileTypes copy];
    }
    
    return _editableFileTypes;
}

- (NSArray *)_viewableFileTypes;
{
    return [[[self _roleByFileType] keyEnumerator] allObjects];
}

- (NSDictionary *)_roleByFileType;
{
    dispatch_once(&_roleByFileTypeOnce, ^{
        // Make a fast index of all our declared UTIs
        NSMutableDictionary *contentTypeRoles = [[NSMutableDictionary alloc] init];
        NSArray *documentTypes = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleDocumentTypes"];
        for (NSDictionary *documentType in documentTypes) {
            NSString *role = [documentType objectForKey:@"CFBundleTypeRole"];
            if (![role isEqualToString:@"Editor"] && ![role isEqualToString:@"Viewer"])
                continue;
            
            NSArray *contentTypes = [documentType objectForKey:@"LSItemContentTypes"];
            for (NSString *contentType in contentTypes)
                [contentTypeRoles setObject:role forKey:[contentType lowercaseString]];
        }
        
        _roleByFileType = [contentTypeRoles copy];
    });
    OBPOSTCONDITION(_roleByFileType != nil);
    return _roleByFileType;
}

- (BOOL)canViewFileTypeWithIdentifier:(NSString *)uti;
{
    OBPRECONDITION(!uti || [uti isEqualToString:[uti lowercaseString]]); // our cache uses lowercase keys.
    
    if (uti == nil)
        return NO;
    
    for (NSString *candidateUTI in [self _roleByFileType]) {
        if (OFTypeConformsTo(uti, candidateUTI))
            return YES;
    }
    
    return NO;
}

- (void)restoreSampleDocuments:(id)sender;
{
    OUIDocumentAppController *documentAppController = [OUIDocumentAppController controller];
    NSURL *sampleDocumentsURL = [documentAppController sampleDocumentsDirectoryURL];
    NSString *restoreSamplesViewControllerTitle = [documentAppController sampleDocumentsDirectoryTitle];
    NSPredicate *sampleDocumentsFilter = [documentAppController sampleDocumentsFilterPredicate];
    
    OUIRestoreSampleDocumentListController *restoreSampleDocumentsViewController = [[OUIRestoreSampleDocumentListController alloc] initWithSampleDocumentsURL:sampleDocumentsURL];
    restoreSampleDocumentsViewController.navigationItem.title = restoreSamplesViewControllerTitle;
    restoreSampleDocumentsViewController.fileFilterPredicate = sampleDocumentsFilter;
    
    UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:restoreSampleDocumentsViewController];
    navigationController.modalPresentationStyle = UIModalPresentationFormSheet;
    navigationController.modalTransitionStyle = UIModalTransitionStyleCoverVertical;
    
    [_documentPicker presentViewController:navigationController animated:YES completion:nil];
    
}

#pragma mark - ODSStoreDelegate

- (Class)documentStore:(ODSStore *)store fileItemClassForURL:(NSURL *)fileURL;
{
    return [ODSFileItem class];
}

- (NSString *)documentStoreBaseNameForNewFiles:(ODSStore *)store;
{
    return NSLocalizedStringFromTableInBundle(@"My Document", @"OmniUIDocument", OMNI_BUNDLE, @"Base name for newly created documents. This will have an number appended to it to make it unique.");
}

- (NSString *)documentStoreBaseNameForNewTemplateFiles:(ODSStore *)store;
{
    return NSLocalizedStringFromTableInBundle(@"My Template", @"OmniUIDocument", OMNI_BUNDLE, @"Base name for newly created templates. This will have an number appended to it to make it unique.");
}

- (NSArray *)documentStoreEditableDocumentTypes:(ODSStore *)store;
{
    return [self editableFileTypes];
}

- (void)presentSyncError:(NSError *)syncError forAccount:(OFXServerAccount *)account inViewController:(UIViewController *)viewController retryBlock:(void (^)(void))retryBlock;
{
    OBPRECONDITION(viewController);
    
    NSError *serverCertificateError = syncError.serverCertificateError;
    if (serverCertificateError != nil) {
        OUICertificateTrustAlert *certAlert = [[OUICertificateTrustAlert alloc] initForError:serverCertificateError];
        certAlert.shouldOfferTrustAlwaysOption = YES;
        certAlert.storeResult = YES;
        if (retryBlock) {
            certAlert.trustBlock = ^(OFCertificateTrustDuration trustDuration) {
                retryBlock();
            };
        }
        [certAlert findViewController:^{
            return viewController;
        }];
        [[[OUIAppController sharedController] backgroundPromptQueue] addOperation:certAlert];
        return;
    }
    
    NSError *displayError = OBFirstUnchainedError(syncError);

    NSError *httpError = [syncError underlyingErrorWithDomain:ODAVHTTPErrorDomain];
    while (httpError != nil && [httpError.userInfo objectForKey:NSUnderlyingErrorKey])
        httpError = [httpError.userInfo objectForKey:NSUnderlyingErrorKey];

    if (httpError != nil && [[httpError domain] isEqualToString:ODAVHTTPErrorDomain] && [[httpError.userInfo objectForKey:ODAVHTTPErrorDataContentTypeKey] isEqualToString:@"text/html"]) {
        OUIWebViewController *webController = [[OUIWebViewController alloc] init];
        webController.delegate = self;
        
        // webController.title = [displayError localizedDescription];
        (void)[webController view]; // Load the view so we get its navigation set up
        webController.navigationItem.leftBarButtonItem = nil; // We don't want a disabled "Back" button on our error page
        [webController loadData:[httpError.userInfo objectForKey:ODAVHTTPErrorDataKey] ofType:[httpError.userInfo objectForKey:ODAVHTTPErrorDataContentTypeKey]];
        UINavigationController *webNavigationController = [[UINavigationController alloc] initWithRootViewController:webController];
        webNavigationController.navigationBar.barStyle = UIBarStyleBlack;

        webNavigationController.modalPresentationStyle = UIModalPresentationOverCurrentContext;
        [viewController presentViewController:webNavigationController animated:YES completion:retryBlock];
        self.webViewController = webController;
        return;
    }

    NSMutableArray *messages = [NSMutableArray array];

    NSString *reason = [displayError localizedFailureReason];
    if (![NSString isEmptyString:reason])
        [messages addObject:reason];

    NSString *suggestion = [displayError localizedRecoverySuggestion];
    if (![NSString isEmptyString:suggestion])
        [messages addObject:suggestion];

    NSString *message = [messages componentsJoinedByString:@"\n"];

    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:[displayError localizedDescription] message:message preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *okAction = [UIAlertAction actionWithTitle:NSLocalizedStringFromTableInBundle(@"OK", @"OmniUIDocument", OMNI_BUNDLE, @"When displaying a sync error, this is the option to ignore the error.") style:UIAlertActionStyleDefault handler:^(UIAlertAction * __nonnull action) {}];
    [alertController addAction:okAction];

    if (account != nil) {
        UIAlertAction *editAction = [UIAlertAction actionWithTitle:NSLocalizedStringFromTableInBundle(@"Edit Credentials", @"OmniUIDocument", OMNI_BUNDLE, @"When displaying a sync error, this is the option to change the username and password.") style:UIAlertActionStyleDefault handler:^(UIAlertAction * __nonnull action) {

            void (^editCredentials)(void) = ^{
                [self.documentPicker editSettingsForAccount:account];
            };
            editCredentials = [editCredentials copy];
            if (_document) {
                [self closeDocumentWithCompletionHandler:^{
                    // Dismissing without animation and then immediately pushing into the top navigation controller causes the screen to be left blank. To prevent this, we dismiss with animation and use the completion handler to run the code that causes the push in the navigation controller.
                    // The document view controller isn't dismissed by -closeDocumentWithCompletionHandler:, which is arguably weird.
                    [self.documentPicker dismissViewControllerAnimated:YES completion:^{
                        editCredentials();
                    }];
                }];
            } else
                editCredentials();
        }];
        [alertController addAction:editAction];
    }

    if (retryBlock != NULL) {
        UIAlertAction *retryAction = [UIAlertAction actionWithTitle:NSLocalizedStringFromTableInBundle(@"Retry Sync", @"OmniUIDocument", OMNI_BUNDLE, @"When displaying a sync error, this is the option to retry syncing.") style:UIAlertActionStyleDefault handler:^(UIAlertAction * __nonnull action) {
            retryBlock();
        }];
        [alertController addAction:retryAction];
    }

    if ([MFMailComposeViewController canSendMail] && ODAVShouldOfferToReportError(syncError)) {
        UIAlertAction *reportAction = [UIAlertAction actionWithTitle:NSLocalizedStringFromTableInBundle(@"Report Error", @"OmniUIDocument", OMNI_BUNDLE, @"When displaying a sync error, this is the option to report the error.") style:UIAlertActionStyleDefault handler:^(UIAlertAction * __nonnull action) {
            NSString *body = [NSString stringWithFormat:@"\n%@\n\n%@\n", [[OUIAppController controller] fullReleaseString], [syncError toPropertyList]];
            [[OUIAppController controller] sendFeedbackWithSubject:@"Sync failure" body:body];
        }];
        [alertController addAction:reportAction];
    }
    [viewController presentViewController:alertController animated:YES completion:^{}];
}

- (void)warnAboutDiscardingUnsyncedEditsInAccount:(OFXServerAccount *)account withCancelAction:(void (^)(void))cancelAction discardAction:(void (^)(void))discardAction;
{
    if (cancelAction == NULL)
        cancelAction = ^{};

    if (account.usageMode != OFXServerAccountUsageModeCloudSync) {
        discardAction(); // This account doesn't sync, so there's nothing to warn about
        return;
    }

    assert(_syncAgent != nil); // Or we won't ever count anything!
    [_syncAgent countFileItemsWithLocalChangesForAccount:account completionHandler:^(NSError *errorOrNil, NSUInteger count) {
        if (count == 0) {
            discardAction(); // No unsynced changes
        } else {
            NSString *message;
            if (count == 1)
                message = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"The \"%@\" account has an edited document which has not yet been synced up to the cloud. Do you wish to discard those edits?", @"OmniUIDocument", OMNI_BUNDLE, @"Discard unsynced edits dialog: message format"), account.displayName, count];
            else if (count == NSNotFound)
                message = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"The \"%@\" account may have edited documents which have not yet been synced up to the cloud. Do you wish to discard any local edits?", @"OmniUIDocument", OMNI_BUNDLE, @"Discard unsynced edits dialog: message format"), account.displayName, count];
            else
                message = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"The \"%@\" account has %ld edited documents which have not yet been synced up to the cloud. Do you wish to discard those edits?", @"OmniUIDocument", OMNI_BUNDLE, @"Discard unsynced edits dialog: message format"), account.displayName, count];

            UIAlertController *alertController = [UIAlertController alertControllerWithTitle:NSLocalizedStringFromTableInBundle(@"Discard unsynced edits?", @"OmniUIDocument", OMNI_BUNDLE, @"Lose unsynced changes warning: title") message:message preferredStyle:UIAlertControllerStyleAlert];

            UIAlertAction *cancelAlertAction = [UIAlertAction actionWithTitle:NSLocalizedStringFromTableInBundle(@"Cancel", @"OmniUIDocument", OMNI_BUNDLE, @"Discard unsynced edits dialog: cancel button label") style:UIAlertActionStyleCancel handler:^(UIAlertAction * __nonnull action) {
                cancelAction();
            }];
            [alertController addAction:cancelAlertAction];

            UIAlertAction *discardAlertAction = [UIAlertAction actionWithTitle:NSLocalizedStringFromTableInBundle(@"Discard Edits", @"OmniUIDocument", OMNI_BUNDLE, @"Discard unsynced edits dialog: discard button label")  style:UIAlertActionStyleDestructive handler:^(UIAlertAction * __nonnull action) {
                discardAction();
            }];
            [alertController addAction:discardAlertAction];

            [self.window.rootViewController presentViewController:alertController animated:YES completion:^{}];
        }
    }];
}

- (BOOL)documentStore:(ODSStore *)store canViewFileTypeWithIdentifier:(NSString *)uti;
{
    return [self canViewFileTypeWithIdentifier:uti];
}

#pragma mark - Subclass responsibility

- (NSString *)recentDocumentShortcutIconImageName;
{
    return nil;
}

- (NSString *)newDocumentShortcutIconImageName;
{
    return @"3DTouchShortcutNewDocument";
}

- (UIImage *)documentPickerBackgroundImage;
{
    return nil;
}

- (NSURL *)documentProviderMoreInfoURL;
{
    return nil;
}

- (Class)documentExporterClass
{
    OBRequestConcreteImplementation(self, _cmd);
}

- (Class)documentClassForURL:(NSURL *)url;
{
    OBRequestConcreteImplementation(self, _cmd);
}

- (UIView *)pickerAnimationViewForTarget:(OUIDocument *)document;
{
    OBRequestConcreteImplementation(self, _cmd);
}

- (NSArray *)toolbarItemsForDocument:(OUIDocument *)document;
{
    OBRequestConcreteImplementation(self, _cmd);
}

- (void)showInspectorFromBarButtonItem:(UIBarButtonItem *)item;
{
    OBRequestConcreteImplementation(self, _cmd);
}

- (void)mainThreadFinishedLoadingDocument:(OUIDocument *)document;  // For handling any loading that can't be done in a thread
{
    // Okay to do nothing
}

#pragma mark -
#pragma mark UIApplicationDelegate

- (void)_delayedFinishLaunchingAllowCopyingSampleDocuments:(BOOL)allowCopyingSampleDocuments
                                    openingDocumentWithURL:(NSURL *)launchDocumentURL
                                       orShowingOnlineHelp:(BOOL)showHelp
                                         completionHandler:(void (^)(void))completionHandler;
{
    DEBUG_LAUNCH(1, @"Delayed finish launching allowCopyingSamples:%d openURL:%@ orShowingHelp:%@", allowCopyingSampleDocuments, launchDocumentURL, showHelp ? @"YES" : @"NO");
    
    OUIDocumentPickerViewController *documentPickerViewController = _documentPicker.selectedScopeViewController;

    BOOL startedOpeningDocument = NO;
    ODSFileItem *fileItemToSelect = nil;
    ODSFileItem *launchFileItem = nil;
    
    if (launchDocumentURL) {
        launchFileItem = [_documentStore fileItemWithURL:launchDocumentURL];
        DEBUG_LAUNCH(1, @"  launchFileItem: %@", [launchFileItem shortDescription]);
    }
    
    completionHandler = [completionHandler copy];

    NSInteger builtInResourceVersion = [self builtInResourceVersion];
    if (allowCopyingSampleDocuments && launchDocumentURL == nil && [[NSUserDefaults standardUserDefaults] integerForKey:@"SampleDocumentsHaveBeenCopiedToUserDocuments"] < builtInResourceVersion) {
        // Copy in a welcome document if one exists and we haven't done so for first launch yet.
        [self copySampleDocumentsToUserDocumentsWithCompletionHandler:^(NSDictionary *nameToURL) {
            [[NSUserDefaults standardUserDefaults] setInteger:builtInResourceVersion forKey:@"SampleDocumentsHaveBeenCopiedToUserDocuments"];
            [[NSUserDefaults standardUserDefaults] setObject:[[NSDate date] xmlString] forKey:@"SampleDocumentsHaveBeenCopiedToUserDocumentsDate"];

            [_documentStore scanItemsWithCompletionHandler:^{
                // Retry after the scan finished, but this time try opening the Welcome document
                [self _delayedFinishLaunchingAllowCopyingSampleDocuments:NO // we just did, don't try again
                                                  openingDocumentWithURL:nil // already checked this
                                                     orShowingOnlineHelp:YES
                                                       completionHandler:completionHandler];
            }];
        }];
        return;
    }

    if (launchFileItem != nil) {
        DEBUG_LAUNCH(1, @"Opening document %@", [launchFileItem shortDescription]);
        [self openDocument:launchFileItem];
        startedOpeningDocument = YES;
    } else {
        // Restore our selected or open document if we didn't get a command from on high.
        NSArray *launchAction = [self.launchAction copy];

        if (launchDocumentURL) {
            // We had a launch URL, but didn't find the file. This might be an OmniPresence config file -- don't open the document if any
            launchAction = nil;
        }
        
        DEBUG_LAUNCH(1, @"  launchAction: %@", launchAction);
        if ([launchAction isKindOfClass:[NSArray class]] && [launchAction count] == 2) {
            // Clear the launch action in case we crash while opening this file; we'll restore it if the file opens successfully.
            self.launchAction = nil;

            if (_isOpeningURL) {
                // We may have been cold launched with a requst from Spotlight or a shortcut. That path sets _isOpeningURL (which is kind of hacky) which we would have done here based on `startedOpeningDocument`.
                startedOpeningDocument = YES;
            } else {
                launchFileItem = [_documentStore fileItemWithURL:[NSURL URLWithString:[launchAction objectAtIndex:1]]];
                if (launchFileItem) {
                    [documentPickerViewController scrollItemToVisible:launchFileItem animated:NO];
                    NSString *action = [launchAction objectAtIndex:0];
                    if ([action isEqualToString:OpenAction]) {
                        DEBUG_LAUNCH(1, @"Opening file item %@", [launchFileItem shortDescription]);
                        [self _openDocument:launchFileItem fileItemToRevealFrom:launchFileItem isOpeningFromPeek:NO willPresentHandler:nil completionHandler:nil];
                        startedOpeningDocument = YES;
                    } else
                        fileItemToSelect = launchFileItem;
                }
            }
        }
        if(allowCopyingSampleDocuments && ![[NSUserDefaults standardUserDefaults] boolForKey:@"SampleDocumentsHaveBeenCopiedToUserDocuments"]) {
            // The user is opening an inbox document. Copy the sample docs and pretend like we're already opening it
            [self copySampleDocumentsToUserDocumentsWithCompletionHandler:^(NSDictionary *nameToURL) {
                [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"SampleDocumentsHaveBeenCopiedToUserDocuments"];
            }];
            if ([launchDocumentURL isFileURL] && OFISEQUAL([[launchDocumentURL path] pathExtension], @"omnipresence-config")) {
                startedOpeningDocument = NO; // If the 'launchDocumentURL' actually points to a config file, we're not going to open a document.
            }
            else {
                startedOpeningDocument = YES;
            }
        }
    }
    
    // Iff we didn't open a document, go to the document picker. We don't want to start loading of previews if the user is going directly to a document (particularly the welcome document).
    if (!startedOpeningDocument) {
        [self _fadeInDocumentPickerScrollingToFileItem:fileItemToSelect];

        if (showHelp && [self shouldOpenOnlineHelpOnFirstLaunch]) {
            dispatch_after(0, dispatch_get_main_queue(), ^{
                [self showOnlineHelp:nil];
            });
        } else if (self.newsURLStringToShowWhenReady){
            self.readyToShowNews = YES;
            [self showNewsURLString:self.newsURLStringToShowWhenReady evenIfShownAlready:NO];
        }
    } else {
        // Now that we are on screen, if we are waiting for a document to open, we'll just fade it in when it is loaded.
        _isOpeningURL = YES; // prevent preview generation while we are getting around to it
    }
    
    self.readyToShowNews = YES;
    if (completionHandler)
        completionHandler();
}

- (NSUInteger)_toolbarIndexForControl:(UIControl *)toolbarControl inToolbar:(UIToolbar *)toolbar;
{
    NSArray *toolbarItems = [toolbar items];
    for (id toolbarTarget in [toolbarControl allTargets]) {
        if ([toolbarTarget isKindOfClass:[UIBarButtonItem class]]) {
            return [toolbarItems indexOfObjectIdenticalTo:toolbarTarget];
        }
    }
    return [toolbarItems indexOfObjectPassingTest:^(id obj, NSUInteger idx, BOOL *stop) {
        UIBarButtonItem *toolbarItem = obj;
        return (BOOL)(toolbarItem.customView == toolbarControl);
    }];
}

#ifdef DEBUG_kc
#define DEBUG_TOOLBAR_AVAILABLE_WIDTH 1
#else
#define DEBUG_TOOLBAR_AVAILABLE_WIDTH 0
#endif

- (CGFloat)_availableWidthForResizingToolbarItems:(NSArray *)resizingToolbarItems inToolbar:(UIToolbar *)toolbar;
{
    NSUInteger firstIndexOfResizingItems = NSNotFound;
    NSUInteger lastIndexOfResizingItems = NSNotFound;
    NSUInteger currentIndex = 0;
    for (UIBarButtonItem *toolbarItem in [toolbar items]) {
        if ([resizingToolbarItems containsObjectIdenticalTo:toolbarItem]) {
            lastIndexOfResizingItems = currentIndex;
            if (firstIndexOfResizingItems == NSNotFound)
                firstIndexOfResizingItems = currentIndex;
        }
        currentIndex++;
    }

    CGFloat toolbarWidth = toolbar.frame.size.width;

    if (firstIndexOfResizingItems == NSNotFound)
        return toolbarWidth;

    CGFloat bogusWidth = ceil(1.2f * toolbarWidth / 500.0) * 500.0f;
    for (UIBarButtonItem *resizingItem in resizingToolbarItems) {
        OBASSERT(resizingItem.width == 0.0f); // Otherwise we should be keeping track of what the old width was so we can put it back
        resizingItem.width = bogusWidth;
    }
    [toolbar setNeedsLayout];
    [toolbar layoutIfNeeded];

    CGFloat leftWidth = 0.0f;
    CGFloat rightWidth = 0.0f;
    CGFloat floatingItemsLeftEdge = 0.0f;
    CGFloat floatingItemsRightEdge = 0.0f;
    CGFloat resizingItemsLeftEdge = 0.0f;
    CGFloat resizingItemsRightEdge = 0.0f;

    for (UIView *toolbarView in [toolbar subviews]) {
        if ([toolbarView isKindOfClass:[UIControl class]]) {
            UIControl *toolbarControl = (UIControl *)toolbarView;
            NSUInteger toolbarIndex = [self _toolbarIndexForControl:toolbarControl inToolbar:toolbar];
            if (toolbarIndex == NSNotFound) {
#if DEBUG_TOOLBAR_AVAILABLE_WIDTH
                NSLog(@"DEBUG: Cannot find toolbar item for %@", toolbarControl);
#endif
            } else if (toolbarIndex < firstIndexOfResizingItems) {
                // This item is to the left of our resizing items
                CGRect toolbarControlFrame = toolbarControl.frame;
                CGFloat rightEdgeOfLeftItem = CGRectGetMaxX(toolbarControlFrame);
                if (rightEdgeOfLeftItem <= 0.0) {
                    // This item floats to the left of the resizing content
                    CGFloat leftEdge = CGRectGetMinX(toolbarControlFrame);
                    if (leftEdge < floatingItemsLeftEdge)
                        floatingItemsLeftEdge = leftEdge;
                } else {
                    if (rightEdgeOfLeftItem > leftWidth)
                        leftWidth = rightEdgeOfLeftItem;
#if DEBUG_TOOLBAR_AVAILABLE_WIDTH
                    NSLog(@"DEBUG: toolbarIndex = %lu, rightEdgeOfLeftItem = %1.1f, leftWidth = %1.1f", toolbarIndex, rightEdgeOfLeftItem, leftWidth);
#endif
                }
            } else if (toolbarIndex > lastIndexOfResizingItems) {
                // This item is to the right of our resizing items
                CGRect toolbarControlFrame = toolbarControl.frame;
                CGFloat leftEdgeOfRightItem = CGRectGetMinX(toolbarControlFrame);
                if (leftEdgeOfRightItem >= toolbarWidth) {
                    // This item floats to the right of the resizing content
                    CGFloat rightEdge = CGRectGetMaxX(toolbarControlFrame);
                    if (rightEdge > floatingItemsRightEdge)
                        floatingItemsRightEdge = rightEdge;
                } else {
                    if (toolbarWidth - leftEdgeOfRightItem > rightWidth)
                        rightWidth = toolbarWidth - leftEdgeOfRightItem;
#if DEBUG_TOOLBAR_AVAILABLE_WIDTH
                    NSLog(@"DEBUG: toolbarIndex = %lu, rightEdgeOfLeftItem = %1.1f, rightWidth = %1.1f", toolbarIndex, leftEdgeOfRightItem, rightWidth);
#endif
                }
            } else {
                CGRect toolbarControlFrame = toolbarControl.frame;
                CGFloat leftEdge = CGRectGetMinX(toolbarControlFrame);
                CGFloat rightEdge = CGRectGetMaxX(toolbarControlFrame);
                if (leftEdge < resizingItemsLeftEdge)
                    resizingItemsLeftEdge = leftEdge;
                if (rightEdge > resizingItemsRightEdge)
                    resizingItemsRightEdge = rightEdge;
#if DEBUG_TOOLBAR_AVAILABLE_WIDTH
                NSLog(@"DEBUG: toolbarIndex = %lu, resizing control=%@", toolbarIndex, toolbarControl);
#endif
            }
        }
    }

    CGFloat floatingItemsWidth = 0.0f;

    if (floatingItemsLeftEdge < resizingItemsLeftEdge)
        floatingItemsWidth += resizingItemsLeftEdge - floatingItemsLeftEdge;

    if (floatingItemsRightEdge > resizingItemsRightEdge)
        floatingItemsWidth += floatingItemsRightEdge - resizingItemsRightEdge;

    CGFloat availableWidth = toolbarWidth - floatingItemsWidth - leftWidth - rightWidth - 8.0f - 8.0f; /* Leave a margin on both sides */

#if DEBUG_TOOLBAR_AVAILABLE_WIDTH
    NSLog(@"DEBUG: availableWidth = %1.1f (toolbarWidth = %1.1f, floatingItemsWidth = %1.1f, leftWidth = %1.1f, rightWidth = %1.1f)", availableWidth, toolbarWidth, floatingItemsWidth, leftWidth, rightWidth);
#endif

    for (UIBarButtonItem *resizingItem in resizingToolbarItems) {
        resizingItem.width = 0.0f; // Put back the old widths
    }

    return availableWidth;
}

- (BOOL)application:(UIApplication * __nonnull)application continueUserActivity:(NSUserActivity * __nonnull)userActivity restorationHandler:(void (^ __nonnull)(NSArray * _Nullable restorableObjects))restorationHandler;
{
    NSString *uniqueID = userActivity.userInfo[CSSearchableItemActivityIdentifier];
    if (uniqueID) {
        self.searchResultsURL = [[self class] fileURLForSpotlightID:uniqueID];
        [self _openDocumentWithURLAfterScan:self.searchResultsURL completion:nil];
        return YES;
    } else {
        return NO;
    }
}


- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions;
{
    // UIKit throws an exception if UIBackgroundModes contains 'fetch' but the application delegate doesn't implement -application:performFetchWithCompletionHandler:. We want to be more flexible to allow apps to use our document picker w/o having to support background fetch.
    OBASSERT_IF([[[NSBundle mainBundle] infoDictionary][@"UIBackgroundModes"] containsObject:@"fetch"],
                [self respondsToSelector:@selector(application:performFetchWithCompletionHandler:)]);
    
    NSURL *launchOptionsURL = [launchOptions objectForKey:UIApplicationLaunchOptionsURLKey];
    if (!launchOptionsURL)
        launchOptionsURL = self.searchResultsURL;
    
    // If we are getting launched into the background, try to stay alive until our document picker is ready to view (otherwise the snapshot in the app launcher will be bogus).
    OFBackgroundActivity *activity = nil;
    if ([application applicationState] == UIApplicationStateBackground)
        activity = [OFBackgroundActivity backgroundActivityWithIdentifier:@"com.omnigroup.OmniUI.OUIDocumentAppController.launching"];
    
    void (^launchAction)(void) = ^(void){
        DEBUG_LAUNCH(1, @"Did launch with options %@", launchOptions);
        
        // If our window wasn't loaded from a xib, make one.
        if (!_window) {
            _window = [self makeMainWindow];
        } else {
            // resize xib window to the current screen size
            [_window setFrame:[[UIScreen mainScreen] bounds]];
        }
        
        _documentStore = [[ODSStore alloc] initWithDelegate:self];

        _documentPicker = [[OUIDocumentPicker alloc] initWithDocumentStore:_documentStore];
        _documentPicker.delegate = self;
        
        OUILaunchViewController *launchViewController = [[OUILaunchViewController alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge color:_window.tintColor];
        _window.rootViewController = launchViewController;
        [_window makeKeyAndVisible];
        
        
        // Pump the runloop once so that the -viewDidAppear: messages get sent before we muck with the view containment again. Otherwise, we never get -viewDidAppear: on the root view controller, and thus the OUILaunchViewController, causing assertions.
        //OUIDisplayNeededViews();
        
        DEBUG_LAUNCH(1, @"Creating document store");
        
        OFXServerAccountRegistry *registry = [OFXServerAccountRegistry defaultAccountRegistry];
        if ([registry.allAccounts count] == 0) {
            [self _importLegacyAccounts];
        }

        // Start out w/o syncing so that our initial setup will just find local documents. This is crufty, but it avoids hangs in syncing when we aren't able to reach the server.
        _syncAgent = [[OFXAgent alloc] init];
        _syncAgent.syncSchedule = (application.applicationState == UIApplicationStateBackground) ? OFXSyncScheduleManual : OFXSyncScheduleNone; // Allow the manual sync from -application:performFetchWithCompletionHandler: that we might be about to do. We just want to avoid automatic syncing.
        [_syncAgent applicationLaunched];
        _syncAgentForegrounded = _syncAgent.foregrounded; // Might be launched into the background
        
        _agentActivity = [[OFXAgentActivity alloc] initWithAgent:_syncAgent];
        
        // Wait for scopes to get their document URL set up.
        [_syncAgent afterAsynchronousOperationsFinish:^{
            DEBUG_LAUNCH(1, @"Sync agent finished first pass");
            
            // See commentary by -_updateDocumentStoreScopes for why we observe the sync agent instead of the account registry
            [_syncAgent addObserver:self forKeyPath:OFValidateKeyPath(_syncAgent, runningAccounts) options:0 context:&SyncAgentRunningAccountsContext];
            [self _updateDocumentStoreScopes];
            
            _localScope = [[ODSLocalDirectoryScope alloc] initWithDirectoryURL:[ODSLocalDirectoryScope userDocumentsDirectoryURL] scopeType:ODSLocalDirectoryScopeNormal documentStore:_documentStore];
            [_documentStore addScope:_localScope];
            _externalScopeManager = [[OUIDocumentExternalScopeManager alloc] initWithDocumentStore:_documentStore];
            ODSScope *trashScope = [[ODSLocalDirectoryScope alloc] initWithDirectoryURL:[ODSLocalDirectoryScope trashDirectoryURL] scopeType:ODSLocalDirectoryScopeTrash documentStore:_documentStore];
            [_documentStore addScope:trashScope];
            
            NSURL *templateDirectoryURL = [ODSLocalDirectoryScope templateDirectoryURL];
            if (templateDirectoryURL) {
                ODSScope *templateScope = [[ODSLocalDirectoryScope alloc] initWithDirectoryURL:[ODSLocalDirectoryScope templateDirectoryURL] scopeType:ODSLocalDirectoryScopeTemplate documentStore:_documentStore];
                [_documentStore addScope:templateScope];
            }

            [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_fileItemContentsChangedNotification:) name:ODSFileItemContentsChangedNotification object:_documentStore];
            [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_fileItemFinishedDownloadingNotification:) name:ODSFileItemFinishedDownloadingNotification object:_documentStore];
            
            __weak OUIDocumentAppController *weakSelf = self;

            // We have to wait for the document store to get results from its scopes
            [_documentStore addAfterInitialDocumentScanAction:^{
                DEBUG_LAUNCH(1, @"Initial scan finished");
                
                OUIDocumentAppController *strongSelf = weakSelf;
                OBASSERT(strongSelf);
                if (!strongSelf)
                    return;
                

                [strongSelf _updateCoreSpotlightIndex];
                
                [strongSelf _delayedFinishLaunchingAllowCopyingSampleDocuments:YES
                                                        openingDocumentWithURL:launchOptionsURL
                                                           orShowingOnlineHelp:NO // Don't always try to open the welcome document; just if we copy samples
                                                             completionHandler:^{
                                                                 
                                                                 // Don't start generating previews until we have decided whether to open a document at launch time (which will prevent preview generation until it is closed).
                                                                 strongSelf->_previewGenerator = [[OUIDocumentPreviewGenerator alloc] init];
                                                                 strongSelf->_previewGenerator.delegate = strongSelf;
                                                                 strongSelf->_previewGeneratorForegrounded = YES;

                                                                 
                                                                 // Cache population should have already started, but we should wait for it before queuing up previews.
                                                                 [OUIDocumentPreview afterAsynchronousPreviewOperation:^{
                                                                     [strongSelf->_previewGenerator enqueuePreviewUpdateForFileItemsMissingPreviews:strongSelf->_documentStore.mergedFileItems];
                                                                 }];
                                                                 
                                                                 // Without this, if we are launched in the background on 7.0b4, the snapshot image saved will not have our laid-out view contents.
                                                                 [strongSelf->_window layoutIfNeeded];

                                                                 [activity finished];
                                                       }];
            }];

        
            // Go ahead and start syncing now.
            _syncAgent.syncSchedule = OFXSyncScheduleAutomatic;
        }];
        
        _didFinishLaunching = YES;
        
        // Start real preview generation any time we are missing one.
        [[NSNotificationCenter defaultCenter] addObserverForName:OUIDocumentPickerItemViewPreviewsDidLoadNotification object:nil queue:nil usingBlock:^(NSNotification *note){
            OUIDocumentPickerItemView *itemView = [note object];
            for (OUIDocumentPreview *preview in itemView.loadedPreviews) {
                // Only do the update if we have a placeholder (no preview on disk). If we have a "empty" preview (meaning there was an error), don't redo the error-provoking work.
                if (preview.type == OUIDocumentPreviewTypePlaceholder) {
                    ODSFileItem *fileItem = [_documentStore fileItemWithURL:preview.fileURL];
                    OBASSERT(fileItem);
                    if (fileItem)
                        [_previewGenerator fileItemNeedsPreviewUpdate:fileItem];
                }
            }
        }];
    };

    // Might be invoked immediately or might be postponed (if we are handling a crash report).
    [self addLaunchAction:launchAction];

    return YES;
}

- (void)_importLegacyAccountOfType:(NSString *)accountTypeIdentifier fromLocationDefault:(NSString *)locationDefault usernameDefault:(NSString *)usernameDefault alreadyImportedDefault:(NSString *)alreadyImportedDefault;
{
    BOOL isOmniSyncServer = OFISEQUAL(accountTypeIdentifier, OFXOmniSyncServerAccountTypeIdentifier);

    OFXServerAccountType *accountType = [OFXServerAccountType accountTypeWithIdentifier:accountTypeIdentifier];
    assert(accountType != nil);

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (![[defaults volatileDomainForName:NSRegistrationDomain] objectForKey:alreadyImportedDefault])
        [defaults registerDefaults:@{alreadyImportedDefault:@NO}];
    if ([defaults boolForKey:alreadyImportedDefault])
        return;

    NSString *username = [defaults stringForKey:usernameDefault];
    if ([NSString isEmptyString:username])
        return; // Our legacy accounts require a username

    NSURL *locationURL = nil;
    if (accountType.requiresServerURL) {
        assert(locationDefault != nil);
        NSString *locationString = [defaults stringForKey:locationDefault];
        if ([NSString isEmptyString:locationString])
            return; // Nothing to import
        locationURL = [NSURL URLWithString:locationString];
        if (locationURL == nil)
            return; // Ignore malformed URLs
    }

    NSURL *remoteBaseURL = OFURLWithTrailingSlash([accountType baseURLForServerURL:locationURL username:username]);
    NSString *hostPattern;
    if (isOmniSyncServer) {
        hostPattern = @"sync[0-9]*\\.omnigroup\\.com/Omni Sync$";
    } else {
        hostPattern = [NSString stringWithFormat:@"^%@/", [[remoteBaseURL host] regularExpressionForLiteralString]];
    }

    NSURLCredential *credentials = OFReadCredentialsForLegacyHostPattern(hostPattern, username);
    if (credentials == nil) {
        NSLog(@"Unable to find password for %@ legacy account using host pattern /%@/ and user '%@'", accountType.displayName, hostPattern, username);
        return;
    }
    NSString *password = [credentials password];

    __autoreleasing NSError *error;
    NSURL *documentsURL = [OFXServerAccount generateLocalDocumentsURLForNewAccount:&error];
    if (documentsURL == nil) {
        NSLog(@"Failed to generate local documents while importing %@ legacy account: %@", accountType.displayName, [error toPropertyList]);
        return;
    }

    OFXServerAccount *account = [[OFXServerAccount alloc] initWithType:accountType usageMode:OFXServerAccountUsageModeImportExport remoteBaseURL:remoteBaseURL localDocumentsURL:documentsURL error:&error];
    if (!account) {
        [error log:@"Error creating account while importing %@ legacy account:", accountType.displayName];
        return;
    }

    id <OFXServerAccountValidator> accountValidator = [account.type validatorWithAccount:account username:username password:password];
    accountValidator.finished = ^(NSError *errorOrNil) {
        if (errorOrNil != nil)
            return;

        OFXServerAccountRegistry *registry = [OFXServerAccountRegistry defaultAccountRegistry];
        __autoreleasing NSError *registrationError;
        if (![registry addAccount:account error:&registrationError]) {
            NSLog(@"Error registering account: %@", [registrationError toPropertyList]);
            return;
        }

        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:alreadyImportedDefault]; // Don't import this account again
    };

    [accountValidator startValidation];
}

- (void)_importLegacyAccounts;
{
    [self _importLegacyAccountOfType:OFXOmniSyncServerAccountTypeIdentifier fromLocationDefault:nil usernameDefault:@"OUIOmniSyncUsername" alreadyImportedDefault:@"OUIOmniSyncUsernameAlreadyImported"];
    [self _importLegacyAccountOfType:OFXWebDAVServerAccountTypeIdentifier fromLocationDefault:@"OUIWebDAVLocation" usernameDefault:@"OUIWebDAVUsername" alreadyImportedDefault:@"OUIWebDAVLocationAlreadyImported"];
}

- (BOOL)_loadOmniPresenceConfigFileFromURL:(NSURL *)url;
{
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
        OBFinishPortingLater("Should we display an alert when asked to open a config file with an unrecognized account type?");
        return NO;
    }

    OUIServerAccountSetupViewController *setup = [[OUIServerAccountSetupViewController alloc] initForCreatingAccountOfType:accountType withUsageMode:OFXServerAccountUsageModeCloudSync];
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
        
        OFXServerAccount *account = errorOrNil ? nil : vc.account;
        OBASSERT_IF(account != nil & account.usageMode == OFXServerAccountUsageModeCloudSync, [[[OFXServerAccountRegistry defaultAccountRegistry] validCloudSyncAccounts] containsObject:account]);
        OBASSERT_IF(account != nil && account.usageMode == OFXServerAccountUsageModeImportExport, [[[OFXServerAccountRegistry defaultAccountRegistry] validImportExportAccounts] containsObject:account]);
        [[OUIDocumentAppController controller] _didAddSyncAccount:account];
        [vc dismissViewControllerAnimated:YES completion:nil];
    };

    // Doing this during launch?
    if (_window.rootViewController != _documentPicker) {
        [_documentPicker showDocuments];
        _window.rootViewController = _documentPicker;
        [_window makeKeyAndVisible];
        
        [self handleCachedSpecialURLIfNeeded];
    }

    UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:setup];
    navigationController.modalPresentationStyle = UIModalPresentationFormSheet;
    navigationController.modalTransitionStyle = UIModalTransitionStyleCoverVertical;
    
    [presentFromViewController presentViewController:navigationController animated:YES completion:nil];

    return YES;
}

- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url sourceApplication:(NSString *)sourceApplication annotation:(id)annotation;
{
    // NOTE: If we are suspending launch actions (possibly due to handling a crash), _didFinishLaunching will be NO and we'd drop this on the ground. So, we add this as launch action as well. We could try to preflight the URL to see if it is certain we can't open it, but we'd have a hard time getting an accurate answer (many of the actions are async anyway).
    
    void (^launchAction)(void) = ^{
        if (!_didFinishLaunching)  // if the app is launched by an open request from another app, then this is called and then application:didFinishLaunchingWithOptions: is called
            return;            // and application:didFinishLaunchingWithOptions: handles opening the doc
        
        DEBUG_LAUNCH(1, @"Did openURL:%@ sourceApplication:%@ annotation:%@", url, sourceApplication, annotation);
        
        if ([self isSpecialURL:url]) {
            _specialURLToHandle = [url copy];
            if (self.window.rootViewController == _documentPicker) {
                [self handleCachedSpecialURLIfNeeded];
            }
            return;
        }
        
        if ([url isFileURL] && OFISEQUAL([[url path] pathExtension], @"omnipresence-config")) {
            OBASSERT(_syncAgent != nil);
            [_syncAgent afterAsynchronousOperationsFinish:^{
                [self _loadOmniPresenceConfigFileFromURL:url];
            }];
            return;
        }
        
        // Only attempt to open handle as an Inbox item if the URL is a file URL.
        if (url.isFileURL) {
            _isOpeningURL = YES;
            
            // Have to wait for the document store to awake again (if we were backgrounded), initiated by -applicationWillEnterForeground:. <bug:///79297> (Bad animation closing file opened from another app)
            
            void (^handleInbox)(void) = ^(void){
                OBASSERT(_documentStore);
                
                void (^scanAction)(void) = ^{
                    if (ODSIsInInbox(url)) {
                        OBASSERT(_localScope);
                        
                        [OUIDocumentInbox cloneInboxItem:url toScope:_localScope completionHandler:^(ODSFileItem *newFileItem, NSError *errorOrNil) {
                            __autoreleasing NSError *deleteInboxError = nil;
                            if (![OUIDocumentInbox coordinatedRemoveItemAtURL:url error:&deleteInboxError]) {
                                NSLog(@"Failed to delete the inbox item with error: %@", [deleteInboxError toPropertyList]);
                            }
                            
                            main_async(^{
                                if (!newFileItem) {
                                    // Display Error and return.
                                    OUI_PRESENT_ERROR_FROM(errorOrNil, self.window.rootViewController);
                                    return;
                                }
                                
                                OBFinishPortingLater("TODO: Reveal scope in document picker");
                                //                            _documentPicker.selectedScopeViewController.selectedScope = _localScope;
                                
                                [self openDocument:newFileItem];
                            });
                        }];
                    } else {
                        OBASSERT_NOT_REACHED("Will the system ever give us a non-inbox item?");
                        ODSFileItem *fileItem = [_documentStore fileItemWithURL:url];
                        OBASSERT(fileItem);
                        if (fileItem)
                            [self openDocument:fileItem];
                    }
                };
                [_documentStore addAfterInitialDocumentScanAction:scanAction];
            };
            
            if (_documentStore && _localScope) {
                handleInbox();
            }
            else {
                OBASSERT(_syncAgent);
                [_syncAgent afterAsynchronousOperationsFinish:handleInbox];
            }
        }
    };
    
    [self addLaunchAction:launchAction];
    
    return YES;
}

- (void)_setLaunchActionFromCurrentState;
{
    if (_document)
        self.launchAction = [NSArray arrayWithObjects:OpenAction, [_document.fileURL absoluteString], nil];
    else
        self.launchAction = nil;
}

- (void)applicationWillEnterForeground:(UIApplication *)application;
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:OUISystemIsSnapshottingNotification object:nil];
    [self destroyCurrentSnapshotTimer];
    DEBUG_LAUNCH(1, @"Will enter foreground");

    if (_syncAgent && _syncAgentForegrounded == NO) {
        _syncAgentForegrounded = YES;
        [_syncAgent applicationWillEnterForeground];
    }
    
    if (_documentStore && _previewGeneratorForegrounded == NO) {
        OBASSERT(_previewGenerator);
        _previewGeneratorForegrounded = YES;
        // Make sure we find the existing previews before we check if there are documents that need previews updated
        [self initializePreviewCache];
    }
}

- (void)initializePreviewCache;
{
    [OUIDocumentPreview populateCacheForFileItems:_documentStore.mergedFileItems completionHandler:^{
        [_previewGenerator enqueuePreviewUpdateForFileItemsMissingPreviews:_documentStore.mergedFileItems];
    }];
    
}

- (void)applicationDidEnterBackground:(UIApplication *)application;
{
    DEBUG_LAUNCH(1, @"Did enter background");
    
    [self _updateShortcutItems];

    if (_didFinishLaunching) { // Might get backgrounded while still launching (like while handling a crash alert)
        // We do NOT save the document here. UIDocument subscribes to application lifecycle notifications and will provoke a save on itself.
        [self _setLaunchActionFromCurrentState];
    }
    
    // Radar 14075101: UIApplicationDidEnterBackgroundNotification sent twice if app with background activity is killed from Springboard
    if (_syncAgent && _syncAgentForegrounded) {
        _syncAgentForegrounded = NO;
        [_syncAgent applicationDidEnterBackground];
    }
    
    if (_documentStore && _previewGeneratorForegrounded) {
        _previewGeneratorForegrounded = NO;
        
        NSSet *mergedFileItems = _documentStore.mergedFileItems;
        
        [[self class] _cleanUpDocumentStateNotUsedByFileItems:mergedFileItems];
        
        [_previewGenerator applicationDidEnterBackground];
        
        // Clean up unused previews
        [OUIDocumentPreview deletePreviewsNotUsedByFileItems:mergedFileItems];
    }
    
    
    //Register to observe the ViewDidLayoutSubviewsNotification, which we post in the -didLayoutSubviews method of the DocumentPickerViewController.
    //-didLayoutSubviews gets called during Apple's snapshots. Each time it is called while we are backgrounded, we assume they are taking another snapshot,
    //so we reset the countdown to clearing the cache (since the cache is used in generating the views they are snapshotting).
    _backgroundFlushActivity = [OFBackgroundActivity backgroundActivityWithIdentifier: @"com.omnigroup.OmniUI.OUIDocumentAppController.delayedCacheClearing"];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(willWaitForSnapshots) name:OUISystemIsSnapshottingNotification object: nil];
    
    //Need to actually kick off the timer, since the system may not take the snapshots that end up causing the notification to post, and we do want to clear the cache eventually.
    [self willWaitForSnapshots];
    
    [super applicationDidEnterBackground:application];
}

- (void)applicationWillTerminate:(UIApplication *)application;
{
    DEBUG_LAUNCH(1, @"Will terminate");

    [self _setLaunchActionFromCurrentState];

    // Radar 14075101: UIApplicationDidEnterBackgroundNotification sent twice if app with background activity is killed from Springboard (though in this case, we get 'did background' and then 'will terminate' and OFXAgent doesn't handle this since both transition it to its 'stopped' state).
    if (_syncAgent && _syncAgentForegrounded) {
        _syncAgentForegrounded = NO;
        [_syncAgent applicationWillTerminateWithCompletionHandler:nil];
    }
    
    [super applicationWillTerminate:application];
}

- (void)applicationDidReceiveMemoryWarning:(UIApplication *)application;
{
    DEBUG_LAUNCH(1, @"Memory warning");

    [super applicationDidReceiveMemoryWarning:application];
    
    [OUIDocumentPreview discardHiddenPreviews];
}

#pragma mark - UIApplicationShortcutItem Handling

- (void)_updateShortcutItems
{
    // Update quicklaunch actions
    NSArray *recentItems = [self recentlyOpenedFileItems];
    NSMutableArray <UIApplicationShortcutItem *> *shortcutItems = [[NSMutableArray <UIApplicationShortcutItem *> alloc] init];
    
    // dynamically create the "new document" option
    UIApplicationShortcutIcon *newDocShortcutIcon = [UIApplicationShortcutIcon iconWithTemplateImageName:[self newDocumentShortcutIconImageName]];
    UIApplicationShortcutItem *newDocItem = [[UIApplicationShortcutItem alloc] initWithType:ODSShortcutTypeNewDocument
                                                                             localizedTitle: NSLocalizedStringWithDefaultValue(@"New Document",  @"OmniUIDocument", OMNI_BUNDLE, @"New Document", @"New Template button title")
                                                                          localizedSubtitle:nil
                                                                                       icon:newDocShortcutIcon
                                                                                   userInfo:nil];
    [shortcutItems addObject:newDocItem];
    
    NSString *shortcutImageName = [self recentDocumentShortcutIconImageName];
    for (ODSFileItem *fileItem in recentItems) {
        NSURL *fileURL = fileItem.fileURL;
        if (!fileURL)
            continue;
        
        NSDictionary *userInfo = @{ ODSOpenRecentDocumentShortcutFileKey : fileURL.absoluteString };
        
        UIApplicationShortcutIcon *shortcutIcon = shortcutImageName ? [UIApplicationShortcutIcon iconWithTemplateImageName:shortcutImageName] : nil;
        
        UIApplicationShortcutItem *item = [[UIApplicationShortcutItem alloc] initWithType:ODSShortcutTypeOpenRecent
                                                                           localizedTitle:fileItem.name
                                                                        localizedSubtitle:nil
                                                                                     icon:shortcutIcon
                                                                                 userInfo:userInfo];
        [shortcutItems addObject:item];
    }
    
    [UIApplication sharedApplication].shortcutItems = shortcutItems;
}

- (void)_closeAllDocumentsBeforePerformingBlock:(void(^)(void))completionHandler;
{
    if (_document != nil) {
        [self closeDocumentWithCompletionHandler:completionHandler];
    } else {
        if (completionHandler != NULL) {
            completionHandler();
        }
    }
}

- (void)application:(UIApplication *)application performActionForShortcutItem:(UIApplicationShortcutItem *)shortcutItem completionHandler:(void (^)(BOOL))completionHandler;
{
    __weak OUIDocumentAppController *weakSelf = self;  // weak self is only to keep compiler happy
    if ([shortcutItem.type hasSuffix:@".shortcut-items.open-recent"]) {
        // Open Recent
        NSString *urlString = [shortcutItem.userInfo stringForKey:ODSOpenRecentDocumentShortcutFileKey];
        if (![NSString isEmptyString:urlString]) {
            NSURL *url = [NSURL URLWithString:urlString];
            if (url) {
                [weakSelf _openDocumentWithURLAfterScan:url completion:^{
                    if (completionHandler) {
                        completionHandler(YES);
                    }
                }];
            } else {
                if (completionHandler) {
                    completionHandler(NO);
                }
            }
        } else {
            if (completionHandler) {
                completionHandler(NO);
            }
        }
    }
    else if ([shortcutItem.type hasSuffix:@".shortcut-items.new-document"]) {
        [weakSelf addLaunchAction:^{
            [weakSelf.documentPicker.documentStore addAfterInitialDocumentScanAction:^{
                [weakSelf _closeAllDocumentsBeforePerformingBlock:^{
                    // New Document
                    OUIDocumentPicker *documentPicker = [weakSelf documentPicker];
                    [documentPicker navigateToScope:[[weakSelf documentPicker] localDocumentsScope] animated:NO];
                    [documentPicker.selectedScopeViewController newDocumentWithTemplateFileItem:nil documentType:ODSDocumentTypeNormal completion:^{
                        if (completionHandler) {
                            completionHandler(YES);
                        }
                    }];
                }];
            }];
        }];
    }
}

#pragma mark - ODSStoreDelegate

- (void)documentStore:(ODSStore *)store addedFileItems:(NSSet *)addedFileItems;
{
    // Register previews as files appear and start preview generation for them. _previewGenerator might still be nil if we are starting up, but we still want to register the previews.
    [OUIDocumentPreview populateCacheForFileItems:addedFileItems completionHandler:^{
        [_previewGenerator enqueuePreviewUpdateForFileItemsMissingPreviews:addedFileItems];
    }];
}

- (void)documentStore:(ODSStore *)store fileItem:(ODSFileItem *)fileItem willMoveToURL:(NSURL *)newURL;
{
    NSString *uniqueID = [[self class] spotlightIDForFileURL:fileItem.fileURL];
    if (uniqueID) {
        NSMutableDictionary *dict = [[self class] _spotlightToFileURL];
        [dict setObject:[[self class] _savedPathForFileURL:newURL] forKey:uniqueID];
        [[NSUserDefaults standardUserDefaults] setObject:dict forKey:@"SpotlightToFileURLPathMapping"];
        
        if (![[fileItem.fileURL.path lastPathComponent] isEqualToString:[newURL.path lastPathComponent]]) {
            // title has changed, regenerate spotlight info
            [_previewGenerator fileItemNeedsPreviewUpdate:fileItem];
        }
    }
}

- (void)documentStore:(ODSStore *)store fileItemEdit:(ODSFileItemEdit *)fileItemEdit willCopyToURL:(NSURL *)newURL;
{
    // Let the preview system know that if anyone comes asking for the new item, it should return the existing preview.
    [OUIDocumentPreview addAliasFromFileItemEdit:fileItemEdit toFileWithURL:newURL];
}

- (void)documentStore:(ODSStore *)store fileItemEdit:(ODSFileItemEdit *)fileItemEdit finishedCopyToURL:(NSURL *)destinationURL withFileItemEdit:(ODSFileItemEdit *)destinationFileItemEditOrNil;
{
    [OUIDocumentPreview removeAliasFromFileItemEdit:fileItemEdit toFileWithURL:destinationURL];
    
    if (destinationFileItemEditOrNil) {
        [[self class] copyDocumentStateFromFileEdit:fileItemEdit.originalFileEdit toFileEdit:destinationFileItemEditOrNil.originalFileEdit];
        [OUIDocumentPreview cachePreviewImagesForFileEdit:destinationFileItemEditOrNil.originalFileEdit byDuplicatingFromFileEdit:fileItemEdit.originalFileEdit];
    }
}

- (void)documentStore:(ODSStore *)store willRemoveFileItemAtURL:(NSURL *)destinationURL;
{
    NSString *uniqueID = [[self class] spotlightIDForFileURL:destinationURL];
    if (uniqueID) {
        [[CSSearchableIndex defaultSearchableIndex] deleteSearchableItemsWithIdentifiers:@[uniqueID] completionHandler: ^(NSError * __nullable error) {
            if (error)
                NSLog(@"Error deleting searchable item %@: %@", uniqueID, error);
        }];
        
        NSMutableDictionary *dict = [[self class] _spotlightToFileURL];
        [dict removeObjectForKey:uniqueID];
        [[NSUserDefaults standardUserDefaults] setObject:dict forKey:@"SpotlightToFileURLPathMapping"];
    }
}

static NSMutableDictionary *spotlightToFileURL;

+ (NSMutableDictionary *)_spotlightToFileURL;
{
    if (!spotlightToFileURL) {
        NSDictionary *dictionary = [[NSUserDefaults standardUserDefaults] objectForKey:@"SpotlightToFileURLPathMapping"];
        if (dictionary)
            spotlightToFileURL = [dictionary mutableCopy];
        else
            spotlightToFileURL = [[NSMutableDictionary alloc] init];
    }
    return spotlightToFileURL;
}


+ (void)registerSpotlightID:(NSString *)uniqueID forDocumentFileURL:(NSURL *)fileURL;
{
    NSMutableDictionary *dict = [self _spotlightToFileURL];
    NSString *savedPath = [self _savedPathForFileURL:fileURL];
    if (savedPath) {
        [dict setObject:savedPath forKey:uniqueID];
        [[NSUserDefaults standardUserDefaults] setObject:dict forKey:@"SpotlightToFileURLPathMapping"];
    }
}

+ (NSString *)spotlightIDForFileURL:(NSURL *)fileURL;
{
    NSString *path = [self _savedPathForFileURL:fileURL];
    NSArray *keys = [[self _spotlightToFileURL] allKeysForObject:path];
    return [keys lastObject];
}

+ (NSURL *)fileURLForSpotlightID:(NSString *)uniqueID;
{
    return [self _fileURLForSavedPath:[[self _spotlightToFileURL] objectForKey:uniqueID]];
}

+ (NSString *)_savedPathForFileURL:(NSURL *)fileURL;
{
    NSString *path = fileURL.path;
    NSString *home = NSHomeDirectory();
    if ([path hasPrefix:home]) // doing this replacement because container id (i.e. part of NSHomeDirectory()) changes on each software update
        path = [@"HOME-" stringByAppendingString:[path stringByRemovingPrefix:home]];
    return path;
}

+ (NSURL *)_fileURLForSavedPath:(NSString *)path;
{
    if (!path)
        return nil;
    
    if ([path hasPrefix:@"HOME-"])
        path = [NSHomeDirectory() stringByAppendingPathComponent:[path stringByRemovingPrefix:@"HOME-"]];
    return [NSURL fileURLWithPath:path];
}

- (void)_updateCoreSpotlightIndex;
{
    NSMutableDictionary *dict = [[self class] _spotlightToFileURL];
    
    // make mapping
    NSMutableDictionary *fileURLToSpotlight = [NSMutableDictionary dictionary];
    for (NSString *uniqueID in dict)
        [fileURLToSpotlight setObject:uniqueID forKey:[dict objectForKey:uniqueID]];

    // remove ids for files which still exist
    for (ODSFileItem *item in _documentStore.mergedFileItems) {
        [fileURLToSpotlight removeObjectForKey:[[self class] _savedPathForFileURL:item.fileURL]];
    }
    
    // whatever is left in mapping are missing indexed files
    NSMutableArray *missingIDs = [NSMutableArray array];
    for (NSString *savedPath in fileURLToSpotlight) {
        NSString *uniqueID = [fileURLToSpotlight objectForKey:savedPath];
        [missingIDs addObject:uniqueID];
        [dict removeObjectForKey:uniqueID];
    }
    if (missingIDs.count) {
        [[CSSearchableIndex defaultSearchableIndex] deleteSearchableItemsWithIdentifiers:missingIDs completionHandler: ^(NSError * __nullable error) {
            if (error)
                NSLog(@"Error deleting searchable items: %@", error);
        }];
        [[NSUserDefaults standardUserDefaults] setObject:dict forKey:@"SpotlightToFileURLPathMapping"];
    }
}

- (ODSFileItem *)documentStore:(ODSStore *)store preferredFileItemForNextAutomaticDownload:(NSSet *)fileItems;
{
    return [_documentPicker.selectedScopeViewController _preferredVisibleItemFromSet:fileItems];
}

#pragma mark - OUIDocumentPickerDelegate

- (void)documentPicker:(OUIDocumentPicker *)picker openTappedFileItem:(ODSFileItem *)fileItem;
{
    OBPRECONDITION(fileItem);
    
#if 1 && defined(DEBUG_bungi)
    BOOL crashBasedOnFilename = YES;
#else
    BOOL crashBasedOnFilename = [[NSUserDefaults standardUserDefaults] boolForKey:@"OUIDocumentPickerShouldCrashBasedOnFileName"];
#endif
    if (crashBasedOnFilename) {
        OBRecordBacktrace("crashing intentionally", OBBacktraceBuffer_Generic);
        OBRecordBacktraceWithContext("crashing intentionally w/context", OBBacktraceBuffer_Generic, (__bridge void *)self);

        NSString *crashType = [[fileItem.fileURL lastPathComponent] stringByDeletingPathExtension];
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
    
    // If we crash in trying to open this document, we should stay in the file picker the next time we launch rather than trying to open it over and over again
    self.launchAction = nil;
    
    if (![_previewGenerator shouldOpenDocumentWithFileItem:fileItem])
        return;
    
    [self openDocument:fileItem];
}

- (void)documentPicker:(OUIDocumentPicker *)picker openCreatedFileItem:(ODSFileItem *)fileItem fileItemToRevealFrom:(ODSFileItem *)fileItemToRevealFrom;
{
    OBPRECONDITION(fileItem);

    // If we crash in trying to open this document, we should stay in the file picker the next time we launch rather than trying to open it over and over again
    self.launchAction = nil;

    // We could also remember the animation type if we want to defer this until after this preview is done generating.
#if 0
    if (![_previewGenerator shouldOpenDocumentWithFileItem:fileItem])
        return;
#endif

    [self _openDocument:fileItem fileItemToRevealFrom:fileItemToRevealFrom isOpeningFromPeek:NO willPresentHandler:nil completionHandler:nil];
}

- (void)documentPicker:(OUIDocumentPicker *)picker openCreatedFileItem:(ODSFileItem *)fileItem;
{
    [self documentPicker:picker openCreatedFileItem:fileItem fileItemToRevealFrom:fileItem];
}

#pragma mark - OUIDocumentPreviewGeneratorDelegate delegate

- (BOOL)previewGenerator:(OUIDocumentPreviewGenerator *)previewGenerator isFileItemCurrentlyOpen:(ODSFileItem *)fileItem;
{
    OBPRECONDITION(fileItem);
    return OFISEQUAL(_document.fileURL, fileItem.fileURL);
}

- (BOOL)previewGeneratorHasOpenDocument:(OUIDocumentPreviewGenerator *)previewGenerator;
{
    OBPRECONDITION(_didFinishLaunching); // Don't start generating previews before the app decides whether to open a launch document
    return _isOpeningURL || _document != nil;
}

- (void)previewGenerator:(OUIDocumentPreviewGenerator *)previewGenerator performDelayedOpenOfFileItem:(ODSFileItem *)fileItem;
{
    [self documentPicker:nil openTappedFileItem:fileItem];
}

- (ODSFileItem *)previewGenerator:(OUIDocumentPreviewGenerator *)previewGenerator preferredFileItemForNextPreviewUpdate:(NSSet *)fileItems;
{
    return [_documentPicker preferredVisibleItemForNextPreviewUpdate:fileItems];
}

- (BOOL)previewGenerator:(OUIDocumentPreviewGenerator *)previewGenerator shouldGeneratePreviewForURL:(NSURL *)fileURL;
{
    return YES;
}

- (Class)previewGenerator:(OUIDocumentPreviewGenerator *)previewGenerator documentClassForFileURL:(NSURL *)fileURL;
{
    return [self documentClassForURL:fileURL];
}

#pragma mark - UIDocumentPickerDelegate

- (void)_presentExternalDocumentPicker:(UIDocumentPickerViewController *)externalDocumentPicker completionBlock:(void (^)(NSURL *))externalPickerCompletionBlock;
{
    _externalPickerCompletionBlock = [externalPickerCompletionBlock copy];
    externalDocumentPicker.delegate = self;
    [self.window.rootViewController presentViewController:externalDocumentPicker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentAtURL:(NSURL *)url;
{
    _externalPickerCompletionBlock(url);
    [self.window.rootViewController dismissViewControllerAnimated:NO completion:nil];
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller;
{
    _externalPickerCompletionBlock(nil);
    [self.window.rootViewController dismissViewControllerAnimated:NO completion:nil];
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

#pragma mark - NSObject (NSKeyValueObserving)

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context;
{
    if (context == &SyncAgentRunningAccountsContext) {
        if (object == _syncAgent && [keyPath isEqual:OFValidateKeyPath(_syncAgent, runningAccounts)]) {
            [self _updateDocumentStoreScopes];
        } else
            OBASSERT_NOT_REACHED("Unknown KVO keyPath");
        return;
    }
    
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

#pragma mark - Document state

static NSString * const OUIDocumentViewStates = @"OUIDocumentViewStates";

+ (NSDictionary *)documentStateForFileEdit:(OFFileEdit *)fileEdit;
{
    OBPRECONDITION(fileEdit);

    NSString *identifier = fileEdit.uniqueEditIdentifier;
    NSDictionary *documentViewStates = [[NSUserDefaults standardUserDefaults] dictionaryForKey:OUIDocumentViewStates];
    return [documentViewStates objectForKey:identifier];
}

+ (void)setDocumentState:(NSDictionary *)documentState forFileEdit:(OFFileEdit *)fileEdit;
{
    OBPRECONDITION(fileEdit);
    if (!fileEdit) {
        return;
    }

    // This gets called twice on save; once to remove the old edit's view state pointer and once to store the new view state under the new edit.
    // We could leave the old edit's document state in place, but it is easy for us to clean it up here rather than waiting for the app to be backgrounded.
    NSString *identifier = fileEdit.uniqueEditIdentifier;
    NSMutableDictionary *allDocsViewState = [NSMutableDictionary dictionaryWithDictionary:[[NSUserDefaults standardUserDefaults] dictionaryForKey:OUIDocumentViewStates]];
    if (documentState)
        [allDocsViewState setObject:documentState forKey:identifier];
    else
        [allDocsViewState removeObjectForKey:identifier];
    [[NSUserDefaults standardUserDefaults] setObject:allDocsViewState forKey:OUIDocumentViewStates];
}

+ (void)copyDocumentStateFromFileEdit:(OFFileEdit *)fromFileEdit toFileEdit:(OFFileEdit *)toFileEdit;
{
    [self setDocumentState:[self documentStateForFileEdit:fromFileEdit] forFileEdit:toFileEdit];
}

+ (void)_cleanUpDocumentStateNotUsedByFileItems:(NSSet *)fileItems;
{
    // Clean up any document's view state that no longer applies
    
    NSDictionary *oldViewStates = [[NSUserDefaults standardUserDefaults] dictionaryForKey:OUIDocumentViewStates];
    NSMutableDictionary *newViewStates = [NSMutableDictionary dictionary];
    
    for (ODSFileItem *fileItem in fileItems) {
        NSString *identifier = fileItem.fileEdit.uniqueEditIdentifier;
        if (!identifier)
            continue;
        NSDictionary *viewState = oldViewStates[identifier];
        if (viewState)
            newViewStates[identifier] = viewState;
    }
    
    [[NSUserDefaults standardUserDefaults] setObject:newViewStates forKey:OUIDocumentViewStates];
}

#pragma mark - Private

static NSString * const OUINextLaunchActionDefaultsKey = @"OUINextLaunchAction";

- (NSArray *)launchAction;
{
    NSArray *action = [[NSUserDefaults standardUserDefaults] objectForKey:OUINextLaunchActionDefaultsKey];
    DEBUG_LAUNCH(1, @"Launch action is %@", action);
    return action;
}

- (void)setLaunchAction:(NSArray *)launchAction;
{
    DEBUG_LAUNCH(1, @"Setting launch action %@", launchAction);
    [[NSUserDefaults standardUserDefaults] setObject:launchAction forKey:OUINextLaunchActionDefaultsKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)_updateDocumentStoreScopes;
{
    OBPRECONDITION(_syncAgent);
    OBPRECONDITION(_documentStore);

    NSMutableDictionary *previousAccountUUIDToScope = [NSMutableDictionary new];
    for (ODSScope *candidate in _documentStore.scopes) {
        if (![candidate isKindOfClass:[OFXDocumentStoreScope class]])
            continue; // Skip the local scope
        
        OFXDocumentStoreScope *scope = (OFXDocumentStoreScope *)candidate;
        previousAccountUUIDToScope[scope.account.uuid] = scope;
    }
    
    // We need to wait for the sync agent to acknowledge a new account before poking it. So, we observe the sync agent's runningAccounts property (and it observes the account registry, in turn).
    for (OFXServerAccount *account in _syncAgent.runningAccounts) {
        NSString *uuid = account.uuid;
        OFXDocumentStoreScope *scope = previousAccountUUIDToScope[uuid];
        if (scope) {
            [previousAccountUUIDToScope removeObjectForKey:uuid];
            continue;
        }
        
        scope = [[OFXDocumentStoreScope alloc] initWithSyncAgent:_syncAgent account:account documentStore:_documentStore];
        [_documentStore addScope:scope];
    }
    
    if ([previousAccountUUIDToScope count] > 0) {
        // Remove scopes for old accounts. If one of them was the selected scope, select something else.
        [previousAccountUUIDToScope enumerateKeysAndObjectsUsingBlock:^(NSString *uuid, OFXDocumentStoreScope *scope, BOOL *stop) {
            [_documentStore removeScope:scope];
        }];
    }
    
    [self _updateBackgroundFetchInterval];
}

- (void)_updateBackgroundFetchInterval;
{
    NSTimeInterval backgroundFetchInterval;
    if ([_syncAgent.runningAccounts count] > 0) {
        DEBUG_FETCH(1, @"Setting minimum fetch interval to \"minimum\".");
        backgroundFetchInterval = UIApplicationBackgroundFetchIntervalMinimum;
    } else {
        DEBUG_FETCH(1, @"Setting minimum fetch interval to \"never\".");
        backgroundFetchInterval = UIApplicationBackgroundFetchIntervalNever;
    }

    [[UIApplication sharedApplication] setMinimumBackgroundFetchInterval:backgroundFetchInterval];
}

- (void)_fadeInDocumentPickerScrollingToFileItem:(ODSFileItem *)fileItem;
{
    DEBUG_LAUNCH(1, @"Showing picker, showing item %@", [fileItem shortDescription]);
    
    [_documentPicker showDocuments];
    _window.rootViewController = _documentPicker;
    [_window makeKeyAndVisible];
    
    [self handleCachedSpecialURLIfNeeded];
    
    [OUIDocumentPreview populateCacheForFileItems:_documentStore.mergedFileItems completionHandler:^{
    }];
}

- (void)_setDocument:(OUIDocument *)document;
{
    if (_document == document)
        return;
    
    if (_document) {
        [[NSNotificationCenter defaultCenter] removeObserver:self name:UIDocumentStateChangedNotification object:_document];
        [_document didClose];
    }
    
    _document = document;
    
    if (_document) {        
        [self _noteRecentlyOpenedDocumentURL:document.fileURL];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_documentStateChanged:) name:UIDocumentStateChangedNotification object:_document];
    }
}

- (void)_didAddSyncAccount:(OFXServerAccount *)account;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    if (account != nil && account.usageMode == OFXServerAccountUsageModeCloudSync) {
        // Wait for the agent to start up. Ugly, but less so than adding an ivar and having -_updateDocumentStoreScopes clear/unlock interaction...
        // This might be marginally less terrible if we had a 'block interaction until foo' object we could create and run.
        
        OUIInteractionLock *lock = [OUIInteractionLock applicationLock];
        [self _selectScopeWithAccount:account completionHandler:^{
            [lock unlock];
        }];
    }
}

- (void)_selectScopeWithAccount:(OFXServerAccount *)account completionHandler:(void (^)(void))completionHandler;
{
    OBPRECONDITION([NSThread isMainThread]);

    completionHandler = [completionHandler copy];
    
    for (ODSScope *candidate in _documentStore.scopes) {
        if (![candidate isKindOfClass:[OFXDocumentStoreScope class]])
            continue; // Skip the local scope
        
        OFXDocumentStoreScope *scope = (OFXDocumentStoreScope *)candidate;
        if (scope.account == account) {
            OBFinishPortingLater("TODO: Reveal scope in document picker");
//            _documentPicker.selectedScopeViewController.selectedScope = scope;
            if (completionHandler)
                completionHandler();
            return;
        }
    }
    
    // Our update of document store scopes happens in response to a block invoked on the main queue and our initial call to -_didAddSyncAccount: is on a block too. So, put ourselves at the end of the main queue.
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        [self _selectScopeWithAccount:account completionHandler:completionHandler];
    }];
}

- (void)_documentStateChanged:(NSNotification *)note;
{
    OBPRECONDITION([note object] == _document);

    UIDocumentState state = _document.documentState;
    OB_UNUSED_VALUE(state);
    
    DEBUG_DOCUMENT(@"State changed to %ld", state);
}

static void _updatePreviewForFileItem(OUIDocumentAppController *self, NSNotification *note)
{
    OBPRECONDITION([note object] == self->_documentStore);

    ODSFileItem *fileItem = [[note userInfo] objectForKey:ODSFileItemInfoKey];
    OBASSERT([fileItem isKindOfClass:[ODSFileItem class]]);

    [self->_previewGenerator fileItemNeedsPreviewUpdate:fileItem];
}

- (void)_fileItemContentsChangedNotification:(NSNotification *)note;
{
    _updatePreviewForFileItem(self, note);
}

- (void)_fileItemFinishedDownloadingNotification:(NSNotification *)note;
{
    _updatePreviewForFileItem(self, note);
}

- (void)_showInspector:(id)sender;
{
    [self showInspectorFromBarButtonItem:_infoBarButtonItem];
}

- (void)_openDocumentWithURLAfterScan:(NSURL *)fileURL completion:(void(^)(void))completion;
{
    // We should be called early on, before any previously open document has been opened.
    OBPRECONDITION(_isOpeningURL == NO);
    OBPRECONDITION(_document == nil);

    // Note that we are in the middle of handling a request to open a URL. This will disable opening of any previously open document in the rest of the launch sequence.
    _isOpeningURL = YES;

    void (^afterScanAction)(void) = ^(void){
        ODSFileItem *launchFileItem = [_documentStore fileItemWithURL:fileURL];
        if (launchFileItem != nil && (!_document || _document.fileItem != launchFileItem)) {
            if (_document) {
                [self closeDocumentWithCompletionHandler:^{
                    [self _setDocument:nil];    // in -closeDocumentWithCompletionHandler:, this block will get called before _setDocument:nil gets called. That messes with -openDocument: so setting the document to nil first
                    [self openDocument:launchFileItem];
                    if (completion) {
                        completion();
                    }
                }];
            } else {
                [self openDocument:launchFileItem];
                if (completion) {
                    completion();
                }
            }
        } else {
            if (completion) {
                completion();
            }
        }
    };
    void (^launchAction)(void) = ^(void){
        [_documentStore addAfterInitialDocumentScanAction:afterScanAction];
    };
    [self addLaunchAction:launchAction];
}

#pragma mark -Snapshots

- (void)didFinishWaitingForSnapshots;
{
    [OUIDocumentPreview flushPreviewImageCache];
    [_backgroundFlushActivity finished];
}

@end
