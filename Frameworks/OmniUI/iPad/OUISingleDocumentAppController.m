// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUISingleDocumentAppController.h>

#import <MobileCoreServices/MobileCoreServices.h>
#import <OmniAppKit/OAFontDescriptor.h>
#import <OmniBase/OmniBase.h>
#import <OmniFileStore/OFSDocumentStore.h>
#import <OmniFileStore/OFSDocumentStoreFileItem.h>
#import <OmniFileStore/OFSFileInfo.h>
#import <OmniFileStore/OFSFileManager.h>
#import <OmniFoundation/NSFileManager-OFSimpleExtensions.h>
#import <OmniFoundation/OFUTI.h>
#import <OmniUI/OUIBarButtonItem.h>
#import <OmniUI/OUIDocument.h>
#import <OmniUI/OUIDocumentPicker.h>
#import <OmniUI/OUIDocumentPickerFileItemView.h>
#import <OmniUI/OUIDocumentPreview.h>
#import <OmniUI/OUIDocumentPreviewView.h>
#import <OmniUI/OUIDocumentViewController.h>
#import <OmniUI/OUIInspector.h>
#import <OmniUI/OUIMainViewController.h>
#import <OmniUI/OUIShieldView.h>
#import <OmniUI/UIBarButtonItem-OUITheming.h>
#import <OmniUI/UIView-OUIExtensions.h>

#import "OUIDocumentConflictResolutionViewController.h"
#import "OUIDocument-Internal.h"
#import "OUIDocumentPicker-Internal.h"
#import "OUIDocumentPickerItemView-Internal.h"
#import "OUILaunchViewController.h"
#import "OUIMainViewController-Internal.h"
#import "OUIDocumentStoreSetupViewController.h"

RCS_ID("$Id$");

static NSString * const OpenAction = @"open";

typedef enum {
    OpenDocumentAnimationZoom,
    OpenDocumentAnimationDissolve,
} OpenDocumentAnimation;

#if 0 && defined(DEBUG)
    #define DEBUG_LAUNCH(format, ...) NSLog(@"LAUNCH: " format, ## __VA_ARGS__)
#else
    #define DEBUG_LAUNCH(format, ...) do {} while (0)
#endif

typedef enum {
    DocumentCopyBehaviorNone,
    DocumentCopyBehaviorMoveLocalToCloud,
    // DocumentCopyBehaviorCopyCloudToLocal -- if we add support for this when re-enabling iCloud
} DocumentCopyBehavior;

@interface OUISingleDocumentAppController (/*Private*/) <OUIDocumentConflictResolutionViewControllerDelegate>

@property(nonatomic,copy) NSArray *launchAction;

- (void)_delayedFinishLaunchingAllowCopyingSampleDocuments:(BOOL)allowCopyingSampleDocuments
                                    openingDocumentWithURL:(NSURL *)launchDocumentURL
                                  orOpeningWelcomeDocument:(BOOL)openWelcomeDocument;

- (void)_fadeInDocumentPickerScrollingToFileItem:(OFSDocumentStoreFileItem *)fileItem;
- (void)_mainThread_finishedLoadingDocument:(OUIDocument *)document animation:(OpenDocumentAnimation)animation completionHandler:(void (^)(void))completionHandler;
- (void)_openDocument:(OFSDocumentStoreFileItem *)fileItem animation:(OpenDocumentAnimation)animation;
- (void)_setDocument:(OUIDocument *)document;

- (void)_promptForUbiquityAccessWithCompletionHandler:(void (^)(DocumentCopyBehavior copyBehavior))completionHandler;
- (void)_handleUbiquityAccessChangeWithCopyBehavior:(DocumentCopyBehavior)copyBehavior withCompletionHandler:(void (^)(void))completionHandler;

- (void)_documentStateChanged:(NSNotification *)note;
- (void)_startConflictResolution:(NSURL *)fileURL;
- (void)_stopConflictResolutionWithCompletion:(void (^)(void))completion;

- (void)_setupGesturesOnTitleTextField;

- (void)_enqueuePreviewUpdateForFileItemsMissingPreviews;
- (void)_fileItemContentsChanged:(OFSDocumentStoreFileItem *)fileItem;
- (void)_fileItemContentsChangedNotification:(NSNotification *)note;
- (void)_continueUpdatingPreviewsOrOpenDocument;
@end

@implementation OUISingleDocumentAppController
{
    UIWindow *_window;
    OUIMainViewController *_mainViewController;
    
    UIBarButtonItem *_closeDocumentBarButtonItem;
    UITextField *_documentTitleTextField;
    UIBarButtonItem *_documentTitleToolbarItem;
    OUIUndoBarButtonItem *_undoBarButtonItem;
    UIBarButtonItem *_infoBarButtonItem;
    OUIDocument *_document;
    
    OUIShieldView *_shieldView;
    BOOL _wasInBackground;
    BOOL _didFinishLaunching;

    OFSDocumentStore *_documentStore;
    
    NSMutableSet *_fileItemsNeedingUpdatedPreviews;
    OFSDocumentStoreFileItem *_currentPreviewUpdatingFileItem;
    OFSDocumentStoreFileItem *_fileItemToOpenAfterCurrentPreviewUpdateFinishes;
    
    OUIDocumentConflictResolutionViewController *_conflictResolutionViewController;
    OUIDocumentStoreSetupViewController *_documentStoreSetupController;
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
    [_mainViewController release];
    
    [self _setDocument:nil];
    
    [_window release];
    
    [_closeDocumentBarButtonItem release];
    [_infoBarButtonItem release];
    
    OBASSERT(_undoBarButtonItem.undoManager == nil);
    _undoBarButtonItem.undoBarButtonItemTarget = nil;
    [_undoBarButtonItem release];
    
    [_documentTitleTextField release];
    [_documentTitleToolbarItem release];
    
    [super dealloc];
}

@synthesize window = _window;
@synthesize mainViewController = _mainViewController;
@synthesize documentTitleTextField = _documentTitleTextField;
@synthesize documentTitleToolbarItem = _documentTitleToolbarItem;

- (void)setDocumentTitleTextField:(UITextField *)textField;
{
    [_documentTitleTextField release];
    _documentTitleTextField = [textField retain];
    [self _setupGesturesOnTitleTextField];
}

- (UIBarButtonItem *)closeDocumentBarButtonItem;
{
    if (!_closeDocumentBarButtonItem) {
        NSString *closeDocumentTitle = NSLocalizedStringWithDefaultValue(@"Documents <back button>", @"OmniUI", OMNI_BUNDLE, @"Documents", @"Toolbar button title for returning to list of documents.");
        _closeDocumentBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:closeDocumentTitle
                                                                        style:UIBarButtonItemStyleBordered target:self action:@selector(closeDocument:)];
        
        [_closeDocumentBarButtonItem applyAppearanceWithBackgroundType:[self defaultBarButtonBackgroundType]];
    }
    return _closeDocumentBarButtonItem;
}

