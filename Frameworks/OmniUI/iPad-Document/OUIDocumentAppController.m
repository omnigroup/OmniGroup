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
#import <OmniFileExchange/OmniFileExchange.h>
#import <OmniFileStore/Errors.h>
#import <OmniFileStore/OFSDocumentStore.h>
#import <OmniFileStore/OFSDocumentStoreFileItem.h>
#import <OmniFileStore/OFSDocumentStoreLocalDirectoryScope.h>
#import <OmniFileStore/OFSFileInfo.h>
#import <OmniFileStore/OFSURL.h>
#import <OmniFoundation/NSDictionary-OFExtensions.h>
#import <OmniFoundation/NSFileManager-OFSimpleExtensions.h>
#import <OmniFoundation/NSSet-OFExtensions.h>
#import <OmniFoundation/NSString-OFExtensions.h>
#import <OmniFoundation/NSURL-OFExtensions.h>
#import <OmniFoundation/OFBindingPoint.h>
#import <OmniFoundation/OFCredentials.h>
#import <OmniFoundation/OFPreference.h>
#import <OmniFoundation/OFUTI.h>
#import <OmniUI/OUIAboutPanel.h>
#import <OmniUI/OUIActivityIndicator.h>
#import <OmniUI/OUIAlert.h>
#import <OmniUI/OUIBarButtonItem.h>
#import <OmniUI/OUICertificateTrustAlert.h>
#import <OmniUI/OUIInspector.h>
#import <OmniUI/OUIMenuOption.h>
#import <OmniUI/OUIShieldView.h>
#import <OmniUI/OUIWebViewController.h>
#import <OmniUI/UIBarButtonItem-OUITheming.h>
#import <OmniUI/UIView-OUIExtensions.h>
#import <OmniUIDocument/OUIDocument.h>
#import <OmniUIDocument/OUIDocumentPicker.h>
#import <OmniUIDocument/OUIDocumentPickerFileItemView.h>
#import <OmniUIDocument/OUIDocumentPreview.h>
#import <OmniUIDocument/OUIDocumentPreviewView.h>
#import <OmniUIDocument/OUIDocumentViewController.h>
#import <OmniUIDocument/OUIMainViewController.h>
#import <OmniUIDocument/OUIToolbarTitleButton.h>
#import <SenTestingKit/SenTestSuite.h>

#import "OUICloudSetupViewController.h"
#import "OUIDocument-Internal.h"
#import "OUIDocumentAppController-Internal.h"
#import "OUIDocumentInbox.h"
#import "OUIDocumentPicker-Internal.h"
#import "OUIDocumentPickerItemView-Internal.h"
#import "OUIDocumentPreviewGenerator.h"
#import "OUILaunchViewController.h"
#import "OUIMainViewController-Internal.h"
#import "OUIRestoreSampleDocumentListController.h"
#import "OUISyncMenuController.h"
#import "OUIServerAccountSetupViewController.h"

RCS_ID("$Id$");

// OUIDocumentConflictResolutionViewControllerDelegate is gone
OBDEPRECATED_METHOD(-conflictResolutionPromptForFileItem:);
OBDEPRECATED_METHOD(-conflictResolutionCancelled:);
OBDEPRECATED_METHOD(-conflictResolutionFinished:);

static NSString * const WelcomeDocumentName = @"Welcome";
static NSString * const OpenAction = @"open";

#if 0 && defined(DEBUG)
    #define DEBUG_LAUNCH(format, ...) NSLog(@"LAUNCH: " format, ## __VA_ARGS__)
#else
    #define DEBUG_LAUNCH(format, ...) do {} while (0)
#endif

@interface OUIDocumentAppController (/*Private*/) <OUIDocumentPreviewGeneratorDelegate>
@property(nonatomic,copy) NSArray *launchAction;
@end

static unsigned SyncAgentRunningAccountsContext;

@implementation OUIDocumentAppController
{
    UIWindow *_window;
    
    dispatch_once_t _roleByFileTypeOnce;
    NSDictionary *_roleByFileType;
    
    NSArray *_editableFileTypes;
    
    UIButton *_documentTitleButton;
    UITextField *_documentTitleTextField;
    BOOL _hasAttemptedRename;

    OUIDocument *_document;
    
    OUIShieldView *_shieldView;
    BOOL _wasInBackground;
    BOOL _didFinishLaunching;
    BOOL _isOpeningURL;

    OFXAgent *_syncAgent;
    OFSDocumentStore *_documentStore;
    OFSDocumentStoreLocalDirectoryScope *_localScope;
    
    OUIDocumentPreviewGenerator *_previewGenerator;
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
    
    OBASSERT(_undoBarButtonItem.undoManager == nil);
    _undoBarButtonItem.undoBarButtonItemTarget = nil;
}

// UIApplicationDelegate has an @optional window property. Our superclass conforms to this protocol, so clang assumes we already have the property, it seems (even though we redeclare it).
@synthesize window = _window;

@synthesize appMenuBarItem = _appMenuBarItem;
- (UIBarButtonItem *)appMenuBarItem;
{
    if (!_appMenuBarItem) {
        NSString *imageName = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"OUIAppMenuImage"];
        if ([NSString isEmptyString:imageName])
            imageName = @"OUIAppMenu.png";
        
        UIImage *appMenuImage = [UIImage imageNamed:imageName];
        OBASSERT(appMenuImage);
        _appMenuBarItem = [[UIBarButtonItem alloc] initWithImage:appMenuImage style:UIBarButtonItemStylePlain target:self action:@selector(showAppMenu:)];
        
        _appMenuBarItem.accessibilityLabel = NSLocalizedStringFromTableInBundle(@"Help and Settings", @"OmniUIDocument", OMNI_BUNDLE, @"Help and Settings toolbar item accessibility label.");
    }
    
    return _appMenuBarItem;
}

@synthesize closeDocumentBarButtonItem = _closeDocumentBarButtonItem;
- (UIBarButtonItem *)closeDocumentBarButtonItem;
{
    if (!_closeDocumentBarButtonItem) {
        NSString *closeDocumentTitle = NSLocalizedStringWithDefaultValue(@"Documents <back button>", @"OmniUIDocument", OMNI_BUNDLE, @"Documents", @"Toolbar button title for returning to list of documents.");
        _closeDocumentBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:closeDocumentTitle
                                                                        style:UIBarButtonItemStyleBordered target:self action:@selector(closeDocument:)];
        
        [_closeDocumentBarButtonItem applyAppearanceWithBackgroundType:[self defaultBarButtonBackgroundType]];
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

- (BOOL)shouldOpenWelcomeDocumentOnFirstLaunch;
{
    // Apps may wish to override this behavior in a subclass
    return YES;
}

- (IBAction)makeNewDocument:(id)sender;
{
    [self.documentPicker newDocument:sender];
}

- (void)closeDocument:(id)sender;
{
    // OmniOutliner's closeDocument overrides this without calling super. See comment there. If you change this, you probably need to change OmniOutliner's -[AppController closeDocument:].
    [self closeDocumentWithAnimationType:OUIDocumentAnimationTypeZoom completionHandler:nil];
}

- (void)closeDocumentWithAnimationType:(OUIDocumentAnimationType)animation completionHandler:(void (^)(void))completionHandler;
{
    OBPRECONDITION(_document);
    
    if (!_document) {
        // Uh. Whatever.
        _mainViewController.innerViewController = self.documentPicker;
        if (completionHandler)
            completionHandler();
        return;
    }
    
    completionHandler = [completionHandler copy]; // capture scope
    
    // Stop tracking the state from this document's undo manager
    [self undoBarButtonItem].undoManager = nil;
    
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
    
    // Start up the spinner and stop accepting events.
    UIViewController *viewController = _document.viewController;
    OUIActivityIndicator *activityIndicator = [OUIActivityIndicator showActivityIndicatorInView:viewController.view withColor:viewController.activityIndicatorColorForMainViewController];
    
    [[UIApplication sharedApplication] beginIgnoringInteractionEvents];
    
    OBStrongRetain(_document);
    [_document closeWithCompletionHandler:^(BOOL success){
        
        // OBFinishPorting: Should rename this and all the ancillary methods to 'did'. This clears the _book pointer, which must be valid until the close (and possible resulting save) are done.
        [_document willClose];
        self.launchAction = nil;
        
        // Doing the -autorelease in the completion handler wasn't late enough. This may not be either...
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            OBASSERT([NSThread isMainThread]);
            OBStrongRelease(_document);
        }];
        
        // If the document was saved, it will have already updated *its* previews, if we were launched into a document w/o the document picker ever being visible, we might not have previews loaded for other documents
        [OUIDocumentPreview populateCacheForFileItems:_documentStore.mergedFileItems completionHandler:^{
            
            switch (animation) {
                case OUIDocumentAnimationTypeZoom: {
                    OFSDocumentStoreFileItem *fileItem = _document.fileItem;
                    
                    OUIDocumentPicker *documentPicker = self.documentPicker;
                    UIView *documentView = [self pickerAnimationViewForTarget:_document];
                    [_mainViewController setInnerViewController:documentPicker animated:YES
                                                     fromRegion:^UIView *(CGRect *outRect) {
                                                         *outRect = CGRectZero;
                                                         return documentView;
                                                     } toRegion:^UIView *(CGRect *outRect) {
                                                         OUIDocumentPickerFileItemView *fileItemView = [documentPicker.activeScrollView fileItemViewForFileItem:fileItem];
                                                         OBASSERT(fileItemView != nil);
                                                         [fileItemView loadPreviews];
                                                         
                                                         OUIDocumentPreviewView *previewView = fileItemView.previewView;
                                                         *outRect = previewView.imageBounds;
                                                         return previewView;
                                                     } transitionAction:^{
                                                         [activityIndicator hide];
                                                         [documentPicker.activeScrollView sortItems];
                                                         [documentPicker scrollItemToVisible:fileItem animated:NO];
                                                     } completionAction:^{
                                                         [[UIApplication sharedApplication] endIgnoringInteractionEvents];
                                                         
                                                         if (completionHandler)
                                                             completionHandler();
                                                     }];
                    break;
                }
                case OUIDocumentAnimationTypeDissolve: {
                    OUIDocumentPicker *documentPicker = self.documentPicker;
                    [UIView transitionWithView:_mainViewController.view duration:0.25
                                       options:UIViewAnimationOptionTransitionCrossDissolve
                                    animations:^{
                                        OUIWithoutAnimating(^{ // some animations get added anyway if we specify NO ... avoid a weird jump from the start to end frame
                                            [_mainViewController setInnerViewController:documentPicker animated:NO fromView:nil toView:nil];
                                        });
                                        [_mainViewController.view layoutIfNeeded];
                                    }
                                    completion:^(BOOL finished){
                                        [activityIndicator hide];
                                        [[UIApplication sharedApplication] endIgnoringInteractionEvents];
                                        
                                        if (completionHandler)
                                            completionHandler();
                                    }];
                    break;
                }
                default:
                    // this shouldn't happen, but JUST IN CASE...
                    OBASSERT_NOT_REACHED("Should've specificed a valid OUIDocumentAnimationType");
                    if (completionHandler)
                        completionHandler();
            }
            
            [self _setDocument:nil];
            
            [_previewGenerator documentClosed];
        }];
    }];
}

