// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUIDocument/OUIDocumentAppController.h>

#import <MobileCoreServices/MobileCoreServices.h>
#import <OmniAppKit/OAFontDescriptor.h>
#import <OmniBase/OmniBase.h>
#import <OmniDAV/ODAVErrors.h>
#import <OmniDAV/ODAVFileInfo.h>
#import <OmniDocumentStore/ODSErrors.h>
#import <OmniDocumentStore/ODSFileItem.h>
#import <OmniDocumentStore/ODSLocalDirectoryScope.h>
#import <OmniDocumentStore/ODSStore.h>
#import <OmniDocumentStore/ODSUtilities.h>
#import <OmniFileExchange/OmniFileExchange.h>
#import <OmniFoundation/NSDictionary-OFExtensions.h>
#import <OmniFoundation/NSFileManager-OFSimpleExtensions.h>
#import <OmniFoundation/NSObject-OFExtensions.h>
#import <OmniFoundation/NSSet-OFExtensions.h>
#import <OmniFoundation/NSString-OFExtensions.h>
#import <OmniFoundation/NSURL-OFExtensions.h>
#import <OmniFoundation/OFBackgroundActivity.h>
#import <OmniFoundation/OFBindingPoint.h>
#import <OmniFoundation/OFCredentials.h>
#import <OmniFoundation/OFPreference.h>
#import <OmniFoundation/OFUTI.h>
#import <OmniUI/OUIActivityIndicator.h>
#import <OmniUI/OUIAlert.h>
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
#import <OmniUIDocument/OUIDocumentViewController.h>
#import <OmniUIDocument/OUIToolbarTitleButton.h>
//#import <CrashReporter/CrashReporter.h>

#import "OUICloudSetupViewController.h"
#import "OUIDocument-Internal.h"
#import "OUIDocumentAppController-Internal.h"
#import "OUIDocumentInbox.h"
#import "OUIDocumentParameters.h"
#import "OUIDocumentPickerViewController-Internal.h"
#import "OUIDocumentPickerItemView-Internal.h"
#import "OUIRestoreSampleDocumentListController.h"
#import "OUISyncMenuController.h"
#import "OUIServerAccountSetupViewController.h"
#import "OUIDocumentOpenAnimator.h"
#import "OUIImportWebDAVNavigationController.h"
#import "OUILaunchViewController.h"

RCS_ID("$Id$");

// OUIDocumentConflictResolutionViewControllerDelegate is gone
OBDEPRECATED_METHOD(-conflictResolutionPromptForFileItem:);
OBDEPRECATED_METHOD(-conflictResolutionCancelled:);
OBDEPRECATED_METHOD(-conflictResolutionFinished:);

static NSString * const OpenAction = @"open";

static NSInteger OUIApplicationLaunchDebug = NSIntegerMax;
#define DEBUG_LAUNCH(level, format, ...) do { \
    if (OUIApplicationLaunchDebug >= (level)) \
        NSLog(@"APP: " format, ## __VA_ARGS__); \
    } while (0)

static NSInteger OUIBackgroundFetchDebug = NSIntegerMax;
#define DEBUG_FETCH(level, format, ...) do { \
    if (OUIBackgroundFetchDebug >= (level)) \
        NSLog(@"FETCH: " format, ## __VA_ARGS__); \
    } while (0)

static NSTimeInterval OUIBackgroundFetchTimeout = 15;

@interface OUIDocumentAppController (/*Private*/) <OUIDocumentPreviewGeneratorDelegate, OUIDocumentPickerDelegate, OUIWebViewControllerDelegate>

@property(nonatomic,copy) NSArray *launchAction;

@property (nonatomic, strong) NSArray *leftItems;
@property (nonatomic, strong) NSArray *rightItems;

@property (nonatomic, weak) OUIWebViewController *webViewController;

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
    OUIDocumentPreviewGenerator *_previewGenerator;
    BOOL _previewGeneratorForegrounded;
    
    UIView *_snapshotForDocumentRebuilding;
}

+ (void)initialize;
{
    OBINITIALIZE;

    OFInitializeDebugLogLevel(OUIBackgroundFetchDebug);
    OFInitializeDebugLogLevel(OUIApplicationLaunchDebug);
    OFInitializeTimeInterval(OUIBackgroundFetchTimeout, 15, 5, 600);
    
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
    
    OBASSERT(_undoBarButtonItem.hasUndoManagers == NO);
    _undoBarButtonItem.undoBarButtonItemTarget = nil;
}

// UIApplicationDelegate has an @optional window property. Our superclass conforms to this protocol, so clang assumes we already have the property, it seems (even though we redeclare it).
@synthesize window = _window;

// Called at app startup if the main xib didn't have a window outlet hooked up.
- (UIWindow *)makeMainWindow;
{
    return [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
}

@synthesize closeDocumentBarButtonItem = _closeDocumentBarButtonItem;
- (UIBarButtonItem *)closeDocumentBarButtonItem;
{
    if (!_closeDocumentBarButtonItem) {
        NSString *closeDocumentTitle = NSLocalizedStringWithDefaultValue(@"Documents <back button>", @"OmniUIDocument", OMNI_BUNDLE, @"Documents", @"Toolbar button title for returning to list of documents.");
        _closeDocumentBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:closeDocumentTitle
                                                                        style:UIBarButtonItemStylePlain target:self action:@selector(closeDocument:)];
    }
    return _closeDocumentBarButtonItem;
}

// OmniGraffle overrides -undoBarButtonItem to return an item from its xib
@synthesize undoBarButtonItem = _undoBarButtonItem;
- (OUIUndoBarButtonItem *)undoBarButtonItem;
{
    if (!_undoBarButtonItem) {
        _undoBarButtonItem = [[OUIUndoBarButtonItem alloc] init];
        _undoBarButtonItem.undoBarButtonItemTarget = self;
    }
    return _undoBarButtonItem;
}