// OmniGraffle overrides -undoBarButtonItem to return an item from its xib
- (OUIUndoBarButtonItem *)undoBarButtonItem;
{
    if (!_undoBarButtonItem) {
        _undoBarButtonItem = [[OUIUndoBarButtonItem alloc] init];
        _undoBarButtonItem.undoBarButtonItemTarget = self;
    }
    return _undoBarButtonItem;
}

- (UIBarButtonItem *)infoBarButtonItem;
{
    if (!_infoBarButtonItem)
        _infoBarButtonItem = [[OUIInspector inspectorBarButtonItemWithTarget:self action:@selector(_showInspector:)] retain];
    return _infoBarButtonItem;
}

- (IBAction)makeNewDocument:(id)sender;
{
    [self.documentPicker newDocument:sender];
}

- (void)closeDocument:(id)sender;
{
    OBPRECONDITION(_document);
    
    if (!_document) {
        // Uh. Whatever.
        _mainViewController.innerViewController = self.documentPicker;
        return;
    }
    
    // Stop tracking the state from this document's undo manager
    [self undoBarButtonItem].undoManager = nil;
    
    OUIWithoutAnimating(^{
        [_window endEditing:YES];
        [_window layoutIfNeeded];
        
        // Make sure -setNeedsDisplay calls (provoked by -endEditing:) have a chance to get flushed before we invalidate the document contents
        OUIDisplayNeededViews();
    });
    
    // The inspector would animate closed and raise an exception, having detected it was getting deallocated while still visible (but animating away).
    [self dismissPopoverAnimated:NO];
    
    // Ending editing may have started opened an undo group, with the nested group stuff for autosave (see OUIDocument). Give the runloop a chance to close the nested group.
    if ([_document.undoManager groupingLevel] > 0) {
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate distantPast]];
        OBASSERT([_document.undoManager groupingLevel] == 0);
    }
    
    // Start up the spinner and stop accepting events.
    [self showActivityIndicatorInView:_document.viewController.view];
    [[UIApplication sharedApplication] beginIgnoringInteractionEvents];
    
    [_document retain];
    [_document closeWithCompletionHandler:^(BOOL success){
        
        // OBFinishPorting: Should rename this and all the ancillary methods to 'did'. This clears the _book pointer, which must be valid until the close (and possible resulting save) are done.
        [_document willClose];
        self.launchAction = nil;
        
        // Doing the -autorelease in the completion handler wasn't late enough. This may not be either...
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            OBASSERT([NSThread isMainThread]);
            [_document autorelease];
        }];
        
        // If the document was saved, it will have already updated *its* previews, if we were launched into a document w/o the document picker ever being visible, we might not have previews loaded for other documents
        [OUIDocumentPreview updatePreviewImageCacheWithCompletionHandler:^{
            OFSDocumentStoreFileItem *fileItem = _document.fileItem;
            
            OUIDocumentPicker *documentPicker = self.documentPicker;
            UIView *documentView = [self pickerAnimationViewForTarget:_document];
            [_mainViewController setInnerViewController:documentPicker animated:YES
                                             fromRegion:^(UIView **outView, CGRect *outRect) {
                                                 *outView = documentView;
                                                 *outRect = CGRectZero;
                                             } toRegion:^(UIView **outView, CGRect *outRect) {
                                                 OUIDocumentPickerFileItemView *fileItemView = [documentPicker.activeScrollView fileItemViewForFileItem:fileItem];
                                                 OBASSERT(fileItemView != nil);
                                                 [fileItemView loadPreviews];

                                                 OUIDocumentPreviewView *previewView = fileItemView.previewView;
                                                 *outView = previewView;
                                                 *outRect = previewView.imageBounds;
                                             } transitionAction:^{
                                                 [documentPicker.activeScrollView sortItems];
                                                 [documentPicker scrollItemToVisible:fileItem animated:NO];
                                             } completionAction:^{
                                                 [[UIApplication sharedApplication] endIgnoringInteractionEvents];
                                             }];
            
            [self _setDocument:nil];
            
            // Start updating the previews for any other documents that were edited and have had incoming iCloud changes invalidate their previews.
            [self _continueUpdatingPreviewsOrOpenDocument];
        }];
    }];
}

- (CGFloat)titleTextFieldWidthForOrientation:(UIInterfaceOrientation)orientation;
{
    if ((orientation == UIInterfaceOrientationPortrait) ||
        (orientation == UIInterfaceOrientationPortraitUpsideDown)) {
        return 400;
    }
    else {
        return 650;
    }
}

- (OUIBarButtonItemBackgroundType)defaultBarButtonBackgroundType;
{
    return OUIBarButtonItemBackgroundTypeClear;
}

- (NSString *)documentTypeForURL:(NSURL *)url;
{
    NSError *error;
    NSString *uti = OFUTIForFileURLPreferringNative(url, &error);
    if (uti) {
        OBASSERT([uti hasPrefix:@"dyn."] == NO); // should be registered
        return uti;
    } else {
        OBASSERT_NOT_REACHED("Failed to get UTI for URL; maybe the URL doesn't point to an existing file in the filesystem?");
        NSLog(@"Failed to get UTI for file URL %@: %@", url, [error toPropertyList]);
        return nil;
    }
}

- (OUIDocument *)document;
{
    return _document;
}

#pragma mark -
#pragma mark Sample documents

- (NSString *)sampleDocumentsDirectoryTitle;
{
    return NSLocalizedStringFromTableInBundle(@"Restore Sample Document", @"OmniUI", OMNI_BUNDLE, @"Restore Sample Document Title");
}

- (NSURL *)sampleDocumentsDirectoryURL;
{
    NSString *samples = [[NSBundle mainBundle] pathForResource:@"Samples" ofType:@""];
    OBASSERT(samples);
    return [NSURL fileURLWithPath:samples isDirectory:YES];
}

- (void)copySampleDocumentsToUserDocuments;
{
    // This should be called as part of an after-scan action. We don't want to re-copy the samples if the user already has some documents, local or in iCloud
    OBPRECONDITION(_documentStore.self.hasFinishedInitialMetdataQuery);
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSURL *sampleDocumentsDirectoryURL = [self sampleDocumentsDirectoryURL];
    NSURL *userDocumentsDirectoryURL = _documentStore.directoryURL;
    OBASSERT(userDocumentsDirectoryURL);
    
    NSError *error = nil;
    NSArray *sampleURLs = [fileManager contentsOfDirectoryAtURL:sampleDocumentsDirectoryURL includingPropertiesForKeys:nil options:0 error:&error];
    if (!sampleURLs) {
        NSLog(@"Unable to find sample documents at %@: %@", sampleDocumentsDirectoryURL, [error toPropertyList]);
        return;
    }
    
    for (NSURL *sampleURL in sampleURLs) {
        NSURL *documentURL = [userDocumentsDirectoryURL URLByAppendingPathComponent:[sampleURL lastPathComponent]];
        NSString *documentName = [[documentURL lastPathComponent] stringByDeletingPathExtension];
        
        NSString *localizedTitle = [self localizedNameForSampleDocumentNamed:documentName];
        if (localizedTitle && ![localizedTitle isEqualToString:documentName]) {
            documentURL = [userDocumentsDirectoryURL URLByAppendingPathComponent:[localizedTitle stringByAppendingPathExtension:[documentURL pathExtension]]];
        }
        
        // Sample documents are regeneratable, so we really shouldn't put them in the cloud.
        // iWork does create new documents in the cloud if enabled, but those are user-initiated.
        if (![[NSFileManager defaultManager] copyItemAtURL:sampleURL toURL:documentURL error:&error]) {
            NSLog(@"Unable to copy %@ to %@: %@", sampleURL, documentURL, [error toPropertyList]);
        } else if ([[documentName stringByDeletingPathExtension] isEqualToString:@"Welcome"]) {
            [fileManager touchItemAtURL:documentURL error:NULL];
        }
    }
}