- (void)documentDidDisableEnditing:(OUIDocument *)document;
{
    OBPRECONDITION(document.editingDisabled == YES); // When we end editing, we'll look at this and ignore the rename request.
    
    OUIWithoutAnimating(^{
        [_documentTitleTextField endEditing:YES];
    });
}

- (void)updateTitleBarButtonItemSizeUsingInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation;
{
    [self updateDocumentTitle:nil];
}

- (OUIBarButtonItemBackgroundType)defaultBarButtonBackgroundType;
{
    return OUIBarButtonItemBackgroundTypeClear;
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

- (void)duplicateAndOpenFileItem:(OFSDocumentStoreFileItem *)fileItem completionHandler:(void (^)(OFSDocumentStoreFileItem *duplicateFileItem))completionHandler;
{
    OBFinishPorting;
#if 0
    [self.documentPicker.documentStore addDocumentWithScope:fileItem.scope inFolderNamed:nil fromURL:fileItem.fileURL option:OFSDocumentStoreAddByRenaming completionHandler:^(OFSDocumentStoreFileItem *duplicateFileItem, NSError *error) {
        
        OBASSERT([NSThread isMainThread]); // gets enqueued on the main thread, but even if it was invoked on the background serial queue, this would be OK as long as we don't access the mutable arrays until all the blocks are done
        
        if (!duplicateFileItem) {
            OBASSERT(error);
            if (error) // let's not crash, though...
                OUI_PRESENT_ALERT(error);
            return;
        }
        
        // Copy the previews for the original file item to be the previews for the duplicate.
        [OUIDocumentPreview cachePreviewImagesForFileURL:duplicateFileItem.fileURL date:duplicateFileItem.date byDuplicatingFromFileURL:fileItem.fileURL date:fileItem.date];
        
        // If we crash in trying to open this document, we should stay in the file picker the next time we launch rather than trying to open it over and over again
        self.launchAction = nil;
        
        if (![_previewGenerator shouldOpenDocumentWithFileItem:duplicateFileItem])
            return;
        
        [self openDocument:duplicateFileItem animation:OUIDocumentAnimationTypeZoom showActivityIndicator:YES];
        
        if (completionHandler)
            completionHandler(duplicateFileItem);
    }];
#endif
}

- (void)openDocument:(OFSDocumentStoreFileItem *)fileItem animation:(OUIDocumentAnimationType)animation showActivityIndicator:(BOOL)showActivityIndicator;
{
    OBPRECONDITION([NSThread isMainThread]);
    OBPRECONDITION(fileItem);
    
    void (^onFail)(void) = ^{
        // The launch document failed to load -- don't leave the user with no document picker and no open document!
        if (_mainViewController.innerViewController != self.documentPicker)
            [self _fadeInDocumentPickerScrollingToFileItem:fileItem];
        _isOpeningURL = NO;
    };
    onFail = [onFail copy];
    
    // Need to provoke download, and if this is a launch-time open, we need to fall back to the document picker instead. Maybe we shouldn't actually provoke download in the launch time case, really. The user might want to tap another document and not compete for download bandwidth.
    if (!fileItem.isDownloaded) {
        __autoreleasing NSError *error = nil;
        if (![fileItem requestDownload:&error])
            OUI_PRESENT_ERROR(error);
        onFail();
        return;
    }
    
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
        OFSDocumentStoreScope *originalScope = fileItem.scope;
        if (![originalScope isFileInContainer:targetURL]) {
            onFail();
            return;
        }

        OFSDocumentStoreFileItem *targetItem = [originalScope fileItemWithURL:targetURL];
        [self openDocument:targetItem animation:animation showActivityIndicator:showActivityIndicator];
        return;
    }

    OUIActivityIndicator *activityIndicator = nil;
    OUIDocumentPickerFileItemView *fileItemView = nil;
    if (animation == OUIDocumentAnimationTypeZoom) {
        fileItemView = [self.documentPicker.activeScrollView fileItemViewForFileItem:fileItem];
        OBASSERT(fileItemView);
        
        fileItemView.highlighted = YES;
        
        if (showActivityIndicator)
            activityIndicator = [OUIActivityIndicator showActivityIndicatorInView:fileItemView.previewView];
    } else {
        // Launch time document open, for example
        if (showActivityIndicator)
            activityIndicator = [OUIActivityIndicator showActivityIndicatorInView:_mainViewController.view];
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
        
        [[UIApplication sharedApplication] beginIgnoringInteractionEvents];
        
        // Dismiss any popovers that may be presented.
        [self dismissPopoverAnimated:YES];
        
        [document openWithCompletionHandler:^(BOOL success){
            if (animation == OUIDocumentAnimationTypeZoom) {
                OBASSERT(fileItemView.highlighted);
                fileItemView.highlighted = NO;
            } else {
                OBASSERT(fileItemView == nil);
            }
            
            if (!success) {
                OUIDocumentHandleDocumentOpenFailure(document, nil);
                
                [activityIndicator hide];
                [[UIApplication sharedApplication] endIgnoringInteractionEvents];
                
                onFail();
                return;
            }
            
            [self _mainThread_finishedLoadingDocument:document animation:animation activityIndicator:activityIndicator completionHandler:^{
                [[UIApplication sharedApplication] endIgnoringInteractionEvents];
                
                // Ensure that when the document is closed we'll be using a filter that shows it.
                [self.documentPicker ensureSelectedFilterMatchesFileItem:fileItem];
            }];
        }];
    };
    
    if (_document) {
        // If we have a document open, wait for it to close before starting to open the new one.
        doOpen = [doOpen copy];
        
        [[UIApplication sharedApplication] beginIgnoringInteractionEvents];
        
        [_document closeWithCompletionHandler:^(BOOL success) {
            [self _setDocument:nil];
            
            doOpen();
            [[UIApplication sharedApplication] endIgnoringInteractionEvents];
        }];
    } else {
        // Just open immediately
        doOpen();
    }
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

- (void)copySampleDocumentsFromDirectoryURL:(NSURL *)sampleDocumentsDirectoryURL toScope:(OFSDocumentStoreScope *)scope stringTableName:(NSString *)stringTableName completionHandler:(void (^)(NSDictionary *nameToURL))completionHandler;
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

        [scope addDocumentInFolderAtURL:nil baseName:localizedTitle fromURL:sampleURL option:OFSDocumentStoreAddByRenaming completionHandler:^(OFSDocumentStoreFileItem *duplicateFileItem, NSError *error){
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
            // If there is a Welcome document, make it sort to the top by date.
            NSURL *welcomeURL = [nameToURL objectForKey:WelcomeDocumentName];
            if (welcomeURL)
                [fileManager touchItemAtURL:welcomeURL error:NULL];
            
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

#pragma mark -
#pragma mark OUIAppController subclass

- (UIViewController *)topViewController;
{
    return _mainViewController;
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


#pragma mark - NSObject (OUIAppMenuTarget)

- (NSString *)feedbackMenuTitle;
{
    OBASSERT_NOT_REACHED("Should be subclassed to provide something nicer.");
    return @"HALP ME!";
}

- (NSString *)aboutMenuTitle;
{
    NSString *format = NSLocalizedStringFromTableInBundle(@"About %@", @"OmniUIDocument", OMNI_BUNDLE, @"Default title for the About menu item");
    return [NSString stringWithFormat:format, self.applicationName];
}

// Invoked by the app menu
- (void)sendFeedback:(id)sender;
{
    NSString *subject = [NSString stringWithFormat:@"%@ Feedback", self.fullReleaseString];
 
    [self sendFeedbackWithSubject:subject body:nil];
}

- (void)_showWebViewWithURL:(NSURL *)url title:(NSString *)title;
{
    if (url == nil)
        return;
    
    OUIWebViewController *webController = [[OUIWebViewController alloc] init];
    webController.title = title;
    webController.URL = url;
    UINavigationController *webNavigationController = [[UINavigationController alloc] initWithRootViewController:webController];
    webNavigationController.navigationBar.barStyle = UIBarStyleBlack;
    
    [self.topViewController presentViewController:webNavigationController animated:YES completion:nil];
}

- (void)_showWebViewWithPath:(NSString *)path title:(NSString *)title;
{
    if (!path)
        return;
    return [self _showWebViewWithURL:[NSURL fileURLWithPath:path] title:title];
}

- (void)showReleaseNotes:(id)sender;
{
    [self _showWebViewWithPath:[[NSBundle mainBundle] pathForResource:@"MessageOfTheDay" ofType:@"html"] title:NSLocalizedStringFromTableInBundle(@"Release Notes", @"OmniUIDocument", OMNI_BUNDLE, @"release notes html screen title")];
}

- (void)showOnlineHelp:(id)sender;
{
    NSString *helpBookFolder = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"OUIHelpBookFolder"];
    NSString *helpBookName = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"OUIHelpBookName"];
    OBASSERT(helpBookName != nil);
    NSString *webViewTitle = [[NSBundle mainBundle] localizedStringForKey:@"OUIHelpBookName" value:helpBookName table:@"InfoPlist"];
    
    NSString *indexPath = [[NSBundle mainBundle] pathForResource:@"index" ofType:@"html" inDirectory:helpBookFolder];
    if (indexPath == nil)
        indexPath = [[NSBundle mainBundle] pathForResource:@"top" ofType:@"html" inDirectory:helpBookFolder];
    OBASSERT(indexPath != nil);
    [self _showWebViewWithPath:indexPath title:webViewTitle];
}

- (void)showAboutPanel:(id)sender;
{
    [OUIAboutPanel displayInSheet];
}

- (void)restoreSampleDocuments:(id)sender;
{
    UIViewController *viewController = [[OUIRestoreSampleDocumentListController alloc] init];
    UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:viewController];
    navigationController.modalPresentationStyle = UIModalPresentationFormSheet;
    navigationController.modalTransitionStyle = UIModalTransitionStyleCoverVertical;
    
    [self.topViewController presentViewController:navigationController animated:YES completion:nil];
    
}

- (void)runTests:(id)sender;
{
    Class cls = NSClassFromString(@"SenTestSuite");
    OBASSERT(cls);
    
    SenTestSuite *suite = [cls defaultTestSuite];
    [suite run];
}

- (void)showAppMenu:(id)sender;
{
    if (!_appMenuController)
        _appMenuController = [[OUIMenuController alloc] initWithDelegate:self];
    
    OBASSERT([sender isKindOfClass:[UIBarButtonItem class]]); // ...or we shouldn't be passing it as the bar item in the next call
    [_appMenuController showMenuFromBarItem:sender];
}

- (void)manualSync:(id)sender;
{
    NSError *lastSyncError = self.documentPicker.selectedScopeError;
    if (lastSyncError != nil) {
        [self presentSyncError:lastSyncError retryBlock:^{
            [_syncAgent sync:^{}];
        }];
        return;
    }

    [_syncAgent sync:^{}];
}

#pragma mark - OFSDocumentStoreDelegate

- (Class)documentStore:(OFSDocumentStore *)store fileItemClassForURL:(NSURL *)fileURL;
{
    return [OFSDocumentStoreFileItem class];
}

- (NSString *)documentStoreBaseNameForNewFiles:(OFSDocumentStore *)store;
{
    return NSLocalizedStringFromTableInBundle(@"My Document", @"OmniUIDocument", OMNI_BUNDLE, @"Base name for newly created documents. This will have an number appended to it to make it unique.");
}

- (NSArray *)documentStoreEditableDocumentTypes:(OFSDocumentStore *)store;
{
    return [self editableFileTypes];
}

- (void)presentSyncError:(NSError *)syncError inNavigationController:(UINavigationController *)navigationController retryBlock:(void (^)(void))retryBlock;
{
    if ([syncError hasUnderlyingErrorDomain:OFSErrorDomain code:OFSCertificateNotTrusted]) {
        NSURLAuthenticationChallenge *challenge = [[syncError userInfo] objectForKey:OFSCertificateTrustChallengeErrorKey];
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

    NSError *httpError = [syncError underlyingErrorWithDomain:OFSDAVHTTPErrorDomain];
    while (httpError != nil && [httpError.userInfo objectForKey:NSUnderlyingErrorKey])
        httpError = [httpError.userInfo objectForKey:NSUnderlyingErrorKey];

    if (httpError != nil && [[httpError domain] isEqualToString:OFSDAVHTTPErrorDomain] && [[httpError.userInfo objectForKey:OFSDAVHTTPErrorDataContentTypeKey] isEqualToString:@"text/html"]) {
        OUIWebViewController *webController = [[OUIWebViewController alloc] init];
        // webController.title = [displayError localizedDescription];
        [webController view]; // Load the view so we get its navigation set up
        webController.navigationItem.leftBarButtonItem = nil; // We don't want a disabled "Back" button on our error page
        [webController loadData:[httpError.userInfo objectForKey:OFSDAVHTTPErrorDataKey] ofType:[httpError.userInfo objectForKey:OFSDAVHTTPErrorDataContentTypeKey]];
        UINavigationController *webNavigationController = [[UINavigationController alloc] initWithRootViewController:webController];
        webNavigationController.navigationBar.barStyle = UIBarStyleBlack;
        if (navigationController != nil) {
            webNavigationController.modalPresentationStyle = UIModalPresentationCurrentContext;
            [navigationController presentViewController:webNavigationController animated:YES completion:retryBlock];
        } else {
            [self.topViewController presentViewController:webNavigationController animated:YES completion:retryBlock];
        }

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

    OUIAlert *alert = [[OUIAlert alloc] initWithTitle:[displayError localizedDescription] message:message cancelButtonTitle:NSLocalizedStringFromTableInBundle(@"Ignore", @"OmniUIDocument", OMNI_BUNDLE, @"When displaying a sync error, this is the option to ignore the error.") cancelAction:NULL];

    if (retryBlock != NULL)
        [alert addButtonWithTitle:NSLocalizedStringFromTableInBundle(@"Retry Sync", @"OmniUIDocument", OMNI_BUNDLE, @"When displaying a sync error, this is the option to retry syncing.") action:retryBlock];

    if ([MFMailComposeViewController canSendMail] && OFSShouldOfferToReportError(syncError)) {
        [alert addButtonWithTitle:NSLocalizedStringFromTableInBundle(@"Report Error", @"OmniUIDocument", OMNI_BUNDLE, @"When displaying a sync error, this is the option to report the error.") action:^{
            NSString *body = [NSString stringWithFormat:@"\n%@\n\n%@\n", [[OUIAppController controller] fullReleaseString], [syncError toPropertyList]];
            [[OUIAppController controller] sendFeedbackWithSubject:@"Sync failure" body:body];
        }];
    }

    [alert show];
}

- (void)presentSyncError:(NSError *)syncError retryBlock:(void (^)(void))retryBlock;
{
    [self presentSyncError:syncError inNavigationController:nil retryBlock:retryBlock];
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
            else
                message = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"The \"%@\" account has %ld edited documents which have not yet been synced up to the cloud. Do you wish to discard those edits?", @"OmniUIDocument", OMNI_BUNDLE, @"Discard unsynced edits dialog: message format"), account.displayName, count];
            OUIAlert *alert = [[OUIAlert alloc] initWithTitle:NSLocalizedStringFromTableInBundle(@"Discard unsynced edits?", @"OmniUIDocument", OMNI_BUNDLE, @"Lose unsynced changes warning: title") message:message cancelButtonTitle:NSLocalizedStringFromTableInBundle(@"Cancel", @"OmniUIDocument", OMNI_BUNDLE, @"Discard unsynced edits dialog: cancel button label") cancelAction:cancelAction];

            [alert addButtonWithTitle:NSLocalizedStringFromTableInBundle(@"Discard Edits", @"OmniUIDocument", OMNI_BUNDLE, @"Discard unsynced edits dialog: discard button label") action:discardAction];
            
            [alert show];
        }
    }];
}