@synthesize infoBarButtonItem = _infoBarButtonItem;
- (UIBarButtonItem *)infoBarButtonItem;
{
    if (!_infoBarButtonItem) {
        _infoBarButtonItem = [OUIInspector inspectorBarButtonItemWithTarget:self action:@selector(_showInspector:)];
        _infoBarButtonItem.accessibilityLabel = NSLocalizedStringFromTableInBundle(@"Info", @"OmniUIDocument", OMNI_BUNDLE, @"Info item accessibility label");
    }
    return _infoBarButtonItem;
}

- (IBAction)makeNewDocument:(id)sender;
{
    [_documentPicker.selectedScopeViewController newDocument:sender];
}

- (void)closeDocument:(id)sender;
{
    [self closeDocumentWithCompletionHandler:^{
        [_documentPicker.navigationController dismissViewControllerAnimated:YES completion:nil];
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
    
    // Stop tracking the state from this document's undo manager
    [[self undoBarButtonItem] removeUndoManager:_document.undoManager];
    
    // The inspector would animate closed and raise an exception, having detected it was getting deallocated while still visible (but animating away).
    // This must happen before ending editing below; otherwise the -endEditing: call will look at the popover for the editor and won't go up to any editor in the main view.
    [self dismissPopoverAnimated:NO];
    
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
    [_documentPicker navigateToContainerForItem:_document.fileItem animated:NO];
    
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
    
    [UIView transitionFromView:_snapshotForDocumentRebuilding toView:nil duration:kOUIDocumentPickerRevertAnimationDuration options:UIViewAnimationOptionTransitionCrossDissolve completion:^(BOOL finished) {
        if (finished) {
            self.window.userInteractionEnabled = YES;
            _snapshotForDocumentRebuilding = nil;
        }
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

- (void)openDocument:(ODSFileItem *)fileItem fileItemToRevealFrom:(ODSFileItem *)fileItemToRevealFrom showActivityIndicator:(BOOL)showActivityIndicator;
{
    OBPRECONDITION([NSThread isMainThread]);
    OBPRECONDITION(fileItem);
    OBPRECONDITION(fileItem.isDownloaded);

    void (^onFail)(void) = ^{
        [self _fadeInDocumentPickerScrollingToFileItem:fileItem];
        _isOpeningURL = NO;
    };
    onFail = [onFail copy];

    NSString *symlinkDestination = [[NSFileManager defaultManager] destinationOfSymbolicLinkAtPath:[fileItem.fileURL path] error:NULL];
    if (symlinkDestination != nil) {
        NSString *originalPath = [fileItem.fileURL path];
        NSString *targetPath = [originalPath stringByResolvingSymlinksInPath];
        if (targetPath == nil || OFISEQUAL(targetPath, originalPath)) {
            onFail();
            return;
        }

        // Look for the target in the fileItem's scope
        NSURL *targetURL = [NSURL fileURLWithPath:targetPath];
        ODSScope *originalScope = fileItem.scope;
        if (![originalScope isFileInContainer:targetURL]) {
            onFail();
            return;
        }

        ODSFileItem *targetItem = [originalScope fileItemWithURL:targetURL];
        [self openDocument:targetItem showActivityIndicator:showActivityIndicator];
        return;
    }

    OUIActivityIndicator *activityIndicator = nil;
    if (showActivityIndicator) {
        OUIDocumentPickerFileItemView *fileItemView = [_documentPicker.selectedScopeViewController.mainScrollView fileItemViewForFileItem:fileItemToRevealFrom];
        if (fileItemView)
            activityIndicator = [OUIActivityIndicator showActivityIndicatorInView:fileItemView withColor:self.window.tintColor];
        else if (self.window.rootViewController == _documentPicker.navigationController)
            activityIndicator = [OUIActivityIndicator showActivityIndicatorInView:_documentPicker.navigationController.topViewController.view withColor:self.window.tintColor];
    }

    void (^doOpen)(void) = ^{
        Class cls = [self documentClassForURL:fileItem.fileURL];
        OBASSERT(OBClassIsSubclassOfClass(cls, [OUIDocument class]));

        __autoreleasing NSError *error = nil;
        OUIDocument *document = [[cls alloc] initWithExistingFileItem:fileItem error:&error];
        if (!document) {
            OUI_PRESENT_ERROR(error);
            onFail();
            return;
        }

        OUIInteractionLock *lock = [OUIInteractionLock applicationLock];

        // Dismiss any popovers that may be presented.
        [self dismissPopoverAnimated:YES];

        [document openWithCompletionHandler:^(BOOL success){
            if (!success) {
                OUIDocumentHandleDocumentOpenFailure(document, nil);

                [activityIndicator hide];
                [lock unlock];

                onFail();
                return;
            }

            [self _mainThread_finishedLoadingDocument:document fileItemToRevealFrom:fileItemToRevealFrom activityIndicator:activityIndicator completionHandler:^{
                [activityIndicator hide];
                [lock unlock];

                // Ensure that when the document is closed we'll be using a filter that shows it.
                [_documentPicker.selectedScopeViewController ensureSelectedFilterMatchesFileItem:fileItem];
            }];
        }];
    };

    if (_document) {
        // If we have a document open, wait for it to close before starting to open the new one. This can happen if the user backgrounds the app and then taps on a document in Mail.
        doOpen = [doOpen copy];

        OUIInteractionLock *lock = [OUIInteractionLock applicationLock];

        [_document closeWithCompletionHandler:^(BOOL success) {
            [self _setDocument:nil];
            [self.documentPicker.navigationController dismissViewControllerAnimated:NO completion:^{
                doOpen();
                [lock unlock];
            }];
        }];
    } else {
        // Just open immediately
        doOpen();
    }
}

- (void)openDocument:(ODSFileItem *)fileItem showActivityIndicator:(BOOL)showActivityIndicator;
{
    [self openDocument:fileItem fileItemToRevealFrom:fileItem showActivityIndicator:showActivityIndicator];
}

#pragma mark -
#pragma mark Sample documents

- (NSString *)sampleDocumentsDirectoryTitle;
{
    return NSLocalizedStringFromTableInBundle(@"Restore Sample Documents", @"OmniUIDocument", OMNI_BUNDLE, @"Restore Sample Documents Title");
}

- (NSURL *)sampleDocumentsDirectoryURL;
{
    NSString *samples = [[NSBundle mainBundle] pathForResource:@"Samples" ofType:@""];
    OBASSERT(samples);
    return [NSURL fileURLWithPath:samples isDirectory:YES];
}

- (NSPredicate *)sampleDocumentsFilterPredicate;
{
    // For subclasses to overide.
    return nil;
}

- (void)copySampleDocumentsToUserDocumentsWithCompletionHandler:(void (^)(NSDictionary *nameToURL))completionHandler;
{
    OBPRECONDITION(_localScope);
    
#if 1 && defined(DEBUG_bungi)
    if (completionHandler)
        completionHandler(nil);
    return;
#endif
    
    [self copySampleDocumentsFromDirectoryURL:[self sampleDocumentsDirectoryURL] toScope:_localScope stringTableName:[self stringTableNameForSampleDocuments] completionHandler:completionHandler];
}

- (void)copySampleDocumentsFromDirectoryURL:(NSURL *)sampleDocumentsDirectoryURL toScope:(ODSScope *)scope stringTableName:(NSString *)stringTableName completionHandler:(void (^)(NSDictionary *nameToURL))completionHandler;
{
    // This should be called as part of an after-scan action so we can properly unique names.
    OBPRECONDITION(scope);
    OBPRECONDITION(scope);
    OBPRECONDITION(scope.hasFinishedInitialScan);
    
    completionHandler = [completionHandler copy];
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    __autoreleasing NSError *error = nil;
    NSArray *sampleURLs = [fileManager contentsOfDirectoryAtURL:sampleDocumentsDirectoryURL includingPropertiesForKeys:nil options:0 error:&error];
    if (!sampleURLs) {
        NSLog(@"Unable to find sample documents at %@: %@", sampleDocumentsDirectoryURL, [error toPropertyList]);
        if (completionHandler)
            completionHandler(nil);
        return;
    }
    
    NSOperationQueue *callingQueue = [NSOperationQueue currentQueue];
    NSMutableDictionary *nameToURL = [NSMutableDictionary dictionary];
    
    for (NSURL *sampleURL in sampleURLs) {
        NSString *sampleName = [[sampleURL lastPathComponent] stringByDeletingPathExtension];
        
        NSString *localizedTitle = [[NSBundle mainBundle] localizedStringForKey:sampleName value:sampleName table:stringTableName];
        if ([NSString isEmptyString:localizedTitle]) {
            OBASSERT_NOT_REACHED("No localization available for sample document name");
            localizedTitle = sampleName;
        }

        [scope addDocumentInFolder:scope.rootFolder baseName:localizedTitle fromURL:sampleURL option:ODSStoreAddByRenaming completionHandler:^(ODSFileItem *duplicateFileItem, NSError *error){
            if (!duplicateFileItem) {
                NSLog(@"Failed to copy sample document %@: %@", sampleURL, [error toPropertyList]);
                return;
            }
            [callingQueue addOperationWithBlock:^{
                OBASSERT([nameToURL objectForKey:sampleName] == nil);
                [nameToURL setObject:duplicateFileItem.fileURL forKey:sampleName];
            }];
        }];
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
    CFStringRef extension = UTTypeCopyPreferredTagWithClass((__bridge CFStringRef)fileType, kUTTagClassFilenameExtension);
    if (!extension)
        OBRequestConcreteImplementation(self, _cmd); // UTI not registered in the Info.plist?
    
    NSString *fileName = [name stringByAppendingPathExtension:(__bridge NSString *)extension];
    CFRelease(extension);
    
    return [[self sampleDocumentsDirectoryURL] URLByAppendingPathComponent:fileName];
}

#pragma mark - Background fetch

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
    [self afterDelay:OUIBackgroundFetchTimeout performBlock:^{
        if (handler) {
            DEBUG_FETCH(1, @"Timed out");
            handler(UIBackgroundFetchResultNoData);
            handler = nil;
        }
     }];
    
    [_syncAgent sync:^{
        // This is ugly for our purposes here, but the -sync: completion handler can return before any transfers have started. Making the completion handler be after all this work is even uglier. In particular, automatic download of small docuemnts is controlled by OFXDocumentStoreScope. Wait for a bit longer for stuff to filter through the systems.
        // Note also, that OFXAgentActivity will keep us alive while transfers are happening.
        
        if (!handler)
            return; // Status already reported
        
        DEBUG_FETCH(1, @"Sync request completed -- waiting for a bit to determine status");
        [self afterDelay:5.0 performBlock:^{
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
        }];
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

- (NSArray *)additionalAppMenuOptionsAtPosition:(OUIAppMenuOptionPosition)position;
{
    NSMutableArray *options = [NSMutableArray arrayWithArray:[super additionalAppMenuOptionsAtPosition:position]];
    
    // Add ways to get more documents only if we are in a valid scope, for now.
    OUIDocumentPickerViewController *scopeViewController = _documentPicker.selectedScopeViewController;
    if (scopeViewController && scopeViewController.canAddDocuments) {
        switch (position) {
            case OUIAppMenuOptionPositionAfterReleaseNotes:
            {
                UIImage *image = [[UIImage imageNamed:@"OUIMenuItemRestoreSampleDocuments.png"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
                [options addObject:[OUIMenuOption optionWithFirstResponderSelector:@selector(restoreSampleDocuments:) title:[[OUIDocumentAppController controller] sampleDocumentsDirectoryTitle] image:image]];
                break;
            }
            case OUIAppMenuOptionPositionAtEnd:
            {
                
                // Import Options
                if ([[OFXServerAccountRegistry defaultAccountRegistry].validImportExportAccounts count] > 0) {
                    __weak OUIDocumentAppController *weakSelf = self;
                    UIImage *image = [[UIImage imageNamed:@"OUIMenuItemImport.png"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
                    OUIMenuOption *importOption = [OUIMenuOption optionWithTitle:NSLocalizedStringFromTableInBundle(@"Import", @"OmniUIDocument", OMNI_BUNDLE, @"gear menu item") image:image action:^{
                        OUIImportWebDAVNavigationController *importNavigationController = [[OUIImportWebDAVNavigationController alloc] init];
                        [weakSelf.window.rootViewController presentViewController:importNavigationController animated:YES completion:nil];
                    }];
                    [options addObject:importOption];
                }
            }
                break;
            default:
                OBASSERT_NOT_REACHED("Unknown possition");
                break;
        }
    }
    
    if (position == OUIAppMenuOptionPositionAtEnd) {
        // Cloud Setup
        __weak OUIDocumentAppController *weakSelf = self;
        OUIMenuOption *cloudSetupOption = [OUIMenuOption optionWithTitle:NSLocalizedStringFromTableInBundle(@"Cloud Setup", @"OmniUIDocument", OMNI_BUNDLE, @"App menu item title") image:[[UIImage imageNamed:@"OUIMenuItemCloudSetUp"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] action:^{
            
            // Don't allow cloud setup in retail demo builds.
            if ([self isRunningRetailDemo]) {
                [self showFeatureDisabledForRetailDemoAlert];
            }
            else {
                if (![weakSelf.documentPicker.delegate respondsToSelector:@selector(documentPickerPresentCloudSetup:)] || ![weakSelf.documentPicker.delegate documentPickerPresentCloudSetup:weakSelf.documentPicker]) {
                    [weakSelf.window.rootViewController presentViewController:[[OUICloudSetupViewController alloc] init] animated:YES completion:NULL];
                }
            }
        }];
        [options addObject:cloudSetupOption];
    }

    
    return options;
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
        return _document == nil; // Don't do this while a document is open...
    
    if (action == @selector(closeDocument:))
        return _document != nil;
    
    return [super canPerformAction:action withSender:sender];
}

#pragma mark - API

- (NSArray *)editableFileTypes;
{
    if (!_editableFileTypes) {
        NSMutableArray *types = [NSMutableArray array];
        
        NSArray *documentTypes = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleDocumentTypes"];
        for (NSDictionary *documentType in documentTypes) {
            NSString *role = [documentType objectForKey:@"CFBundleTypeRole"];
            OBASSERT([role isEqualToString:@"Editor"] || [role isEqualToString:@"Viewer"]);
            if ([role isEqualToString:@"Editor"]) {
                NSArray *contentTypes = [documentType objectForKey:@"LSItemContentTypes"];
                for (NSString *contentType in contentTypes)
                    [types addObject:[contentType lowercaseString]];
            }
        }
        
        _editableFileTypes = [types copy];
    }
    
    return _editableFileTypes;
}

- (BOOL)canViewFileTypeWithIdentifier:(NSString *)uti;
{
    OBPRECONDITION(!uti || [uti isEqualToString:[uti lowercaseString]]); // our cache uses lowercase keys.
    
    if (uti == nil)
        return NO;
    
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
    OBASSERT(_roleByFileType);
    
    
    for (NSString *candidateUTI in _roleByFileType) {
        if (UTTypeConformsTo((__bridge CFStringRef)uti, (__bridge CFStringRef)candidateUTI))
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
    
    [_documentPicker.navigationController presentViewController:navigationController animated:YES completion:nil];
    
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

- (void)presentSyncError:(NSError *)syncError inViewController:(UIViewController *)viewController retryBlock:(void (^)(void))retryBlock;
{
    OBPRECONDITION(viewController);
    
    if ([syncError hasUnderlyingErrorDomain:ODAVErrorDomain code:ODAVCertificateNotTrusted]) {
        NSURLAuthenticationChallenge *challenge = [[syncError userInfo] objectForKey:ODAVCertificateTrustChallengeErrorKey];
        OUICertificateTrustAlert *certAlert = [[OUICertificateTrustAlert alloc] initForChallenge:challenge];
        certAlert.trustBlock = ^(OFCertificateTrustDuration trustDuration) {
            OFAddTrustForChallenge(challenge, trustDuration);
            if (retryBlock)
                retryBlock();
        };
        [certAlert show];
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
        [webController view]; // Load the view so we get its navigation set up
        webController.navigationItem.leftBarButtonItem = nil; // We don't want a disabled "Back" button on our error page
        [webController loadData:[httpError.userInfo objectForKey:ODAVHTTPErrorDataKey] ofType:[httpError.userInfo objectForKey:ODAVHTTPErrorDataContentTypeKey]];
        UINavigationController *webNavigationController = [[UINavigationController alloc] initWithRootViewController:webController];
        webNavigationController.navigationBar.barStyle = UIBarStyleBlack;

        webNavigationController.modalPresentationStyle = UIModalPresentationCurrentContext;
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

    OUIAlert *alert = [[OUIAlert alloc] initWithTitle:[displayError localizedDescription] message:message cancelButtonTitle:NSLocalizedStringFromTableInBundle(@"OK", @"OmniUIDocument", OMNI_BUNDLE, @"When displaying a sync error, this is the option to ignore the error.") cancelAction:NULL];

    if (retryBlock != NULL)
        [alert addButtonWithTitle:NSLocalizedStringFromTableInBundle(@"Retry Sync", @"OmniUIDocument", OMNI_BUNDLE, @"When displaying a sync error, this is the option to retry syncing.") action:retryBlock];

    if ([MFMailComposeViewController canSendMail] && ODAVShouldOfferToReportError(syncError)) {
        [alert addButtonWithTitle:NSLocalizedStringFromTableInBundle(@"Report Error", @"OmniUIDocument", OMNI_BUNDLE, @"When displaying a sync error, this is the option to report the error.") action:^{
            NSString *body = [NSString stringWithFormat:@"\n%@\n\n%@\n", [[OUIAppController controller] fullReleaseString], [syncError toPropertyList]];
            [[OUIAppController controller] sendFeedbackWithSubject:@"Sync failure" body:body];
        }];
    }

    [alert show];
}

- (void)warnAboutDiscardingUnsyncedEditsInAccount:(OFXServerAccount *)account withCancelAction:(void (^)(void))cancelAction discardAction:(void (^)(void))discardAction;
{
    if (cancelAction == NULL)
        cancelAction = ^{};

    if (!account.isCloudSyncEnabled) {
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
            OUIAlert *alert = [[OUIAlert alloc] initWithTitle:NSLocalizedStringFromTableInBundle(@"Discard unsynced edits?", @"OmniUIDocument", OMNI_BUNDLE, @"Lose unsynced changes warning: title") message:message cancelButtonTitle:NSLocalizedStringFromTableInBundle(@"Cancel", @"OmniUIDocument", OMNI_BUNDLE, @"Discard unsynced edits dialog: cancel button label") cancelAction:cancelAction];

            [alert addButtonWithTitle:NSLocalizedStringFromTableInBundle(@"Discard Edits", @"OmniUIDocument", OMNI_BUNDLE, @"Discard unsynced edits dialog: discard button label") action:discardAction];
            
            [alert show];
        }
    }];
}

- (void)createNewDocumentAtURL:(NSURL *)url templateURL:(NSURL *)templateURL completionHandler:(void (^)(NSError *errorOrNil))completionHandler;
{
    OBPRECONDITION(_document == nil);

    completionHandler = [completionHandler copy];

    Class cls = [self documentClassForURL:url];
    OBASSERT(OBClassIsSubclassOfClass(cls, [OUIDocument class]));

    __autoreleasing NSError *error = nil;
    OUIDocument *document = [[cls alloc] initEmptyDocumentToBeSavedToURL:url templateURL:templateURL error:&error];
    if (document == nil) {
        if (completionHandler)
            completionHandler(error);
        return;
    }

    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        [document saveToURL:url forSaveOperation:UIDocumentSaveForCreating completionHandler:^(BOOL saveSuccess){
            // The save completion handler isn't called on the main thread; jump over *there* to start the close (subclasses want that).
            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                [document closeWithCompletionHandler:^(BOOL closeSuccess){
                    [document didClose];

                    if (completionHandler) {
                        if (!saveSuccess) {
                            // The document instance should have gotten the real error presented some other way
                            NSError *cancelledError = [NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError userInfo:nil];
                            completionHandler(cancelledError);
                        } else {
                            completionHandler(nil);
                        }
                    }
                }];
            }];
        }];
    }];
}

- (BOOL)documentStore:(ODSStore *)store canViewFileTypeWithIdentifier:(NSString *)uti;
{
    return [self canViewFileTypeWithIdentifier:uti];
}

#pragma mark - Subclass responsibility

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
    
    if (allowCopyingSampleDocuments && launchDocumentURL == nil && ![[NSUserDefaults standardUserDefaults] boolForKey:@"SampleDocumentsHaveBeenCopiedToUserDocuments"]) {
        // Copy in a welcome document if one exists and we haven't done so for first launch yet.
        [self copySampleDocumentsToUserDocumentsWithCompletionHandler:^(NSDictionary *nameToURL) {
            [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"SampleDocumentsHaveBeenCopiedToUserDocuments"];
            
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
        [self openDocument:launchFileItem showActivityIndicator:YES];
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

            launchFileItem = [_documentStore fileItemWithURL:[NSURL URLWithString:[launchAction objectAtIndex:1]]];
            if (launchFileItem) {
                [documentPickerViewController scrollItemToVisible:launchFileItem animated:NO];
                NSString *action = [launchAction objectAtIndex:0];
                if ([action isEqualToString:OpenAction]) {
                    DEBUG_LAUNCH(1, @"Opening file item %@", [launchFileItem shortDescription]);
                    [self openDocument:launchFileItem showActivityIndicator:YES];
                    startedOpeningDocument = YES;
                } else
                    fileItemToSelect = launchFileItem;
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
        
        if (showHelp)
            [self showOnlineHelp:nil];
    } else {
        // Now that we are on screen, if we are waiting for a document to open, we'll just fade it in when it is loaded.
        _isOpeningURL = YES; // prevent preview generation while we are getting around to it
    }
    
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

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions;
{
    // UIKit throws an exception if UIBackgroundModes contains 'fetch' but the application delegate doesn't implement -application:performFetchWithCompletionHandler:. We want to be more flexible to allow apps to use our document picker w/o having to support background fetch.
    OBASSERT_IF([[[NSBundle mainBundle] infoDictionary][@"UIBackgroundModes"] containsObject:@"fetch"],
                [self respondsToSelector:@selector(application:performFetchWithCompletionHandler:)]);
    
    NSURL *launchOptionsURL = [launchOptions objectForKey:UIApplicationLaunchOptionsURLKey];
    
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
        
        UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:launchViewController];
        _window.rootViewController = navController;
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

    OFXServerAccount *account = [[OFXServerAccount alloc] initWithType:accountType remoteBaseURL:remoteBaseURL localDocumentsURL:documentsURL error:&error];
    if (!account) {
        [error log:@"Error creating account while importing %@ legacy account:", accountType.displayName];
        return;
    }
    
    account.isCloudSyncEnabled = NO;

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
    if (ODSInInInbox(url)) {
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

    OUIServerAccountSetupViewController *setup = [[OUIServerAccountSetupViewController alloc] initWithAccount:nil ofType:accountType];
    setup.location = [config objectForKey:@"location" defaultObject:setup.location];
    setup.accountName = [config objectForKey:@"accountName" defaultObject:setup.accountName];
    setup.password = [config objectForKey:@"password" defaultObject:setup.password];
    setup.nickname = [config objectForKey:@"nickname" defaultObject:setup.nickname];

    UIViewController *vc = nil;
    if (self.document) {
        vc = self.document.viewControllerToPresent;
    }
    else {
        vc = _documentPicker.navigationController;
    }

    setup.finished = ^(OUIServerAccountSetupViewController *vc, NSError *errorOrNil) {
        OBPRECONDITION([NSThread isMainThread]);
        
        OFXServerAccount *account = errorOrNil ? nil : vc.account;
        OBASSERT(account == nil || account.isCloudSyncEnabled ? [[[OFXServerAccountRegistry defaultAccountRegistry] validCloudSyncAccounts] containsObject:account] : [[[OFXServerAccountRegistry defaultAccountRegistry] validImportExportAccounts] containsObject:account]);
        [[OUIDocumentAppController controller] _didAddSyncAccount:account];
        [vc dismissViewControllerAnimated:YES completion:nil];
    };

    // Doing this during launch?
    if (_window.rootViewController != _documentPicker.navigationController) {
        [_documentPicker showDocuments];
        _window.rootViewController = _documentPicker.navigationController;
        [_window makeKeyAndVisible];
    }

    UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:setup];
    navigationController.modalPresentationStyle = UIModalPresentationFormSheet;
    navigationController.modalTransitionStyle = UIModalTransitionStyleCoverVertical;
    
    [vc presentViewController:navigationController animated:YES completion:nil];

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
            [self handleSpecialURL:url];
            return;
        }
        
        if ([url isFileURL] && OFISEQUAL([[url path] pathExtension], @"omnipresence-config")) {
            [self _loadOmniPresenceConfigFileFromURL:url];
            return;
        }
        
        [_documentPicker.selectedScopeViewController _applicationWillOpenDocument];
        _isOpeningURL = YES;
        
        // Have to wait for the docuemnt store to awake again (if we were backgrounded), initiated by -applicationWillEnterForeground:. <bug:///79297> (Bad animation closing file opened from another app)
        
        void (^handleInbox)(void) = ^(void){
            OBASSERT(_documentStore);
            
            void (^scanAction)(void) = ^{
                if (ODSInInInbox(url)) {
                    OBASSERT(_localScope);
                    
                    [OUIDocumentInbox cloneInboxItem:url toScope:_localScope completionHandler:^(ODSFileItem *newFileItem, NSError *errorOrNil) {
                        __autoreleasing NSError *deleteInboxError = nil;
                        if (![OUIDocumentInbox deleteInbox:&deleteInboxError]) {
                            NSLog(@"Failed to delete the inbox: %@", [deleteInboxError toPropertyList]);
                        }
                        
                        main_async(^{
                            if (!newFileItem) {
                                // Display Error and return.
                                OUI_PRESENT_ERROR(errorOrNil);
                                return;
                            }
                            
                            OBFinishPortingLater("TODO: Reveal scope in document picker");
//                            _documentPicker.selectedScopeViewController.selectedScope = _localScope;
                            
                            [self openDocument:newFileItem showActivityIndicator:YES];
                        });
                    }];
                } else {
                    OBASSERT_NOT_REACHED("Will the system ever give us a non-inbox item?");
                    ODSFileItem *fileItem = [_documentStore fileItemWithURL:url];
                    OBASSERT(fileItem);
                    if (fileItem)
                        [self openDocument:fileItem showActivityIndicator:YES];
                }
            };
            [_documentStore addAfterInitialDocumentScanAction:scanAction];
        };
        
        if (_documentStore) {
            handleInbox();
        }
        else {
            OBASSERT(_syncAgent);
            [_syncAgent afterAsynchronousOperationsFinish:handleInbox];
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
    DEBUG_LAUNCH(1, @"Will enter foreground");

    if (_syncAgent && _syncAgentForegrounded == NO) {
        _syncAgentForegrounded = YES;
        [_syncAgent applicationWillEnterForeground];
    }
    
    if (_documentStore && _previewGeneratorForegrounded == NO) {
        OBASSERT(_previewGenerator);
        _previewGeneratorForegrounded = YES;
        // Make sure we find the existing previews before we check if there are documents that need previews updated
        [OUIDocumentPreview populateCacheForFileItems:_documentStore.mergedFileItems completionHandler:^{
            [_previewGenerator enqueuePreviewUpdateForFileItemsMissingPreviews:_documentStore.mergedFileItems];
        }];
    }
}

- (void)applicationDidEnterBackground:(UIApplication *)application;
{
    DEBUG_LAUNCH(1, @"Did enter background");

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
        
        // Clean up any document's view state that no longer applies
        NSSet *mergedFileItemEditStateIdentifiers = [_documentStore.mergedFileItems setByPerformingBlock:^NSString *(ODSFileItem *fileItem) {
            return _normalizedDocumentStateIdentifierFromURL(fileItem.fileURL);
        }];
        
        NSDictionary *allDocsViewState = [[NSUserDefaults standardUserDefaults] dictionaryForKey:OUIDocumentViewStates];
        NSMutableDictionary *docStatesToKeep = [NSMutableDictionary dictionary];
        [allDocsViewState enumerateKeysAndObjectsUsingBlock:^(NSString *docStateIdentifier, NSDictionary *docState, BOOL *stop) {
            if ([mergedFileItemEditStateIdentifiers member:docStateIdentifier])
                [docStatesToKeep setObject:docState forKey:docStateIdentifier];
        }];
        [[NSUserDefaults standardUserDefaults] setObject:docStatesToKeep forKey:OUIDocumentViewStates];
        
        [_previewGenerator applicationDidEnterBackground];
        
        // Clean up unused previews
        [OUIDocumentPreview deletePreviewsNotUsedByFileItems:_documentStore.mergedFileItems];
        [OUIDocumentPreview flushPreviewImageCache];
    }
    
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

#pragma mark - ODSStoreDelegate

- (void)documentStore:(ODSStore *)store addedFileItems:(NSSet *)addedFileItems;
{
    // Register previews as files appear and start preview generation for them. _previewGenerator might still be nil if we are starting up, but we still want to register the previews.
    [OUIDocumentPreview populateCacheForFileItems:addedFileItems completionHandler:^{
        [_previewGenerator enqueuePreviewUpdateForFileItemsMissingPreviews:addedFileItems];
    }];
}

- (void)documentStore:(ODSStore *)store fileWithURL:(NSURL *)oldURL andDate:(NSDate *)oldDate willMoveToURL:(NSURL *)newURL;
{
    // Let the preview system know that if anyone comes asking for the new item, it should return the existing preview.
    [OUIDocumentPreview addAliasFromFileWithURL:oldURL withDate:oldDate toFileWithURL:newURL];
}

- (void)documentStore:(ODSStore *)store fileWithURL:(NSURL *)oldURL andDate:(NSDate *)date finishedMoveToURL:(NSURL *)newURL successfully:(BOOL)successfully;
{
    [OUIDocumentPreview removeAliasFromFileWithURL:oldURL withDate:date toFileWithURL:newURL];

    if (successfully) {
        [OUIDocumentPreview updateCacheAfterFileURL:oldURL withDate:date didMoveToURL:newURL];
        
        // This doesn't actually fix <bug:///93446> (Placeholder preview briefly pops into place after moving multiple items into a folder). The file item might not be found, or something else may be going on.
#if 0
        // Prompt the document picker to look up the unaliased preview now that it has been moved.
        ODSFileItem *fileItem = [store fileItemWithURL:newURL];
        if (fileItem)
            [[NSNotificationCenter defaultCenter] postNotificationName:OUIDocumentPreviewsUpdatedForFileItemNotification object:fileItem userInfo:nil];
#endif
        
        // Update document view state
        [[self class] moveDocumentStateFromURL:oldURL toURL:newURL deleteOriginal:YES];
    }
}

- (void)documentStore:(ODSStore *)store fileWithURL:(NSURL *)oldURL andDate:(NSDate *)oldDate willCopyToURL:(NSURL *)newURL;
{
    // Let the preview system know that if anyone comes asking for the new item, it should return the existing preview.
    [OUIDocumentPreview addAliasFromFileWithURL:oldURL withDate:oldDate toFileWithURL:newURL];
}

- (void)documentStore:(ODSStore *)store fileWithURL:(NSURL *)oldURL andDate:(NSDate *)oldDate finishedCopyToURL:(NSURL *)newURL andDate:(NSDate *)newDate successfully:(BOOL)successfully;
{
    [OUIDocumentPreview removeAliasFromFileWithURL:oldURL withDate:oldDate toFileWithURL:newURL];
    
    if (successfully) {
        // Update document view state
        [[self class] moveDocumentStateFromURL:oldURL toURL:newURL deleteOriginal:NO];

        [OUIDocumentPreview cachePreviewImagesForFileURL:newURL date:newDate byDuplicatingFromFileURL:oldURL date:oldDate];

        // This doesn't actually fix <bug:///93446> (Placeholder preview briefly pops into place after moving multiple items into a folder). The file item might not be found, or something else may be going on.
#if 0
        // Prompt the document picker to look up the unaliased preview now that it has been moved.
        ODSFileItem *fileItem = [store fileItemWithURL:newURL];
        if (fileItem)
            [[NSNotificationCenter defaultCenter] postNotificationName:OUIDocumentPreviewsUpdatedForFileItemNotification object:fileItem userInfo:nil];
#endif
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
        NSString *crashType = [[fileItem.fileURL lastPathComponent] stringByDeletingPathExtension];
        if ([crashType isEqual:@"crash-abort"])
            abort();
        if ([crashType isEqual:@"crash-null"])
            NSLog(@"%d", *(int *)[@"0" intValue]);
        if ([crashType isEqual:@"crash-exception"])
            [NSException raise:NSGenericException reason:@"testing unhandled exception"];
        if ([crashType isEqual:@"crash-signal"])
            raise(SIGTRAP); // really the same as abort since it raises SIGABRT
#if 0
        if ([crashType isEqual:@"crash-report"]) {
            NSData *reportData = [[PLCrashReporter sharedReporter] generateLiveReport];
            PLCrashReport *report = [[PLCrashReport alloc] initWithData:reportData error:NULL];
            NSLog(@"report:\n%@", [PLCrashReportTextFormatter stringValueForCrashReport:report withTextFormat:PLCrashReportTextFormatiOS]);
            return;
        }
#endif
    }
    
    // If we crash in trying to open this document, we should stay in the file picker the next time we launch rather than trying to open it over and over again
    self.launchAction = nil;
    
    if (![_previewGenerator shouldOpenDocumentWithFileItem:fileItem])
        return;
    
    [self openDocument:fileItem showActivityIndicator:YES];
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

    [self openDocument:fileItem fileItemToRevealFrom:fileItemToRevealFrom showActivityIndicator:YES];
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
    UIViewController *top = _documentPicker.navigationController.topViewController;
    
    if ([top respondsToSelector:@selector(_preferredVisibleItemFromSet:)])
        return [(OUIDocumentPickerViewController *)top _preferredVisibleItemFromSet:fileItems];
    else
        return nil;
}

- (BOOL)previewGenerator:(OUIDocumentPreviewGenerator *)previewGenerator shouldGeneratePreviewForURL:(NSURL *)fileURL;
{
    return YES;
}

- (Class)previewGenerator:(OUIDocumentPreviewGenerator *)previewGenerator documentClassForFileURL:(NSURL *)fileURL;
{
    return [self documentClassForURL:fileURL];
}

#pragma mark - OUIWebViewControllerDelegate
- (void)webViewControllerDidClose:(OUIWebViewController *)webViewController;
{
    [webViewController.presentingViewController dismissViewControllerAnimated:YES completion:NULL];
}

#pragma mark - OUIUndoBarButtonItemTarget

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

static NSString *_normalizedDocumentStateIdentifierFromURL(NSURL *url)
{
    // Sadly, this doesn't work if the URL doesn't exist. We could look for an ancestor directory that exists, normalize that, and then tack on the suffix again.
    //    OBPRECONDITION([url isFileURL]);
    //    OBPRECONDITION([[NSFileManager defaultManager] fileExistsAtPath:[url path] isDirectory:NULL]);
    
    // Need consistent mapping of /private/var/mobile vs /var/mobile.
    return [[[url URLByResolvingSymlinksInPath] URLByStandardizingPath] path];
}

static NSString * const OUIDocumentViewStates = @"OUIDocumentViewStates";
+ (NSDictionary *)documentStateForURL:(NSURL *)documentURL;
{
    NSDictionary *documentViewStates = [[NSUserDefaults standardUserDefaults] dictionaryForKey:OUIDocumentViewStates];
    return [documentViewStates objectForKey:_normalizedDocumentStateIdentifierFromURL(documentURL)];
}

+ (void)setDocumentState:(NSDictionary *)documentState forURL:(NSURL *)documentURL;
{
    NSMutableDictionary *allDocsViewState = [NSMutableDictionary dictionaryWithDictionary:[[NSUserDefaults standardUserDefaults] dictionaryForKey:OUIDocumentViewStates]];
    [allDocsViewState setObject:documentState forKey:_normalizedDocumentStateIdentifierFromURL(documentURL)];
    [[NSUserDefaults standardUserDefaults] setObject:allDocsViewState forKey:OUIDocumentViewStates];
}

+ (void)moveDocumentStateFromURL:(NSURL *)fromDocumentURL toURL:(NSURL *)toDocumentURL deleteOriginal:(BOOL)deleteOriginal;
{
    NSMutableDictionary *allDocsViewState = [NSMutableDictionary dictionaryWithDictionary:[[NSUserDefaults standardUserDefaults] dictionaryForKey:OUIDocumentViewStates]];
    NSString *fromDocumentStateIdentifier = _normalizedDocumentStateIdentifierFromURL(fromDocumentURL);
    NSDictionary *state = [allDocsViewState objectForKey:fromDocumentStateIdentifier];
    if (state) {
        [allDocsViewState setObject:state forKey:_normalizedDocumentStateIdentifierFromURL(toDocumentURL)];
        if (deleteOriginal)
            [allDocsViewState removeObjectForKey:fromDocumentStateIdentifier];
        [[NSUserDefaults standardUserDefaults] setObject:allDocsViewState forKey:OUIDocumentViewStates];
    }
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
        
        if ([_documentStore.scopes indexOfObjectIdenticalTo:_documentPicker.selectedScopeViewController.selectedScope] == NSNotFound) {
            OBFinishPortingLater("TODO: Reveal scope in document picker; Should pick a scope that makes sense -- maybe any scope that has documents?");
//            _documentPicker.selectedScopeViewController.selectedScope = _documentStore.defaultUsableScope;
        }
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
    _window.rootViewController = _documentPicker.navigationController;
    [_window makeKeyAndVisible];
    [OUIDocumentPreview populateCacheForFileItems:_documentStore.mergedFileItems completionHandler:^{
    }];
}

- (void)_mainThread_finishedLoadingDocument:(OUIDocument *)document fileItemToRevealFrom:(ODSFileItem *)fileItemToRevealFrom activityIndicator:(OUIActivityIndicator *)activityIndicator completionHandler:(void (^)(void))completionHandler;
{
    OBASSERT([NSThread isMainThread]);
    [self _setDocument:document];
    _isOpeningURL = NO;
    
    UIViewController *presentFromViewController = _documentPicker.navigationController.topViewController;
    UIViewController <OUIDocumentViewController> *documentViewController = _document.documentViewController;
    UIViewController *toPresent = _document.viewControllerToPresent;
    UIView *view = [documentViewController view]; // make sure the view is loaded in case -pickerAnimationViewForTarget: doesn't and return a subview thereof.
    
    [UIView performWithoutAnimation:^{
        [view setFrame:presentFromViewController.view.bounds];
        [view layoutIfNeeded];
        [toPresent.view setFrame:presentFromViewController.view.bounds];
        [toPresent.view layoutIfNeeded];
    }];
    
    OBASSERT(![document hasUnsavedChanges]); // We just loaded our document and created our view, we shouldn't have any view state that needs to be saved. If we do, we should probably investigate to prevent bugs like <bug:///80514> ("Document Updated" on (null) alert is still hanging around), perhaps discarding view state changes if we can't prevent them.

    [self mainThreadFinishedLoadingDocument:document];
    
    
    // Start automatically tracking undo state from this document's undo manager
    [[self undoBarButtonItem] addUndoManager:_document.undoManager];
    
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

    // Capture scope for the animation...
    completionHandler = [completionHandler copy];
    
    if ([documentViewController respondsToSelector:@selector(restoreDocumentViewState:)])
        [documentViewController restoreDocumentViewState:[OUIDocumentAppController documentStateForURL:fileItem.fileURL]];
    
    OUIDocumentOpenAnimator *animator = [OUIDocumentOpenAnimator sharedAnimator];
    animator.documentPicker = _documentPicker;
    animator.fileItem = fileItemToRevealFrom;
    animator.actualFileItem = fileItem;
    toPresent.transitioningDelegate = animator;
    toPresent.modalPresentationStyle = UIModalPresentationFullScreen;
    
    BOOL animateDocument = YES;
    
    if (_window.rootViewController != _documentPicker.navigationController) {
        [_documentPicker showDocuments];
        _window.rootViewController = _documentPicker.navigationController;
        [_window makeKeyAndVisible];
        animateDocument = NO;
    }
    
    [_documentPicker.navigationController.topViewController presentViewController:toPresent animated:animateDocument completion:^{
        if ([documentViewController respondsToSelector:@selector(documentFinishedOpening)])
            [documentViewController documentFinishedOpening];
        if (completionHandler)
            completionHandler();
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
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_documentStateChanged:) name:UIDocumentStateChangedNotification object:_document];
    }
}

- (void)_didAddSyncAccount:(OFXServerAccount *)account;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    if (account != nil && account.isCloudSyncEnabled) {
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

    OBASSERT((state & UIDocumentStateInConflict) == 0, "We no longer use iCloud and we have no way of making conflict versions, so we don't expect to see the conflict state");
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

@end