- (NSString *)localizedNameForSampleDocumentNamed:(NSString *)documentName;
{
    return [[NSBundle mainBundle] localizedStringForKey:documentName value:documentName table:@"SampleNames"];
}

- (NSURL *)URLForSampleDocumentNamed:(NSString *)name ofType:(NSString *)fileType;
{
    CFStringRef extension = UTTypeCopyPreferredTagWithClass((CFStringRef)fileType, kUTTagClassFilenameExtension);
    if (!extension)
        OBRequestConcreteImplementation(self, _cmd); // UTI not registered in the Info.plist?
    
    NSString *fileName = [name stringByAppendingPathExtension:(NSString *)extension];
    CFRelease(extension);
    
    return [[self sampleDocumentsDirectoryURL] URLByAppendingPathComponent:fileName];
}

#pragma mark -
#pragma mark OUIAppController subclass

- (UIViewController *)topViewController;
{
    return _mainViewController;
}

- (void)createNewDocumentAtURL:(NSURL *)url completionHandler:(void (^)(NSURL *url, NSError *error))completionHandler;
{
    OBPRECONDITION(_document == nil);
    
    completionHandler = [[completionHandler copy] autorelease];
    
    Class cls = [self documentClassForURL:url];
    OBASSERT(OBClassIsSubclassOfClass(cls, [OUIDocument class]));
    
    NSError *error = nil;
    OUIDocument *document = [[cls alloc] initEmptyDocumentToBeSavedToURL:url error:&error];
    if (document == nil) {
        if (completionHandler)
            completionHandler(nil, error);
        return;
    }
    
    [document saveToURL:url forSaveOperation:UIDocumentSaveForCreating completionHandler:^(BOOL saveSuccess){
        // The save completion handler isn't called on the main thread; jump over *there* to start the close (subclasses want that).
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            [document closeWithCompletionHandler:^(BOOL closeSuccess){
                [document willClose];
                [document release];
                
                if (completionHandler) {
                    if (!saveSuccess) {
                        // The document instance should have gotten the real error presented some other way
                        NSError *cancelledError = [NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError userInfo:nil];
                        completionHandler(nil, cancelledError);
                    } else {
                        completionHandler(url, nil);
                    }
                }
            }];
        }];
    }];
}

#pragma mark -
#pragma mark Subclass responsibility

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
#pragma mark UITextFieldDelegate

- (BOOL)textFieldShouldBeginEditing:(UITextField *)textField;
{
    OBPRECONDITION(textField == _documentTitleTextField);

    OFSDocumentStoreFileItem *fileItem = _document.fileItem;
    OBASSERT(fileItem);
    
    textField.text = fileItem.editingName;
    return YES;
}