- (void)createNewDocumentAtURL:(NSURL *)url completionHandler:(void (^)(NSError *errorOrNil))completionHandler;
{
    OBPRECONDITION(_document == nil);
    
    completionHandler = [completionHandler copy];
    
    Class cls = [self documentClassForURL:url];
    OBASSERT(OBClassIsSubclassOfClass(cls, [OUIDocument class]));
    
    __autoreleasing NSError *error = nil;
    OUIDocument *document = [[cls alloc] initEmptyDocumentToBeSavedToURL:url error:&error];
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
                    [document willClose];

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

- (BOOL)documentStore:(OFSDocumentStore *)store canViewFileTypeWithIdentifier:(NSString *)uti;
{
    return [self canViewFileTypeWithIdentifier:uti];
}

#pragma mark - OUIMenuControllerDelegate

//#define SHOW_ABOUT_MENU_ITEM 1

- (NSArray *)menuControllerOptions:(OUIMenuController *)menu;
{
    if (menu == _appMenuController) {
        NSMutableArray *options = [NSMutableArray array];
        OUIMenuOption *option;
        
#ifdef SHOW_ABOUT_MENU_ITEM
        option = [OUIMenuController menuOptionWithFirstResponderSelector:@selector(showAboutPanel:)
                                                                   title:NSLocalizedStringFromTableInBundle(@"About", @"OmniUIDocument", OMNI_BUNDLE, @"App menu item title")
                                                                   image:[UIImage imageNamed:@"OUIMenuItemAbout.png"]];
        [options addObject:option];
#endif
        
        option = [OUIMenuController menuOptionWithFirstResponderSelector:@selector(showOnlineHelp:)
                                                                   title:[[NSBundle mainBundle] localizedStringForKey:@"OUIHelpBookName" value:[[NSBundle mainBundle] objectForInfoDictionaryKey:@"OUIHelpBookName"] table:@"InfoPlist"]
                                                                   image:[UIImage imageNamed:@"OUIMenuItemHelp.png"]];
        [options addObject:option];
        
        option = [OUIMenuController menuOptionWithFirstResponderSelector:@selector(sendFeedback:)
                                                                   title:[[OUIDocumentAppController controller] feedbackMenuTitle]
                                                                   image:[UIImage imageNamed:@"OUIMenuItemSendFeedback.png"]];
        [options addObject:option];
        
        option = [OUIMenuController menuOptionWithFirstResponderSelector:@selector(showReleaseNotes:)
                                                                   title:NSLocalizedStringFromTableInBundle(@"Release Notes", @"OmniUIDocument", OMNI_BUNDLE, @"App menu item title")
                                                                   image:[UIImage imageNamed:@"OUIMenuItemReleaseNotes.png"]];
        [options addObject:option];
        
        option = [OUIMenuController menuOptionWithFirstResponderSelector:@selector(restoreSampleDocuments:)
                                                                   title:[[OUIDocumentAppController controller] sampleDocumentsDirectoryTitle]
                                                                   image:nil];
        [options addObject:option];
        
#if defined(DEBUG)
        BOOL includedTestsMenu = YES;
#else
        BOOL includedTestsMenu = [[NSUserDefaults standardUserDefaults] boolForKey:@"OUIIncludeTestsMenu"];
#endif
        if (includedTestsMenu && NSClassFromString(@"SenTestSuite")) {
            option = [OUIMenuController menuOptionWithFirstResponderSelector:@selector(runTests:)
                                                                       title:NSLocalizedStringFromTableInBundle(@"Run Tests", @"OmniUIDocument", OMNI_BUNDLE, @"App menu item title")
                                                                       image:[UIImage imageNamed:@"OUIMenuItemRunTests.png"]];
            [options addObject:option];
        }
        
        return options;
    }
    
    OBASSERT_NOT_REACHED("Unknown menu");
    return nil;
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

#pragma mark - UITextFieldDelegate

// <bug:///77415> (Reduce the amount of copy/pasted code for file renaming) See OUIDocumentRenameViewController for the other implementation of this similar-but-not-identical behavior.
 
- (BOOL)textFieldShouldBeginEditing:(UITextField *)textField;
{
    OBPRECONDITION(textField == _documentTitleTextField);
    OBPRECONDITION(_hasAttemptedRename == NO);
    
    OFSDocumentStoreFileItem *fileItem = _document.fileItem;
    OBASSERT(fileItem);
    
    textField.text = fileItem.editingName;
    return YES;
}

- (BOOL)textFieldShouldEndEditing:(UITextField *)textField;
{
    // If we are new, there will be no fileItem.
    // Actually, we give documents default names and load their fileItem up immediately on creation...
    OFSDocumentStoreFileItem *fileItem = _document.fileItem;
    NSString *originalName = fileItem.editingName;
    OBASSERT(originalName);
    
    NSString *newName = [textField text];
    if (_hasAttemptedRename || [NSString isEmptyString:newName] || [newName isEqualToString:originalName] || _document.editingDisabled) {
        _hasAttemptedRename = NO; // This rename finished (or we are going to discard it due to an incoming iCloud edit); prepare for the next one.
        textField.text = originalName;
        return YES;
    }
    
    // Otherwise, start the rename and return NO for now, but remember that we've tried already.
    _hasAttemptedRename = YES;
    NSURL *currentURL = [fileItem.fileURL copy];
    
    NSString *uti = OFUTIForFileExtensionPreferringNative([currentURL pathExtension], NO);
    OBASSERT(uti);
    
    // We don't want a "directory changed" notification for the local documents directory.
    OUIDocumentPicker *documentPicker = self.documentPicker;

    // Tell the document that the rename is local
    [_document _willBeRenamedLocally];
    [self updateDocumentTitle:newName]; // edit field will be dismissed and the title label displayed before the rename is completed so this will make sure that the label shows the updated name
    
    // Make sure we don't close the document while the rename is happening, or some such. It would probably be OK with the synchronization API, but there is no reason to allow it.
    [[UIApplication sharedApplication] beginIgnoringInteractionEvents];
    [documentPicker _beginIgnoringDocumentsDirectoryUpdates];
    
    [fileItem.scope renameFileItem:fileItem baseName:newName fileType:uti completionHandler:^(NSURL *destinationURL, NSError *error){
        
        [documentPicker _endIgnoringDocumentsDirectoryUpdates];
        [[UIApplication sharedApplication] endIgnoringInteractionEvents];
        
        if (!destinationURL) {
            NSLog(@"Error renaming document with URL \"%@\" to \"%@\" with type \"%@\": %@", [currentURL absoluteString], newName, uti, [error toPropertyList]);
            OUI_PRESENT_ERROR(error);
            
            [self updateDocumentTitle:originalName];
            
            if ([error hasUnderlyingErrorDomain:OFSErrorDomain code:OFSFilenameAlreadyInUse]) {
                // Leave the fixed name for the user to try again.
                _hasAttemptedRename = NO;
            } else {
                // Some other error which may not be correctable -- bail
                [_documentTitleTextField endEditing:YES];
            }
        } else {
            // Don't need to scroll the document picker in this copy of the code.
            //[documentPicker _didPerformRenameToFileURL:destinationURL];
            [_documentTitleTextField endEditing:YES];
        }
    }];
    
    return NO;
}

- (void)textFieldDidEndEditing:(UITextField *)textField;
{
    OBPRECONDITION(textField == _documentTitleTextField);
    
    [self _toggleTitleToolbarCustomView];
    [self _removeShieldView];
}

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string;
{
    OBPRECONDITION(textField == _documentTitleTextField);
    
    // <bug://bugs/61021>
    NSRange r = [string rangeOfString:@"/"];
    if (r.location != NSNotFound) {
        return NO;
    }
    
    return YES;
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField;
{
    OBPRECONDITION(textField == _documentTitleTextField);
    
    if (_documentTitleTextField.isEditing)
        [_documentTitleTextField endEditing:YES];
    
    return YES;
}

#pragma mark -
#pragma mark UIApplicationDelegate

- (void)_delayedFinishLaunchingAllowCopyingSampleDocuments:(BOOL)allowCopyingSampleDocuments
                                    openingDocumentWithURL:(NSURL *)launchDocumentURL
                           orOpeningWelcomeDocumentWithURL:(NSURL *)welcomeDocumentURL
                                         completionHandler:(void (^)(void))completionHandler;
{
    DEBUG_LAUNCH(@"Delayed finish launching allowCopyingSamples:%d openURL:%@ orWelcome:%@", allowCopyingSampleDocuments, launchDocumentURL, welcomeDocumentURL);
    
    OUIDocumentPicker *documentPicker = self.documentPicker;

    BOOL startedOpeningDocument = NO;
    OFSDocumentStoreFileItem *fileItemToSelect = nil;
    OFSDocumentStoreFileItem *launchFileItem = nil;
    
    if (launchDocumentURL) {
        launchFileItem = [_documentStore fileItemWithURL:launchDocumentURL];
        DEBUG_LAUNCH(@"  launchFileItem: %@", [launchFileItem shortDescription]);
    }
    
    completionHandler = [completionHandler copy];
    
    if (allowCopyingSampleDocuments && launchDocumentURL == nil && ![[NSUserDefaults standardUserDefaults] boolForKey:@"SampleDocumentsHaveBeenCopiedToUserDocuments"]) {
        // Copy in a welcome document if one exists and we haven't done so for first launch yet.
        [self copySampleDocumentsToUserDocumentsWithCompletionHandler:^(NSDictionary *nameToURL) {
            NSURL *welcomeURL = self.shouldOpenWelcomeDocumentOnFirstLaunch ? [nameToURL objectForKey:WelcomeDocumentName] : nil;
            
            [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"SampleDocumentsHaveBeenCopiedToUserDocuments"];
            
            [_documentStore scanItemsWithCompletionHandler:^{
                // Retry after the scan finished, but this time try opening the Welcome document
                [self _delayedFinishLaunchingAllowCopyingSampleDocuments:NO // we just did, don't try again
                                                  openingDocumentWithURL:nil // already checked this
                                         orOpeningWelcomeDocumentWithURL:welcomeURL
                                                       completionHandler:completionHandler];
            }];
        }];
        return;
    }
    
    if (!launchFileItem && welcomeDocumentURL) {
        launchFileItem = [_documentStore fileItemWithURL:welcomeDocumentURL];
        DEBUG_LAUNCH(@"  launchFileItem: %@", [launchFileItem shortDescription]);
    }

    if (launchFileItem != nil) {
        DEBUG_LAUNCH(@"Opening document %@", [launchFileItem shortDescription]);
        [self openDocument:launchFileItem animation:OUIDocumentAnimationTypeDissolve showActivityIndicator:YES];
        startedOpeningDocument = YES;
    } else {
        // Restore our selected or open document if we didn't get a command from on high.
        NSArray *launchAction = [self.launchAction copy];
        
        DEBUG_LAUNCH(@"  launchAction: %@", launchAction);
        if ([launchAction isKindOfClass:[NSArray class]] && [launchAction count] == 2) {
            // Clear the launch action in case we crash while opening this file; we'll restore it if the file opens successfully.
            self.launchAction = nil;

            launchFileItem = [_documentStore fileItemWithURL:[NSURL URLWithString:[launchAction objectAtIndex:1]]];
            if (launchFileItem) {
                [documentPicker scrollItemToVisible:launchFileItem animated:NO];
                NSString *action = [launchAction objectAtIndex:0];
                if ([action isEqualToString:OpenAction]) {
                    DEBUG_LAUNCH(@"Opening file item %@", [launchFileItem shortDescription]);
                    [self openDocument:launchFileItem animation:OUIDocumentAnimationTypeDissolve showActivityIndicator:YES];
                    startedOpeningDocument = YES;
                } else
                    fileItemToSelect = launchFileItem;
            }
        }
        if(allowCopyingSampleDocuments && ![[NSUserDefaults standardUserDefaults] boolForKey:@"SampleDocumentsHaveBeenCopiedToUserDocuments"]) {
            // The user is opening an inbox document. Copy the sample docs and pretend like we're already opening it
            [self copySampleDocumentsToUserDocumentsWithCompletionHandler:nil];
            startedOpeningDocument = YES;
        }
    }
    
    // Iff we didn't open a document, go to the document picker. We don't want to start loading of previews if the user is going directly to a document (particularly the welcome document).
    if (!startedOpeningDocument) {
        [self _fadeInDocumentPickerScrollingToFileItem:fileItemToSelect];
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

#define DEBUG_TOOLBAR_AVAILABLE_WIDTH 0

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

- (void)updateDocumentTitle:(NSString *)newTitle;
{
    if (newTitle == nil)
        newTitle = _document.fileItem.name;

    _documentTitleTextField.text = newTitle;
    // Had to add a space after the title to make padding between the title and the image. I tried using UIEdgeInsets on the image, title and content but could not get it to work horizontally. I did, however, get it to work to vertically align the image.
    [_documentTitleButton setTitle:[newTitle stringByAppendingString:@" "] forState:UIControlStateNormal];
    UIToolbar *toolbar = (UIToolbar *)[_documentTitleButton superview];
    if (toolbar == nil)
        return;

    CGFloat availableWidth = [self _availableWidthForResizingToolbarItems:@[_documentTitleToolbarItem] inToolbar:toolbar];
    CGSize buttonSize = [_documentTitleButton sizeThatFits:CGSizeMake(availableWidth, _documentTitleButton.bounds.size.height)];
    if (buttonSize.width > availableWidth)
        buttonSize.width = availableWidth;

    CGRect currentFrame = _documentTitleButton.frame;
    _documentTitleButton.frame = (CGRect){.origin = currentFrame.origin, .size = buttonSize};
    _documentTitleToolbarItem.width = 0.0f;
    [_documentTitleButton layoutIfNeeded];
    [toolbar layoutIfNeeded];
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions;
{
    DEBUG_LAUNCH(@"Did launch with options %@", launchOptions);
    
    _mainViewController.resizesToAvoidKeyboard = YES;
    
    _mainViewController.view.frame = _window.screen.applicationFrame;
    _window.rootViewController = _mainViewController;
    [_window makeKeyAndVisible];
    
    // Setup Document Title Bar Item Stuffs

    OBASSERT(_documentTitleButton == nil);

    _documentTitleButton = [OUIToolbarTitleButton buttonWithType:UIButtonTypeCustom];
    _documentTitleButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin|UIViewAutoresizingFlexibleRightMargin;

#if 0
    UIImage *disclosureImage = [UIImage imageNamed:@"OUIToolbarTitleDisclosureButton.png"];
    OBASSERT(disclosureImage != nil);
    [_documentTitleButton setImage:disclosureImage forState:UIControlStateNormal];
    _documentTitleButton.imageEdgeInsets = (UIEdgeInsets){.top = 4}; // Push the button down a bit to line up with the x height
#endif

    _documentTitleButton.titleLabel.font = [UIFont boldSystemFontOfSize:20.0];

    _documentTitleButton.adjustsImageWhenHighlighted = NO;
    _documentTitleButton.accessibilityHint = NSLocalizedStringFromTableInBundle(@"Triple tap to rename document.", @"OmniUIDocument", OMNI_BUNDLE, @"Document title label item accessibility hint.");

    UITapGestureRecognizer *doubleTapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(_handleTitleDoubleTapGesture:)];
    doubleTapRecognizer.numberOfTapsRequired = 2;
    [_documentTitleButton addGestureRecognizer:doubleTapRecognizer];
    
    [self updateDocumentTitle:@""];

    _documentTitleToolbarItem = [[UIBarButtonItem alloc] initWithCustomView:_documentTitleButton];

    _documentTitleTextField = [[UITextField alloc] initWithFrame:CGRectMake(0.0f, 0.0f, 200.0f, 31.0f)];
    _documentTitleTextField.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _documentTitleTextField.font = [UIFont fontWithName:@"Helvetica-Bold" size:20.0];
    _documentTitleTextField.textAlignment = NSTextAlignmentCenter;
    _documentTitleTextField.adjustsFontSizeToFitWidth = YES;
    _documentTitleTextField.minimumFontSize = 17.0;
    _documentTitleTextField.autocapitalizationType = UITextAutocapitalizationTypeWords;
    _documentTitleTextField.borderStyle = UITextBorderStyleBezel;
    _documentTitleTextField.backgroundColor = [UIColor whiteColor];
    _documentTitleTextField.textColor = [UIColor blackColor];
    _documentTitleTextField.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
    _documentTitleTextField.delegate = self;
    _documentTitleTextField.clearButtonMode = UITextFieldViewModeWhileEditing;
    
    // Add a placeholder view controller until we finish scanning
    OUILaunchViewController *launchViewController = [[OUILaunchViewController alloc] init];
    [_mainViewController setInnerViewController:launchViewController animated:NO fromView:nil toView:nil];
    
    // Pump the runloop once so that the -viewDidAppear: messages get sent before we muck with the view containment again. Otherwise, we never get -viewDidAppear: on the root view controller, and thus the OUILaunchViewController, causing assertions.
    OUIDisplayNeededViews();
    OBASSERT(launchViewController.visibility == OUIViewControllerVisibilityVisible);
    
    NSURL *launchOptionsURL = [launchOptions objectForKey:UIApplicationLaunchOptionsURLKey];
    
    void (^moarFinishing)(void) = ^(void){
        DEBUG_LAUNCH(@"Creating document store");
        
        OUIActivityIndicator *activityIndicator = [OUIActivityIndicator showActivityIndicatorInView:_mainViewController.view];
        
        // Start out w/o syncing so that our initial setup will just find local documents. This is crufty, but it avoids hangs in syncing when we aren't able to reach the server.
        _syncAgent = [[OFXAgent alloc] init];
        _syncAgent.syncingEnabled = NO;
        [_syncAgent applicationLaunched];
        
        _agentActivity = [[OFXAgentActivity alloc] initWithAgent:_syncAgent];
        
        // Wait for scopes to get their document URL set up.
        [_syncAgent afterAsynchronousOperationsFinish:^{
            _documentStore = [[OFSDocumentStore alloc] initWithDelegate:self];

            // See commentary by -_updateDocumentStoreScopes for why we observe the sync agent instead of the account registry
            [_syncAgent addObserver:self forKeyPath:OFValidateKeyPath(_syncAgent, runningAccounts) options:0 context:&SyncAgentRunningAccountsContext];
            [self _updateDocumentStoreScopes];
            
            _localScope = [[OFSDocumentStoreLocalDirectoryScope alloc] initWithDirectoryURL:[OFSDocumentStoreLocalDirectoryScope userDocumentsDirectoryURL] isTrash:NO documentStore:_documentStore];
            [_documentStore addScope:_localScope];
            OFSDocumentStoreScope *trashScope = [[OFSDocumentStoreLocalDirectoryScope alloc] initWithDirectoryURL:[OFSDocumentStoreLocalDirectoryScope trashDirectoryURL] isTrash:YES documentStore:_documentStore];
            [_documentStore addScope:trashScope];

            [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_fileItemContentsChangedNotification:) name:OFSDocumentStoreFileItemContentsChangedNotification object:_documentStore];
            [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_fileItemFinishedDownloadingNotification:) name:OFSDocumentStoreFileItemFinishedDownloadingNotification object:_documentStore];
            
            __weak OUIDocumentAppController *weakSelf = self;

            // We have to wait for the document store to get results from its scopes
            [_documentStore addAfterInitialDocumentScanAction:^{
                DEBUG_LAUNCH(@"Initial scan finished");
                
                OUIDocumentAppController *strongSelf = weakSelf;
                OBASSERT(strongSelf);
                if (!strongSelf)
                    return;

                OUIDocumentPicker *documentPicker = strongSelf.documentPicker;
                documentPicker.documentStore = strongSelf->_documentStore;
                
                [strongSelf _delayedFinishLaunchingAllowCopyingSampleDocuments:YES
                                                        openingDocumentWithURL:launchOptionsURL
                                               orOpeningWelcomeDocumentWithURL:nil // Don't always try to open the welcome document; just if we copy samples
                                                             completionHandler:^{
                                                                 
                                                                 // Don't start generating previews until we have decided whether to open a document at launch time (which will prevent preview generation until it is closed).
                                                                 strongSelf->_previewGenerator = [[OUIDocumentPreviewGenerator alloc] init];
                                                                 strongSelf->_previewGenerator.delegate = strongSelf;
                                                                 
                                                                 
                                                                 // Cache population should have already started, but we should wait for it before queuing up previews.
                                                                 [OUIDocumentPreview afterAsynchronousPreviewOperation:^{
                                                                     [strongSelf->_previewGenerator enqueuePreviewUpdateForFileItemsMissingPreviews:strongSelf->_documentStore.mergedFileItems];
                                                                 }];
                                                                 
                                                                 [activityIndicator hide];
                                                       }];
            }];

        
            // Go ahead and start syncing now.
            _syncAgent.syncingEnabled = YES;
        }];
        
        _didFinishLaunching = YES;
        
        // Start real preview generation any time we are missing one.
        [[NSNotificationCenter defaultCenter] addObserverForName:OUIDocumentPickerItemViewPreviewsDidLoadNotification object:nil queue:nil usingBlock:^(NSNotification *note){
            OUIDocumentPickerItemView *itemView = [note object];
            for (OUIDocumentPreview *preview in itemView.loadedPreviews) {
                // Only do the update if we have a placeholder (no preview on disk). If we have a "empty" preview (meaning there was an error), don't redo the error-provoking work.
                if (preview.type == OUIDocumentPreviewTypePlaceholder) {
                    OFSDocumentStoreFileItem *fileItem = [_documentStore fileItemWithURL:preview.fileURL];
                    OBASSERT(fileItem);
                    if (fileItem)
                        [_previewGenerator fileItemNeedsPreviewUpdate:fileItem];
                }
            }
        }];
    };

#if 0 && defined(DEBUG_bungi)
    {
        OFXServerAccountRegistry *registry = [OFXServerAccountRegistry defaultAccountRegistry];
        if ([registry.allAccounts count] == 0) {
            OFXServerAccountType *type = [OFXServerAccountType accountTypeWithIdentifier:OFXWebDAVServerAccountTypeIdentifier];
            // Currently has to end in "Documents" for OFSDocumentStoreScopeCacheKeyForURL(). Can't be directly in $HOME since that'll hit a sandbox violation.
            NSURL *documentsDirectory = [NSURL fileURLWithPath:[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/OmniPresence/Documents"] isDirectory:YES];
            OFXServerAccount *account = [[OFXServerAccount alloc] initWithType:type
                                                                 remoteBaseURL:[NSURL URLWithString:@"https://crispy.local:8001/test/"]
                                                             localDocumentsURL:documentsDirectory];
            [type validateAccount:account username:@"test" password:@"password" validationHandler:^(NSError *errorOrNil) {
                if (errorOrNil)
                    NSLog(@"Error validating account: %@", [errorOrNil toPropertyList]);
                else {
                    NSError *error = nil;
                    if (![registry addAccount:account error:&error])
                        NSLog(@"Error adding account: %@", [error toPropertyList]);
                }
                
                moarFinishing();
            }];
        } else
             moarFinishing();
    }
#else
    {
        OFXServerAccountRegistry *registry = [OFXServerAccountRegistry defaultAccountRegistry];
        if ([registry.allAccounts count] == 0) {
            [self _importLegacyAccounts];
        }
        moarFinishing();
    }
#endif

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
    if (OFSInInInbox(url)) {
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

    setup.finished = ^(OUIServerAccountSetupViewController *vc, NSError *errorOrNil) {
        OFXServerAccount *account = errorOrNil ? nil : vc.account;
        OBASSERT(account == nil || account.isCloudSyncEnabled ? [[[OFXServerAccountRegistry defaultAccountRegistry] validCloudSyncAccounts] containsObject:account] : [[[OFXServerAccountRegistry defaultAccountRegistry] validImportExportAccounts] containsObject:account]);
        [[OUIDocumentAppController controller] _didAddSyncAccount:account];
    };
    
    UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:setup];
    navigationController.modalPresentationStyle = UIModalPresentationFormSheet;
    navigationController.modalTransitionStyle = UIModalTransitionStyleCoverVertical;
    [self.topViewController presentViewController:navigationController animated:YES completion:nil];

    return YES;
}

- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url sourceApplication:(NSString *)sourceApplication annotation:(id)annotation;
{
    if (!_didFinishLaunching)  // if the app is launched by an open request from another app, then this is called and then application:didFinishLaunchingWithOptions: is called
        return YES;            // and application:didFinishLaunchingWithOptions: handles opening the doc
    
    if ([self isSpecialURL:url]) {
        return [self handleSpecialURL:url];
    }
    
    if ([url isFileURL] && OFISEQUAL([[url path] pathExtension], @"omnipresence-config")) {
        return [self _loadOmniPresenceConfigFileFromURL:url];
    }

    [self.documentPicker _applicationWillOpenDocument];
    _isOpeningURL = YES;

    // Have to wait for the docuemnt store to awake again (if we were backgrounded), initiated by -applicationWillEnterForeground:. <bug:///79297> (Bad animation closing file opened from another app)
    
    __weak OUIDocumentAppController *weakSelf = self;
    
    
    void (^handleInbox)(void) = ^(void){
        OBASSERT(_documentStore);
        [_documentStore addAfterInitialDocumentScanAction:^{
            OUIDocumentAppController *strongSelf = weakSelf;
            OBASSERT(strongSelf);
            if (!strongSelf)
                return;
            
            if (OFSInInInbox(url)) {
                OFSDocumentStoreScope *scope = strongSelf.documentPicker.selectedScope; // Ooof, that's a deep dive.
                
                [OUIDocumentInbox cloneInboxItem:url toScope:scope completionHandler:^(OFSDocumentStoreFileItem *newFileItem, NSError *errorOrNil) {
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
                        
                        // Depending on the sort type, the item mive be in view or not. Don't bother scrolling to it if not.
                        OUIDocumentAnimationType animation = [strongSelf.documentPicker.activeScrollView fileItemViewForFileItem:newFileItem] ? OUIDocumentAnimationTypeZoom : OUIDocumentAnimationTypeDissolve;
                        
                        [strongSelf openDocument:newFileItem animation:animation showActivityIndicator:YES];
                    });
                }];
            } else {
                OBASSERT_NOT_REACHED("Will the system ever give us a non-inbox item?");
                OFSDocumentStoreFileItem *fileItem = [strongSelf->_documentStore fileItemWithURL:url];
                OBASSERT(fileItem);
                if (fileItem)
                    [strongSelf openDocument:fileItem animation:OUIDocumentAnimationTypeDissolve showActivityIndicator:YES];
            }
        }];
    };
    
    
    if (_documentStore) {
        handleInbox();
    }
    else {
        OBASSERT(_syncAgent);
        [_syncAgent afterAsynchronousOperationsFinish:handleInbox];
    }
    
    
    
    return YES;
}

- (void)_setLaunchActionFromCurrentState;
{
    if (_document)
        self.launchAction = [NSArray arrayWithObjects:OpenAction, [_document.fileURL absoluteString], nil];
    else
        self.launchAction = nil;
}

- (void)_finishedEnteringForeground;
{
    if (_wasInBackground) {        
        [_documentStore applicationWillEnterForegroundWithCompletionHandler:^{
            // Make sure we find the existing previews before we check if there are documents that need previews updated
                [OUIDocumentPreview populateCacheForFileItems:_documentStore.mergedFileItems completionHandler:^{
                [_previewGenerator enqueuePreviewUpdateForFileItemsMissingPreviews:_documentStore.mergedFileItems];
            }];
        }];
        _wasInBackground = NO;
    }
}

- (void)applicationWillEnterForeground:(UIApplication *)application;
{
    [_syncAgent applicationWillEnterForeground];
        
    [self _finishedEnteringForeground];
}

- (void)applicationDidEnterBackground:(UIApplication *)application;
{
    if (_didFinishLaunching) { // Might get backgrounded while the "move docs to iCloud" prompt is still up.
        // We do NOT save the document here. UIDocument subscribes to application lifecycle notifications and will provoke a save on itself.
        [self _setLaunchActionFromCurrentState];
        
        [_syncAgent applicationDidEnterBackground];
    }
    
    if (_documentStore) {
        OBASSERT(_wasInBackground == NO);
        _wasInBackground = YES;
        [_documentStore applicationDidEnterBackground];
    }

    [_previewGenerator applicationDidEnterBackground];
    
    // Clean up unused previews
    [OUIDocumentPreview deletePreviewsNotUsedByFileItems:_documentStore.mergedFileItems];
    [OUIDocumentPreview flushPreviewImageCache];
    
    // Clean up any document's view state that no longer applies
    NSMutableArray *mergedFileItemEditStateIdentifiers = [NSMutableArray array];
    for (OFSDocumentStoreFileItem *fileItem in _documentStore.mergedFileItems)
        [mergedFileItemEditStateIdentifiers addObject:_normalizedDocumentStateIdentifierFromURL(fileItem.fileURL)];
    
    NSDictionary *allDocsViewState = [[NSUserDefaults standardUserDefaults] dictionaryForKey:OUIDocumentViewStates];
    NSMutableDictionary *docStatesToKeep = [NSMutableDictionary dictionary];
    [allDocsViewState enumerateKeysAndObjectsUsingBlock:^(NSString *docStateIdentifier, NSDictionary *docState, BOOL *stop) {
        if ([mergedFileItemEditStateIdentifiers containsObject:docStateIdentifier])
            [docStatesToKeep setObject:docState forKey:docStateIdentifier];
    }];
    [[NSUserDefaults standardUserDefaults] setObject:docStatesToKeep forKey:OUIDocumentViewStates];

    [super applicationDidEnterBackground:application];
}

- (void)applicationWillTerminate:(UIApplication *)application;
{
    [self _setLaunchActionFromCurrentState];
    
    [_syncAgent applicationWillTerminateWithCompletionHandler:nil];
    
    [super applicationWillTerminate:application];
}

- (void)applicationDidReceiveMemoryWarning:(UIApplication *)application;
{
    [super applicationDidReceiveMemoryWarning:application];
    
    [OUIDocumentPreview discardHiddenPreviews];
}

#pragma mark - OFSDocumentStoreDelegate

- (void)documentStore:(OFSDocumentStore *)store addedFileItems:(NSSet *)addedFileItems;
{
    // Register previews as files appear and start preview generation for them. _previewGenerator might still be nil if we are starting up, but we still want to register the previews.
    [OUIDocumentPreview populateCacheForFileItems:addedFileItems completionHandler:^{
        [_previewGenerator enqueuePreviewUpdateForFileItemsMissingPreviews:addedFileItems];
    }];
}

- (void)documentStore:(OFSDocumentStore *)store fileWithURL:(NSURL *)oldURL andDate:(NSDate *)date didMoveToURL:(NSURL *)newURL;
{
    [OUIDocumentPreview updateCacheAfterFileURL:oldURL withDate:date didMoveToURL:newURL];
    
    // Update document view state
    [[self class] moveDocumentStateFromURL:oldURL toURL:newURL deleteOriginal:YES];
}

- (void)documentStore:(OFSDocumentStore *)store fileWithURL:(NSURL *)oldURL andDate:(NSDate *)oldDate didCopyToURL:(NSURL *)newURL andDate:(NSDate *)newDate;
{
    // Update document view state
    [[self class] moveDocumentStateFromURL:oldURL toURL:newURL deleteOriginal:NO];
    
    // If we have valid previews for the old document, copy them to the new. We might not have previews if the old file is a sample document being restored, for example.
    Class cls = [self documentClassForURL:oldURL];
    
    OUIDocumentPreview *landscapePreview = [OUIDocumentPreview makePreviewForDocumentClass:cls fileURL:oldURL date:oldDate withLandscape:YES];
    if (landscapePreview.type != OUIDocumentPreviewTypeRegular)
        return;
    
    OUIDocumentPreview *portraitPreview = [OUIDocumentPreview makePreviewForDocumentClass:cls fileURL:oldURL date:oldDate withLandscape:NO];
    if (portraitPreview.type != OUIDocumentPreviewTypeRegular)
        return;

    [OUIDocumentPreview cachePreviewImagesForFileURL:newURL date:newDate byDuplicatingFromFileURL:oldURL date:oldDate];
}

- (OFSDocumentStoreFileItem *)documentStore:(OFSDocumentStore *)store preferredFileItemForNextAutomaticDownload:(NSSet *)fileItems;
{
    return [self.documentPicker _preferredVisibleItemFromSet:fileItems];
}

#pragma mark - OUIDocumentPickerDelegate

- (void)documentPicker:(OUIDocumentPicker *)picker openTappedFileItem:(OFSDocumentStoreFileItem *)fileItem;
{
    OBPRECONDITION(fileItem);
    
    // If we crash in trying to open this document, we should stay in the file picker the next time we launch rather than trying to open it over and over again
    self.launchAction = nil;
    
    if (![_previewGenerator shouldOpenDocumentWithFileItem:fileItem])
        return;
    
    [self openDocument:fileItem animation:OUIDocumentAnimationTypeZoom showActivityIndicator:YES];
}

- (void)documentPicker:(OUIDocumentPicker *)picker openCreatedFileItem:(OFSDocumentStoreFileItem *)fileItem;
{
    OBPRECONDITION(fileItem);
    
    // If we crash in trying to open this document, we should stay in the file picker the next time we launch rather than trying to open it over and over again
    self.launchAction = nil;
    
    // We could also remember the animation type if we want to defer this until after this preview is done generating.
#if 0
    if (![_previewGenerator shouldOpenDocumentWithFileItem:fileItem])
        return;
#endif
    
    [self openDocument:fileItem animation:OUIDocumentAnimationTypeDissolve showActivityIndicator:NO];
}

#pragma mark - OUIDocumentPreviewGeneratorDelegate delegate

- (BOOL)previewGenerator:(OUIDocumentPreviewGenerator *)previewGenerator isFileItemCurrentlyOpen:(OFSDocumentStoreFileItem *)fileItem;
{
    OBPRECONDITION(fileItem);
    return OFISEQUAL(_document.fileURL, fileItem.fileURL);
}

- (BOOL)previewGeneratorHasOpenDocument:(OUIDocumentPreviewGenerator *)previewGenerator;
{
    OBPRECONDITION(_didFinishLaunching); // Don't start generating previews before the app decides whether to open a launch document
    return _isOpeningURL || _document != nil;
}

- (void)previewGenerator:(OUIDocumentPreviewGenerator *)previewGenerator performDelayedOpenOfFileItem:(OFSDocumentStoreFileItem *)fileItem;
{
    [self documentPicker:nil openTappedFileItem:fileItem];
}

- (OFSDocumentStoreFileItem *)previewGenerator:(OUIDocumentPreviewGenerator *)previewGenerator preferredFileItemForNextPreviewUpdate:(NSSet *)fileItems;
{
    return [self.documentPicker _preferredVisibleItemFromSet:fileItems];
}

- (Class)previewGenerator:(OUIDocumentPreviewGenerator *)previewGenerator documentClassForFileURL:(NSURL *)fileURL;
{
    return [self documentClassForURL:fileURL];
}

#pragma mark -
#pragma mark OUIUndoBarButtonItemTarget

- (void)undo:(id)sender;
{
    [_document undo:sender];
}

- (void)redo:(id)sender;
{
    [_document redo:sender];
}

- (BOOL)canPerformAction:(SEL)action withSender:(id)sender;
{
    if (action == @selector(undo:))
        return [_document.undoManager canUndo];
    else if (action == @selector(redo:))
        return [_document.undoManager canRedo];
        
    return YES;
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
    DEBUG_LAUNCH(@"Launch action is %@", action);
    return action;
}

- (void)setLaunchAction:(NSArray *)launchAction;
{
    DEBUG_LAUNCH(@"Setting launch action %@", launchAction);
    [[NSUserDefaults standardUserDefaults] setObject:launchAction forKey:OUINextLaunchActionDefaultsKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)_updateDocumentStoreScopes;
{
    OBPRECONDITION(_syncAgent);
    OBPRECONDITION(_documentStore);

    NSMutableDictionary *previousAccountUUIDToScope = [NSMutableDictionary new];
    for (OFSDocumentStoreScope *candidate in _documentStore.scopes) {
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
        
        if ([_documentStore.scopes indexOfObjectIdenticalTo:_documentPicker.selectedScope] == NSNotFound) {
            OBFinishPortingLater("Should pick a scope that makes sense -- maybe any scope that has documents?");
            _documentPicker.selectedScope = _documentStore.defaultUsableScope;
        }
    }
}

- (void)_fadeInDocumentPickerScrollingToFileItem:(OFSDocumentStoreFileItem *)fileItem;
{
    DEBUG_LAUNCH(@"Showing picker, showing item %@", [fileItem shortDescription]);
    
    OUIDocumentPicker *documentPicker = self.documentPicker;
    
    [OUIDocumentPreview populateCacheForFileItems:_documentStore.mergedFileItems completionHandler:^{
        [UIView transitionWithView:_mainViewController.view duration:0.25
                           options:UIViewAnimationOptionTransitionCrossDissolve
                        animations:^{
                            OUIWithoutAnimating(^{ // some animations get added anyway if we specify NO ... avoid a weird jump from the start to end frame
                                [_mainViewController setInnerViewController:documentPicker animated:NO fromView:nil toView:nil];
                                
                                if (!fileItem)
                                    [documentPicker scrollToTopAnimated:NO];
                                else
                                    [documentPicker scrollItemToVisible:fileItem animated:NO];
                            });
                            [_mainViewController.view layoutIfNeeded];
                        }
                        completion:^(BOOL finished){
                            // Make sure we have previews for all the file items that don't have one. Files may have been added/updated while we were not running.
                            [_previewGenerator enqueuePreviewUpdateForFileItemsMissingPreviews:_documentStore.mergedFileItems];
                        }];
    }];
}

- (void)_mainThread_finishedLoadingDocument:(OUIDocument *)document animation:(OUIDocumentAnimationType)animation activityIndicator:(OUIActivityIndicator *)activityIndicator completionHandler:(void (^)(void))completionHandler;
{
    OBASSERT([NSThread isMainThread]);
    [self _setDocument:document];
    _isOpeningURL = NO;
        
    [self updateDocumentTitle:nil];
    
    UIViewController <OUIDocumentViewController> *viewController = _document.viewController;
    [viewController view]; // make sure the view is loaded in case -pickerAnimationViewForTarget: doesn't and return a subview thereof.
    OBASSERT(![document hasUnsavedChanges]); // We just loaded our document and created our view, we shouldn't have any view state that needs to be saved. If we do, we should probably investigate to prevent bugs like <bug:///80514> ("Document Updated" on (null) alert is still hanging around), perhaps discarding view state changes if we can't prevent them.

    [self mainThreadFinishedLoadingDocument:document];
    
    
    // Start automatically tracking undo state from this document's undo manager
    [self undoBarButtonItem].undoManager = _document.undoManager;
    
    // Might be a newly created document that was never edited and trivially returns YES to saving. Make sure there is an item before overwriting our last default value.
    NSURL *url = _document.fileURL;
    OFSDocumentStoreFileItem *fileItem = [_documentStore fileItemWithURL:url];
    if (fileItem) {
        self.launchAction = [NSArray arrayWithObjects:OpenAction, [url absoluteString], nil];
    }
    
    // Wait until the document is opened to do this, which will let cache entries from opening document A be used in document B w/o being flushed.
    [OAFontDescriptor forgetUnusedInstances];
    
    // UIWindow will automatically create an undo manager if one isn't found along the responder chain. We want to be darn sure that don't end up getting two undo managers and accidentally splitting our registrations between them.
    OBASSERT([_document undoManager] == [_document.viewController undoManager]);
    OBASSERT([_document undoManager] == [_document.viewController.view undoManager]); // Does your view controller implement -undoManager? We don't do this for you right now.

    // Capture scope for the animation...
    completionHandler = [completionHandler copy];
    
    if ([viewController respondsToSelector:@selector(restoreDocumentViewState:)])
        [viewController restoreDocumentViewState:[OUIDocumentAppController documentStateForURL:fileItem.fileURL]];
    
    switch (animation) {
        case OUIDocumentAnimationTypeZoom: {
            OUIDocumentPickerFileItemView *fileItemView = [self.documentPicker.activeScrollView fileItemViewForFileItem:_document.fileItem];
            OBASSERT(fileItemView);
            OB_UNUSED_VALUE(fileItemView); // http://llvm.org/bugs/show_bug.cgi?id=11576 Use in block doesn't count as use to prevent dead store warning
            UIView *documentView = [self pickerAnimationViewForTarget:_document];
            [_mainViewController setInnerViewController:viewController animated:YES
                                             fromRegion:^UIView *(CGRect *outRect){
                                                 OUIDocumentPreviewView *previewView = fileItemView.previewView;
                                                 *outRect = previewView.imageBounds;
                                                 return previewView;
                                             } toRegion:^UIView *(CGRect *outRect){
                                                 *outRect = CGRectZero;
                                                 return documentView;
                                             } transitionAction:nil
                                       completionAction:^{
                                           if ([viewController respondsToSelector:@selector(documentFinishedOpening)])
                                               [viewController documentFinishedOpening];
                                           if (completionHandler)
                                               completionHandler();
                                       }];

            [activityIndicator hide]; // will be on the item preview view for a document tap initiated load
            break;
        }
        case OUIDocumentAnimationTypeDissolve: {
            OUIMainViewController *mainViewController = _mainViewController;
            [UIView transitionWithView:mainViewController.view duration:0.25
                               options:UIViewAnimationOptionTransitionCrossDissolve
                            animations:^{
                                OUIWithoutAnimating(^{ // some animations get added anyway if we specify NO ... avoid a weird jump from the start to end frame
                                    [mainViewController setInnerViewController:viewController animated:NO fromView:nil toView:nil];
                                });
                                [mainViewController.view layoutIfNeeded];
                            }
                            completion:^(BOOL finished){
                                if ([viewController respondsToSelector:@selector(documentFinishedOpening)])
                                    [viewController documentFinishedOpening];
                                if (completionHandler)
                                    completionHandler();
                                
                                [activityIndicator hide];
                            }];
            break;
        }
        default:
            // this shouldn't happen, but JUST IN CASE...
            OBASSERT_NOT_REACHED("Should've specificed a valid OUIDocumentAnimationType");
            if (completionHandler)
                completionHandler();
    } 
}

- (void)_setDocument:(OUIDocument *)document;
{
    if (_document == document)
        return;
    
    if (_document) {
        [[NSNotificationCenter defaultCenter] removeObserver:self name:UIDocumentStateChangedNotification object:_document];
        [_document willClose];
    }
    
    _document = document;
    
    if (_document) {        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_documentStateChanged:) name:UIDocumentStateChangedNotification object:_document];
    }
}

// Called from the main app menu
- (void)_setupCloud:(id)sender;
{
    OUICloudSetupViewController *setup = [[OUICloudSetupViewController alloc] init];
    [_mainViewController presentViewController:setup animated:YES completion:nil];
}

- (void)_didAddSyncAccount:(OFXServerAccount *)account;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    [_mainViewController dismissViewControllerAnimated:YES completion:nil];
    
    if (account != nil && account.isCloudSyncEnabled) {
        // Wait for the agent to start up. Ugly, but less so than adding an ivar and having -_updateDocumentStoreScopes clear/unlock interaction...
        // This might be marginally less terrible if we had a 'block interaction until foo' object we could create and run.
        
        [[UIApplication sharedApplication] beginIgnoringInteractionEvents];
        [self _selectScopeWithAccount:account completionHandler:^{
            [[UIApplication sharedApplication] endIgnoringInteractionEvents];
        }];
    }
}

- (void)_selectScopeWithAccount:(OFXServerAccount *)account completionHandler:(void (^)(void))completionHandler;
{
    OBPRECONDITION([NSThread isMainThread]);

    completionHandler = [completionHandler copy];
    
    for (OFSDocumentStoreScope *candidate in _documentStore.scopes) {
        if (![candidate isKindOfClass:[OFXDocumentStoreScope class]])
            continue; // Skip the local scope
        
        OFXDocumentStoreScope *scope = (OFXDocumentStoreScope *)candidate;
        if (scope.account == account) {
            _documentPicker.selectedScope = scope;
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

    OFSDocumentStoreFileItem *fileItem = [[note userInfo] objectForKey:OFSDocumentStoreFileItemInfoKey];
    OBASSERT([fileItem isKindOfClass:[OFSDocumentStoreFileItem class]]);

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

- (void)_handleTitleDoubleTapGesture:(UIGestureRecognizer*)gestureRecognizer;
{
    OBASSERT(gestureRecognizer.view == _documentTitleButton);

    [self _toggleTitleToolbarCustomView];

    if (![_documentTitleTextField becomeFirstResponder]) {
        [self _toggleTitleToolbarCustomView];
        return;
    }
    
    UITapGestureRecognizer *shieldViewTapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(_shieldViewTapped:)];        
    NSArray *passthroughViews = [NSArray arrayWithObject:_documentTitleTextField];
    _shieldView = [OUIShieldView shieldViewWithView:_window];
    [_shieldView addGestureRecognizer:shieldViewTapRecognizer];
    _shieldView.passthroughViews = passthroughViews;
    [_window addSubview:_shieldView];
}

- (void)_toggleTitleToolbarCustomView;
{
    if ([_documentTitleTextField superview] == nil) {
        UIView *superview = [_documentTitleToolbarItem.customView superview];
        _documentTitleTextField.frame = CGRectInset(superview.bounds, 3.0f, 3.0f);
        [superview addSubview:_documentTitleTextField];
    } else {
        [_documentTitleTextField removeFromSuperview];
        [self updateDocumentTitle:nil];
    }
}

- (void)_shieldViewTapped:(UIGestureRecognizer *)gestureRecognizer;
{
    if (gestureRecognizer.state == UIGestureRecognizerStateEnded) {
        [self _removeShieldView];
        [_documentTitleTextField endEditing:YES];
    }
}

- (void)_removeShieldView;
{
    if (_shieldView) {
        [_shieldView removeFromSuperview];
        _shieldView = nil;
    }
}

@end