- (void)textFieldDidEndEditing:(UITextField *)textField;
{
    OBPRECONDITION(textField == _documentTitleTextField);
    
    // UITextField adjusts its recognizers when it starts editing. Put ours back.
    [self _setupGesturesOnTitleTextField];

    // If we are new, there will be no fileItem.
    // Actually, we give documents default names and load their fileItem up immediately on creation...
    NSString *originalName = _document.fileItem.editingName;
    OBASSERT(originalName);

    NSString *newName = [textField text];
    if (!newName || [newName length] == 0) {
        textField.text = originalName;
        return;
    }
    
    if (![newName isEqualToString:originalName]) {
        OFSDocumentStoreFileItem *fileItem = _document.fileItem;
        OBASSERT(fileItem); // any document that gets opened already has a fileItem
        
        OUIDocumentPicker *documentPicker = self.documentPicker;
        NSString *documentType = [self documentTypeForURL:fileItem.fileURL];
        
        OFSDocumentStore *documentStore = documentPicker.documentStore;
        
        // Make sure we don't close the document while the rename is happening, or some such. It would probably be OK with the synchronization API, but there is no reason to allow it.
        [[UIApplication sharedApplication] beginIgnoringInteractionEvents];
        
        // We have to synchronize with any in flight autosaves
        [_document performAsynchronousFileAccessUsingBlock:^{
            OBASSERT([NSThread isMainThread] == NO);
            
            [documentStore renameFileItem:fileItem baseName:newName fileType:documentType completionQueue:[NSOperationQueue mainQueue] handler:^(NSURL *destinationURL, NSError *error){
                OBASSERT([NSThread isMainThread] == YES);
                
                [[UIApplication sharedApplication] endIgnoringInteractionEvents];

                // <bug://bugs/61021> Code below checks for "/" in the name, but there could still be other renaming problems that we don't know about.
                if (!destinationURL) {
                    NSLog(@"Error renaming document with URL \"%@\" to \"%@\" with type \"%@\": %@", [fileItem.fileURL absoluteString], newName, documentType, [error toPropertyList]);
                    
                    NSString *msg = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Unable to rename document to \"%@\".", @"OmniUI", OMNI_BUNDLE, @"error when renaming a document"), newName];                
                    NSError *err = [[NSError alloc] initWithDomain:NSURLErrorDomain code:0 userInfo:[NSDictionary dictionaryWithObjectsAndKeys:msg, NSLocalizedDescriptionKey, msg, NSLocalizedFailureReasonErrorKey, nil]];
                    OUI_PRESENT_ERROR(err);
                    [err release];
                }
                
                OBFinishPortingLater("The notification from NSFilePresenter happens after a delay, so this will load the old name. Also, we could get unsolicited renames from iCloud while we are open, so we should really handle this another way");
                OBASSERT(_document.fileItem);
                textField.text = _document.fileItem.name;
            }];
        }];
    }
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
                                  orOpeningWelcomeDocument:(BOOL)openWelcomeDocument;
{
    DEBUG_LAUNCH(@"Delayed finish launching allowCopyingSamples:%d openURL:%@ orWelcome:%d", allowCopyingSampleDocuments, launchDocumentURL, openWelcomeDocument);
    
    OUIDocumentPicker *documentPicker = self.documentPicker;

    BOOL startedOpeningDocument = NO;
    OFSDocumentStoreFileItem *fileItemToSelect = nil;
    OFSDocumentStoreFileItem *launchFileItem = nil;
    
    if (launchDocumentURL) {
        launchFileItem = [_documentStore fileItemWithURL:launchDocumentURL];
        DEBUG_LAUNCH(@"  launchFileItem: %@", [launchFileItem shortDescription]);
    }
    
    if (allowCopyingSampleDocuments && launchDocumentURL == nil && ![[NSUserDefaults standardUserDefaults] boolForKey:@"SampleDocumentsHaveBeenCopiedToUserDocuments"]) {
        // Copy in a welcome document if one exists and we haven't done so for first launch yet.
        [self copySampleDocumentsToUserDocuments];
        
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"SampleDocumentsHaveBeenCopiedToUserDocuments"];
        
        [_documentStore scanItemsWithCompletionHandler:^{
            // Retry after the scan finished, but this time try opening the Welcome document
            [self _delayedFinishLaunchingAllowCopyingSampleDocuments:NO // we just did, don't try again
                                              openingDocumentWithURL:nil // already checked this
                                            orOpeningWelcomeDocument:YES];
        }];
        return;
    }
    
    if (!launchFileItem && openWelcomeDocument) {
        launchFileItem = [_documentStore fileItemNamed:[self localizedNameForSampleDocumentNamed:@"Welcome"]];
        DEBUG_LAUNCH(@"  launchFileItem: %@", [launchFileItem shortDescription]);
    }

    if (launchFileItem != nil) {
        DEBUG_LAUNCH(@"Opening document %@", [launchFileItem shortDescription]);
        [self performSelector:@selector(_loadStartupDocument:) withObject:launchFileItem afterDelay:0.0];
        startedOpeningDocument = YES;
    } else {
        // Restore our selected or open document if we didn't get a command from on high.
        NSArray *launchAction = [[self.launchAction copy] autorelease];
        
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
                    [self performSelector:@selector(_loadStartupDocument:) withObject:launchFileItem afterDelay:0.0];
                    startedOpeningDocument = YES;
                } else
                    fileItemToSelect = launchFileItem;
            }
        }
    }
    
    // Iff we didn't open a document, go to the document picker. We don't want to start loading of previews if the user is going directly to a document (particularly the welcome document).
    if (!startedOpeningDocument) {
        [self _fadeInDocumentPickerScrollingToFileItem:fileItemToSelect];
    } else {
        // Now that we are on screen, if we are waiting for a document to open, we'll just fade it in when it is loaded.
    }
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions;
{
    DEBUG_LAUNCH(@"Did launch with options %@", launchOptions);
    
    [self _setupGesturesOnTitleTextField];
    
    _mainViewController.resizesToAvoidKeyboard = YES;
    
    _mainViewController.view.frame = _window.screen.applicationFrame;
    _window.rootViewController = _mainViewController;
    [_window makeKeyAndVisible];
    
    // Add a placeholder view controller until we finish scanning
    OUILaunchViewController *launchViewController = [[OUILaunchViewController alloc] init];
    [_mainViewController setInnerViewController:launchViewController animated:NO fromView:nil toView:nil];
    [launchViewController release];
    
    // Pump the runloop once so that the -viewDidAppear: messages get sent before we muck with the view containment again. Otherwise, we never get -viewDidAppear: on the root view controller, and thus the OUILaunchViewController, causing assertions.
    OUIDisplayNeededViews();
    OBASSERT(launchViewController.visibility == OUIViewControllerVisibilityVisible);
    
    NSURL *launchOptionsURL = [launchOptions objectForKey:UIApplicationLaunchOptionsURLKey];
    
    void (^moarFinishing)(DocumentCopyBehavior copyBehavior) = ^(DocumentCopyBehavior copyBehavior){
        DEBUG_LAUNCH(@"Creating document store");
        
        _documentStore = [[OFSDocumentStore alloc] initWithDirectoryURL:[OFSDocumentStore userDocumentsDirectoryURL] delegate:self scanCompletionHandler:nil];
                     
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_fileItemContentsChangedNotification:) name:OFSDocumentStoreFileItemContentsChangedNotification object:_documentStore];
        
        OUIDocumentPicker *documentPicker = self.documentPicker;
        documentPicker.documentStore = _documentStore;
        
        // We have to wait for the document store to get results from its NSMetadataQuery (if iCloud is enabled on this device and the app is using it).
        [_documentStore addAfterInitialDocumentScanAction:^{
            DEBUG_LAUNCH(@"Initial scan finished");

            OBFinishPortingLater("If the user turns iCloud off and then back on, we could still end up moving sample documents into iCloud"); // We could maybe add a custom xattr to sample documents and make sure that doesn't get saved on save (or specifically remove it). Ugly, but then we could avoid moving sample documents into iCloud.
            
            // Now that we know what the existing documents are, possibly move some of them into iCloud (before we possibly create sample documents which should not be moved into iCloud).
            [self _handleUbiquityAccessChangeWithCopyBehavior:copyBehavior withCompletionHandler:^{
                [self _delayedFinishLaunchingAllowCopyingSampleDocuments:YES
                                                  openingDocumentWithURL:launchOptionsURL
                                                orOpeningWelcomeDocument:NO]; // Don't always try to open the welcome document; just if we copy samples
            }];
        }];
        
        _didFinishLaunching = YES;
        
        // Start real preview generation any time we are missing one.
        [[NSNotificationCenter defaultCenter] addObserverForName:OUIDocumentPickerItemViewPreviewsDidLoadNotification object:nil queue:nil usingBlock:^(NSNotification *note){
            OUIDocumentPickerItemView *itemView = [note object];
            for (OUIDocumentPreview *preview in itemView.loadedPreviews) {
                if (preview.type == OUIDocumentPreviewTypePlaceholder) {
                    OBFinishPortingLater("If we got a zero-length preview file, we shouldn't do this. Need to know why the preview is a placeholder so we avoid spinning.");
                    
                    // Fake a content change to regenerate a preview
                    OFSDocumentStoreFileItem *fileItem = [_documentStore fileItemWithURL:preview.fileURL];
                    OBASSERT(fileItem);
                    if (fileItem)
                        [self _fileItemContentsChanged:fileItem];
                }
            }
        }];
    };

    // If the app is launched for the first time (or first time after enabling iCloud) due to tapping on a document in some other app, don't prompt for iCloud, but do what the user actually wanted.
    // TODO: In this case, it would be good to show this the first time the document picker is visible.
    if (launchOptionsURL == nil && [OFSDocumentStore shouldPromptForUbiquityAccess] == YES) {
        DEBUG_LAUNCH(@"Prompting user for iCloud enabledness");
        moarFinishing = [[moarFinishing copy] autorelease];
        
        // If we don't defer for a bit, this can come up in the wrong orientation if the device is in face-up orientation. <bug:///76783> (First launch iCloud screen doesn't obey orientation).
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            [self _promptForUbiquityAccessWithCompletionHandler:moarFinishing];
        }];
    } else {
        moarFinishing(DocumentCopyBehaviorNone);
    }
    
    return YES;
}

/*
 This is split out to avoid a semi-random (probably notification sending order dependent) assertion if we try to open a document at launch time:
 
2011-06-16 14:27:50.109 OmniOutliner-iPad[35144:15b03] *** Assertion failure in -[Document revertToContentsOfURL:completionHandler:], /SourceCache/UIKit_Sim/UIKit-1727.6/UIDocument.m:692
 
 Apple is going to look at this (and has other reports of it).
 
 */

- (void)_loadStartupDocument:(OFSDocumentStoreFileItem *)fileItem;
{
    [self _openDocument:fileItem animation:OpenDocumentAnimationDissolve];
}

- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url sourceApplication:(NSString *)sourceApplication annotation:(id)annotation;
{
    if (!_didFinishLaunching)  // if the app is launched by an open request from another app, then this is called and then application:didFinishLaunchingWithOptions: is called
        return YES;            // and application:didFinishLaunchingWithOptions: handles opening the doc
    
    if ([self isSpecialURL:url]) {
        return [self handleSpecialURL:url];
    }
    
    OFSDocumentStore *documentStore = self.documentPicker.documentStore;
    [documentStore scanItemsWithCompletionHandler:^{
        [documentStore cloneInboxItem:url completionHandler:^(OFSDocumentStoreFileItem *newFileItem, NSError *errorOrNil) {
            NSError *deleteInboxError = nil;
            if (![documentStore deleteInbox:&deleteInboxError]) {
                NSLog(@"Failed to delete the inbox: %@", [deleteInboxError toPropertyList]);
            }
            
            main_async(^{
                if (!newFileItem) {
                    // Display Error and return.
                    OUI_PRESENT_ERROR(errorOrNil);
                    return;
                }
                
                [self _openDocument:newFileItem animation:OpenDocumentAnimationDissolve];
            });
        }];
    }];
    
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
            [self _enqueuePreviewUpdateForFileItemsMissingPreviews];
        }];
        _wasInBackground = NO;
    }
}

- (void)applicationWillEnterForeground:(UIApplication *)application;
{
    // Might be running one already due to launching. Or, iCloud might be enabled while we were backgrounded.
    if (_documentStoreSetupController == nil && [OFSDocumentStore shouldPromptForUbiquityAccess] == YES) {
        [self _promptForUbiquityAccessWithCompletionHandler:^(DocumentCopyBehavior copyBehavior){
            [self _handleUbiquityAccessChangeWithCopyBehavior:copyBehavior withCompletionHandler:^{
                // We want to avoid the document store rescanning/renaming stuff until after we've moved things into iCloud (if we do). Otherwise, it'll possibly have renamed local files that conflict with iCloud files to have "(local)" and then put them in iCloud.
                [self _finishedEnteringForeground];
            }];
        }];
        return;
    } else if (_documentStoreSetupController && ![OFSDocumentStore shouldPromptForUbiquityAccess]) {
        // If we have a setup controller, it might be irrelevant now if iCloud was disabled while we were in the background.
        [_documentStoreSetupController cancel];
    }
    
    [self _finishedEnteringForeground];
}

- (void)applicationDidEnterBackground:(UIApplication *)application;
{
    if (_didFinishLaunching) { // Might get backgrounded while the "move docs to iCloud" prompt is still up.
        // We do NOT save the document here. UIDocument subscribes to application lifecycle notifications and will provoke a save on itself.
        [self _setLaunchActionFromCurrentState];
    }
    
    if (_documentStore) {
        OBASSERT(_wasInBackground == NO);
        _wasInBackground = YES;
        [_documentStore applicationDidEnterBackground];
    }

    [super applicationDidEnterBackground:application];
    
}

- (void)applicationWillTerminate:(UIApplication *)application;
{
    [self _setLaunchActionFromCurrentState];
    
    [super applicationWillTerminate:application];
}

#pragma mark -
#pragma mark OUIDocumentPickerDelegate

- (void)documentPicker:(OUIDocumentPicker *)picker openTappedFileItem:(OFSDocumentStoreFileItem *)fileItem;
{
    OBPRECONDITION(fileItem);
    OBPRECONDITION(_fileItemToOpenAfterCurrentPreviewUpdateFinishes == nil);
    
    if (fileItem.hasUnresolvedConflicts) {
        [self _startConflictResolution:fileItem.fileURL];
        return;
    }
    
    // If we crash in trying to open this document, we should stay in the file picker the next time we launch rather than trying to open it over and over again
    self.launchAction = nil;
    
    if (_currentPreviewUpdatingFileItem) {
        PREVIEW_DEBUG(@"Delaying opening document at %@ until preview refresh finishes for %@", fileItem.fileURL, _currentPreviewUpdatingFileItem.fileURL);
        
        // Delay the open until after we've finished updating this preview
        [_fileItemToOpenAfterCurrentPreviewUpdateFinishes release];
        _fileItemToOpenAfterCurrentPreviewUpdateFinishes = [fileItem retain];
        
        OBFinishPortingLater("Turn off user interaction while this is going on");
        return;
    }
    
    [self _openDocument:fileItem animation:OpenDocumentAnimationZoom];
}

- (void)documentPicker:(OUIDocumentPicker *)picker openCreatedFileItem:(OFSDocumentStoreFileItem *)fileItem;
{
    OBPRECONDITION(fileItem);
    OBPRECONDITION(fileItem.hasUnresolvedConflicts == NO); // it's new
    OBPRECONDITION(_fileItemToOpenAfterCurrentPreviewUpdateFinishes == nil);
    
    // If we crash in trying to open this document, we should stay in the file picker the next time we launch rather than trying to open it over and over again
    self.launchAction = nil;
    
    // We could also remember the animation type if we want to defer this until after this preview is done generating.
#if 0
    if (_currentPreviewUpdatingFileItem) {
        PREVIEW_DEBUG(@"Delaying opening document at %@ until preview refresh finishes for %@", fileItem.fileURL, _currentPreviewUpdatingFileItem.fileURL);
        
        // Delay the open until after we've finished updating this preview
        [_fileItemToOpenAfterCurrentPreviewUpdateFinishes release];
        _fileItemToOpenAfterCurrentPreviewUpdateFinishes = [fileItem retain];
        
        OBFinishPortingLater("Turn off user interaction while this is going on");
        return;
    }
#endif
    
    [self _openDocument:fileItem animation:OpenDocumentAnimationDissolve];
}

#pragma mark -
#pragma mark OUIDocumentConflictResolutionViewControllerDelegate

- (void)conflictResolutionCancelled:(OUIDocumentConflictResolutionViewController *)conflictResolution;
{
    OBPRECONDITION(_conflictResolutionViewController == conflictResolution);
    [self _stopConflictResolutionWithCompletion:nil];
    
    // We currently don't allow editing a document in conflict. If the user cancelled, go back to the document picker.
    if (_document)
        [self closeDocument:nil];
}

- (void)conflictResolutionFinished:(OUIDocumentConflictResolutionViewController *)conflictResolution;
{
    OBPRECONDITION(_conflictResolutionViewController == conflictResolution);
    [self _stopConflictResolutionWithCompletion:nil];
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

#pragma mark -
#pragma mark Private

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

- (void)_fadeInDocumentPickerScrollingToFileItem:(OFSDocumentStoreFileItem *)fileItem;
{
    DEBUG_LAUNCH(@"Showing picker, showing item %@", [fileItem shortDescription]);
    
    OUIDocumentPicker *documentPicker = self.documentPicker;
    
    [OUIDocumentPreview updatePreviewImageCacheWithCompletionHandler:^{
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
                            [self _enqueuePreviewUpdateForFileItemsMissingPreviews];
                        }];
    }];
}

- (void)_mainThread_finishedLoadingDocument:(OUIDocument *)document animation:(OpenDocumentAnimation)animation completionHandler:(void (^)(void))completionHandler;
{
    OBASSERT([NSThread isMainThread]);
    [self _setDocument:document];
        
    NSString *title = _document.fileItem.name;
    OBASSERT(title);
    _documentTitleTextField.text = title;
    
    UIViewController <OUIDocumentViewController> *viewController = _document.viewController;
    [viewController view]; // make sure the view is loaded in case -pickerAnimationViewForTarget: doesn't and return a subview thereof.
    
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
    completionHandler = [[completionHandler copy] autorelease];
    
    switch (animation) {
        case OpenDocumentAnimationZoom: {
            OUIDocumentPickerFileItemView *fileItemView = [self.documentPicker.activeScrollView fileItemViewForFileItem:_document.fileItem];
            OBASSERT(fileItemView);
            UIView *documentView = [self pickerAnimationViewForTarget:_document];
            [_mainViewController setInnerViewController:viewController animated:YES
                                             fromRegion:^(UIView **outView, CGRect *outRect){
                                                 OUIDocumentPreviewView *previewView = fileItemView.previewView;
                                                 *outView = previewView;
                                                 *outRect = previewView.imageBounds;
                                             } toRegion:^(UIView **outView, CGRect *outRect){
                                                 *outView = documentView;
                                                 *outRect = CGRectZero;
                                             } transitionAction:nil
                                       completionAction:^{
                                           if ([viewController respondsToSelector:@selector(documentFinishedOpening)])
                                               [viewController documentFinishedOpening];
                                           if (completionHandler)
                                               completionHandler();
                                       }];

            [self hideActivityIndicator]; // will be on the item preview view for a document tap initiated load
            break;
        }
        case OpenDocumentAnimationDissolve:
            [UIView transitionWithView:_mainViewController.view duration:0.25
                               options:UIViewAnimationOptionTransitionCrossDissolve
                            animations:^{
                                OUIWithoutAnimating(^{ // some animations get added anyway if we specify NO ... avoid a weird jump from the start to end frame
                                    [_mainViewController setInnerViewController:viewController animated:NO fromView:nil toView:nil];
                                });
                                [_mainViewController.view layoutIfNeeded];
                            }
                            completion:^(BOOL finished){
                                if ([viewController respondsToSelector:@selector(documentFinishedOpening)])
                                    [viewController documentFinishedOpening];
                                if (completionHandler)
                                    completionHandler();
                            }];
            break;
        default:
            // this shouldn't happen, but JUST IN CASE...
            OBASSERT_NOT_REACHED("Should've specificed a valid OpenDocumentAnimation");
            if (completionHandler)
                completionHandler();
    } 
}

- (void)_openDocument:(OFSDocumentStoreFileItem *)fileItem animation:(OpenDocumentAnimation)animation;
{
    OBPRECONDITION([NSThread isMainThread]);
    OBPRECONDITION(fileItem);
    
    void (^onFail)(void) = ^{
        // The launch document failed to load -- don't leave the user with no document picker and no open document!
        if (_mainViewController.innerViewController != self.documentPicker)
            [self _fadeInDocumentPickerScrollingToFileItem:fileItem];
    };
    onFail = [[onFail copy] autorelease];
    
    if (fileItem.scope == OFSDocumentStoreScopeUbiquitous) {
        // Need to provoke download, and if this is a launch-time open, we need to return NO to let the caller know it should just go to the document picker instead. Maybe we shouldn't actually provoke download in the launch time case, really. The user might want to tap another document and not compete for download bandwidth.
        if (!fileItem.isDownloaded) {
            NSError *error = nil;
            if (![[NSFileManager defaultManager] startDownloadingUbiquitousItemAtURL:fileItem.fileURL error:&error])
                OUI_PRESENT_ERROR(error);
            onFail();
            return;
        }
    }

    OUIDocumentPickerFileItemView *fileItemView = nil;
    if (animation == OpenDocumentAnimationZoom) {
        fileItemView = [self.documentPicker.activeScrollView fileItemViewForFileItem:fileItem];
        OBASSERT(fileItemView);

        fileItemView.highlighted = YES;
        [self showActivityIndicatorInView:fileItemView.previewView];
    }
    
    void (^doOpen)(void) = ^{
        Class cls = [self documentClassForURL:fileItem.fileURL];
        OBASSERT(OBClassIsSubclassOfClass(cls, [OUIDocument class]));
        
        NSError *error = nil;
        OUIDocument *document = [[[cls alloc] initWithExistingFileItem:fileItem error:&error] autorelease];
        if (!document) {
            OUI_PRESENT_ERROR(error);
            onFail();
            return;
        }
        
        [[UIApplication sharedApplication] beginIgnoringInteractionEvents];
        
        [document openWithCompletionHandler:^(BOOL success){
            if (animation == OpenDocumentAnimationZoom) {
                OBASSERT(fileItemView.highlighted);
                fileItemView.highlighted = NO;
            } else {
                OBASSERT(fileItemView == nil);
            }
            
            if (!success) {
                OBASSERT([NSThread isMainThread]);
                
                // Failed to read the document. The error will have already been presented via OUIDocument's -handleError:userInteractionPermitted:.
                OBASSERT(document.documentState == (UIDocumentStateClosed|UIDocumentStateSavingError)); // don't have to close it here.
                [self hideActivityIndicator];
                [[UIApplication sharedApplication] endIgnoringInteractionEvents];
                
                onFail();
                return;
            }
            
            [self _mainThread_finishedLoadingDocument:document animation:animation completionHandler:^{
                [[UIApplication sharedApplication] endIgnoringInteractionEvents];
            }];
        }];
    };
    
    if (_document) {
        // If we have a document open, wait for it to close before starting to open the new one.
        doOpen = [[doOpen copy] autorelease];

        [_document closeWithCompletionHandler:^(BOOL success) {
            [self _setDocument:nil];
            
            doOpen();
        }];
    } else {
        // Just open immediately
        doOpen();
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
    
    [_document release];
    _document = [document retain];
    
    if (_document) {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_documentStateChanged:) name:UIDocumentStateChangedNotification object:_document]; 
    }
}

// Called from the main app menu
- (void)_setupCloud:(id)sender;
{
    [self _promptForUbiquityAccessWithCompletionHandler:^(DocumentCopyBehavior copyBehavior){
        [self _handleUbiquityAccessChangeWithCopyBehavior:copyBehavior withCompletionHandler:nil];
    }];
}

- (void)_promptForUbiquityAccessWithCompletionHandler:(void (^)(DocumentCopyBehavior copyBehavior))completionHandler;
{
    OBPRECONDITION(_documentStoreSetupController == nil);
    OBPRECONDITION([OFSDocumentStore canPromptForUbiquityAccess]);
    
    completionHandler = [[completionHandler copy] autorelease];
    
    DEBUG_LAUNCH(@"Prompting user for iCloud enabledness");
    
    _documentStoreSetupController = [[OUIDocumentStoreSetupViewController alloc] initWithDismissAction:^(BOOL cancelled){
        DEBUG_LAUNCH(@"Prompt completed");
                
        [_mainViewController dismissViewControllerAnimated:YES completion:^{
            DocumentCopyBehavior copyBehavior = DocumentCopyBehaviorNone;
            
            if (!cancelled) {
                BOOL useICloud = _documentStoreSetupController.useICloud;
                [OFSDocumentStore didPromptForUbiquityAccessWithResult:useICloud];
                
                if (useICloud && _documentStoreSetupController.moveExistingDocumentsToICloud) {
                    copyBehavior = DocumentCopyBehaviorMoveLocalToCloud;
                }
            }
            
            [_documentStoreSetupController release];
            _documentStoreSetupController = nil;
            
            if (completionHandler)
                completionHandler(copyBehavior);
        }];
        
    }];
    [_mainViewController presentViewController:_documentStoreSetupController animated:YES completion:nil];
}

- (void)_handleUbiquityAccessChangeWithCopyBehavior:(DocumentCopyBehavior)copyBehavior withCompletionHandler:(void (^)(void))completionHandler;
{
    switch (copyBehavior) {
        case DocumentCopyBehaviorNone:
            if (completionHandler)
                completionHandler();
            return;
        case DocumentCopyBehaviorMoveLocalToCloud:
            
            completionHandler = [[completionHandler copy] autorelease]; // capture scope
            
            [_documentStore moveLocalDocumentsToCloudWithCompletionHandler:^(NSDictionary *movedURLs, NSDictionary *errorURLs){
                if (completionHandler)
                    completionHandler();

                if ([errorURLs count] > 0) {
                    
                    NSString *title = NSLocalizedStringFromTableInBundle(@"Error moving to iCloud", @"OmniUI", OMNI_BUNDLE, @"Alert title");
                    NSString *message;
                    
                    if ([movedURLs count] > 0)
                        message = NSLocalizedStringFromTableInBundle(@"Some files were not moved to iCloud.", @"OmniUI", OMNI_BUNDLE, @"Alert message");
                    else
                        message = NSLocalizedStringFromTableInBundle(@"No files were moved to iCloud.", @"OmniUI", OMNI_BUNDLE, @"Alert message");                
                    
                    
                    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:title message:message delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
                    [alert show];
                    [alert release];
                }
            }];
            return;
    }
    
    OBASSERT_NOT_REACHED("Unhandled behavior");
}

- (void)_documentStateChanged:(NSNotification *)note;
{
    OBPRECONDITION([note object] == _document);
    
    UIDocumentState state = _document.documentState;
    DEBUG_DOCUMENT(@"State changed to %ld", state);
    
    // When entering the conflict state, the state will transition from UIDocumentStateNormal to UIDocumentStateEditingDisabled, to UIDocumentStateEditingDisabled|UIDocumentStateInConflict to UIDocumentStateInConflict.
    if ((state & UIDocumentStateInConflict) && !_conflictResolutionViewController) {
        [self _startConflictResolution:_document.fileURL];
    } else if ((state & UIDocumentStateInConflict) == 0 && _conflictResolutionViewController) {
        [self _stopConflictResolutionWithCompletion:nil];
    }
}

- (void)_startConflictResolution:(NSURL *)fileURL;
{
    if (_conflictResolutionViewController) {
        OBASSERT_NOT_REACHED("Should have already ended conflict resolution");
        [self _stopConflictResolutionWithCompletion:^{
            [self _startConflictResolution:fileURL];
        }];
        return;
    }
    
    _conflictResolutionViewController = [[OUIDocumentConflictResolutionViewController alloc] initWithDocumentStore:_documentStore fileURL:fileURL delegate:self];
    [_mainViewController presentViewController:_conflictResolutionViewController animated:YES completion:nil];
}

- (void)_stopConflictResolutionWithCompletion:(void (^)(void))completion;
{
    if (_conflictResolutionViewController == nil)
        return;
    OBASSERT(_mainViewController.presentedViewController == _conflictResolutionViewController);
    [_mainViewController dismissViewControllerAnimated:YES completion:^{
        [_conflictResolutionViewController release];
        _conflictResolutionViewController = nil;
        if (completion)
            completion();
    }];
}


- (void)_enqueuePreviewUpdateForFileItemsMissingPreviews;
{
    for (OFSDocumentStoreFileItem *fileItem in _documentStore.fileItems) {
        if ([_fileItemsNeedingUpdatedPreviews member:fileItem])
            continue; // Already queued up.
        
        if (_document && _document.fileItem == fileItem)
            continue; // Ignore this one. The process of closing a document will update its preview and once we become visible we'll check for other previews that need to be updated.

        NSURL *fileURL = fileItem.fileURL;
        NSDate *date = fileItem.date;
        
        if (![OUIDocumentPreview hasPreviewForFileURL:fileURL date:date withLandscape:YES] ||
            ![OUIDocumentPreview hasPreviewForFileURL:fileURL date:date withLandscape:NO]) {
            
            if (!_fileItemsNeedingUpdatedPreviews)
                _fileItemsNeedingUpdatedPreviews = [[NSMutableSet alloc] init];
            [_fileItemsNeedingUpdatedPreviews addObject:fileItem];
        }
    }
    
    if (_document == nil) // Start updating previews immediately if there is no open document. Otherwise, queue them until the document is closed
        [self _continueUpdatingPreviewsOrOpenDocument];
}

- (void)_fileItemContentsChanged:(OFSDocumentStoreFileItem *)fileItem;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    // If we have an open document (the document picker isn't visible), just ignore this. The process of closing a document will update its preview and once we become visible we'll check for other previews that need to be updated.
    if (_document && _document.fileItem == fileItem)
        return;
    
    if ([_fileItemsNeedingUpdatedPreviews member:fileItem] == nil) {
        PREVIEW_DEBUG(@"Queueing preview update of %@", fileItem.fileURL);
        if (!_fileItemsNeedingUpdatedPreviews)
            _fileItemsNeedingUpdatedPreviews = [[NSMutableSet alloc] init];
        [_fileItemsNeedingUpdatedPreviews addObject:fileItem];
        
        if (_document == nil) // Start updating previews immediately if there is no open document. Otherwise, queue them until the document is closed
            [self _continueUpdatingPreviewsOrOpenDocument];
    }
}

- (void)_fileItemContentsChangedNotification:(NSNotification *)note;
{
    OBPRECONDITION([note object] == _documentStore);

    // We'll want to have an operation queue / interlock with opening documents so that we only have one document opening at a time (between the preview updating and real document opening).
    // Doing something hacky for some to have something to improve upon.
    OFSDocumentStoreFileItem *fileItem = [[note userInfo] objectForKey:OFSDocumentStoreFileItemInfoKey];
    OBASSERT([fileItem isKindOfClass:[OFSDocumentStoreFileItem class]]);
    
    [self _fileItemContentsChanged:fileItem];
}

- (void)_continueUpdatingPreviewsOrOpenDocument;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    if (_currentPreviewUpdatingFileItem)
        return; // Already updating one. When this finishes, this method will be called again
    
    // If the user tapped on a document while a preview was happening, we'll have delayed that action until the current preview update finishes (to avoid having two documents open at once and possibliy running out of memory).
    if (_fileItemToOpenAfterCurrentPreviewUpdateFinishes) {
        PREVIEW_DEBUG(@"Performing delayed open of document at %@", _fileItemToOpenAfterCurrentPreviewUpdateFinishes.fileURL);

        OFSDocumentStoreFileItem *fileItem = [_fileItemToOpenAfterCurrentPreviewUpdateFinishes autorelease];
        _fileItemToOpenAfterCurrentPreviewUpdateFinishes = nil;
        
        // Re-invoke the tap
        [self documentPicker:nil openTappedFileItem:fileItem];
        return;
    }
    
    _currentPreviewUpdatingFileItem = [[_fileItemsNeedingUpdatedPreviews anyObject] retain];
    if (!_currentPreviewUpdatingFileItem)
        return; // No more to do!
    
    PREVIEW_DEBUG(@"Starting preview update of %@", _currentPreviewUpdatingFileItem.fileURL);
    Class cls = [self documentClassForURL:_currentPreviewUpdatingFileItem.fileURL];
    OBASSERT(OBClassIsSubclassOfClass(cls, [OUIDocument class]));
    if (!cls)
        return;
    
    // We don't want to open the document and provoke download. If the user taps it to provoke download, or iCloud auto-downloads it, we'll get notified via the document store's metadata query and will update the preview again.
    if ([_currentPreviewUpdatingFileItem isDownloaded] == NO) {
        OBASSERT([_fileItemsNeedingUpdatedPreviews member:_currentPreviewUpdatingFileItem] == _currentPreviewUpdatingFileItem);
        [_fileItemsNeedingUpdatedPreviews removeObject:_currentPreviewUpdatingFileItem];
        [_currentPreviewUpdatingFileItem autorelease];
        _currentPreviewUpdatingFileItem = nil;
        [self _continueUpdatingPreviewsOrOpenDocument];
        return;
    }
    

    NSError *error = nil;
    OUIDocument *document = [[[cls alloc] initWithExistingFileItem:_currentPreviewUpdatingFileItem error:&error] autorelease];
    if (!document) {
        NSLog(@"Error opening document at %@ to rebuild its preview: %@", _currentPreviewUpdatingFileItem.fileURL, [error toPropertyList]);
    }
    
    // Let the document know that it is only going to be used to generate previews.
    document.forPreviewGeneration = YES;
    
    [document openWithCompletionHandler:^(BOOL success){
        OBASSERT([NSThread isMainThread]);
        
        OFSDocumentStoreFileItem *fileItem = [_currentPreviewUpdatingFileItem autorelease];
        _currentPreviewUpdatingFileItem = nil;

        OBASSERT([_fileItemsNeedingUpdatedPreviews member:fileItem] == fileItem);
        [_fileItemsNeedingUpdatedPreviews removeObject:fileItem];

        [document _writePreviewsIfNeeded:YES onlyPlaceholders:!success];

        if (success) {
            [document closeWithCompletionHandler:^(BOOL success){
                OBASSERT([NSThread isMainThread]);
                if (success) {
                    [document willClose];
                    
                    PREVIEW_DEBUG(@"Finished preview update of %@", fileItem.fileURL);
                    
                    // Inform the document picker that it should reload previews for this item, if visible
                    [self.documentPicker _previewsUpdatedForFileItem:fileItem];
                }
            }];
        }
        
        [self _continueUpdatingPreviewsOrOpenDocument];
    }];
}

- (void)_showInspector:(id)sender;
{
    [self showInspectorFromBarButtonItem:_infoBarButtonItem];
}

- (void)_handleTitleTapGesture:(UIGestureRecognizer*)gestureRecognizer;
{
    // do not want an action here
    OBASSERT(gestureRecognizer.view == _documentTitleTextField);
}

static UITapGestureRecognizer *titleTextFieldTap = nil;
static UITapGestureRecognizer *titleTextFieldDoubleTap = nil;

- (void)_handleTitleDoubleTapGesture:(UIGestureRecognizer*)gestureRecognizer;
{
    OBASSERT(gestureRecognizer.view == _documentTitleTextField);
    
    [_documentTitleTextField removeGestureRecognizer:titleTextFieldTap];
    [_documentTitleTextField removeGestureRecognizer:titleTextFieldDoubleTap];
    

    UITapGestureRecognizer *shieldViewTapRecognizer = [[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(_shieldViewTapped:)] autorelease];        
    NSArray *passthroughViews = [NSArray arrayWithObject:_documentTitleTextField];
    _shieldView = [[OUIShieldView shieldViewWithView:_window] retain];
    [_shieldView addGestureRecognizer:shieldViewTapRecognizer];
    _shieldView.passthroughViews = passthroughViews;
    [_window addSubview:_shieldView];
    
    // Switch to a white background while editing so that the text loupe will work properly.
    [_documentTitleTextField setTextColor:[UIColor blackColor]];
    [_documentTitleTextField setBackgroundColor:[UIColor whiteColor]];
    _documentTitleTextField.borderStyle = UITextBorderStyleBezel;
    
    [_documentTitleTextField becomeFirstResponder];
}

- (void)_setupGesturesOnTitleTextField;
{
    if (!titleTextFieldDoubleTap) {
        titleTextFieldDoubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(_handleTitleDoubleTapGesture:)];
        titleTextFieldDoubleTap.numberOfTapsRequired = 2;
    }
    
    if (!titleTextFieldTap) {
        titleTextFieldTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(_handleTitleTapGesture:)];
        
        [titleTextFieldTap requireGestureRecognizerToFail:titleTextFieldDoubleTap];
    }
    
    [_documentTitleTextField addGestureRecognizer:titleTextFieldTap];
    [_documentTitleTextField addGestureRecognizer:titleTextFieldDoubleTap];
    
    // Restore the regular colors of the text field.
    [_documentTitleTextField setTextColor:[UIColor whiteColor]];
    [_documentTitleTextField setBackgroundColor:[UIColor clearColor]];
    _documentTitleTextField.borderStyle = UITextBorderStyleNone;
    if ([_shieldView superview]) {
        [_shieldView removeFromSuperview];
        [_shieldView release], _shieldView = nil;
    }
}

- (void)_shieldViewTapped:(UIGestureRecognizer *)gestureRecognizer;
{
    if (gestureRecognizer.state == UIGestureRecognizerStateEnded) {
        [_shieldView removeFromSuperview];
        [_shieldView release], _shieldView = nil;
        [_documentTitleTextField endEditing:YES];
    }
}

@end

