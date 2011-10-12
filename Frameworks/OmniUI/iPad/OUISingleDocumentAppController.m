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
#import <OmniFileStore/OFSFileInfo.h>
#import <OmniFileStore/OFSFileManager.h>
#import <OmniFoundation/NSFileManager-OFSimpleExtensions.h>
#import <OmniFoundation/OFBundleRegistry.h>
#import <OmniFoundation/OFPreference.h>
#import <OmniUI/OUIBarButtonItem.h>
#import <OmniUI/OUIDocument.h>
#import <OmniUI/OUIDocumentPicker.h>
#import <OmniUI/OUIDocumentPickerFileItemView.h>
#import <OmniUI/OUIDocumentPreviewView.h>
#import <OmniUI/OUIDocumentStore.h>
#import <OmniUI/OUIDocumentStoreFileItem.h>
#import <OmniUI/OUIInspector.h>
#import <OmniUI/OUIShieldView.h>
#import <OmniUI/OUIMainViewController.h>
#import <OmniUI/UIView-OUIExtensions.h>

#import "OUIDocumentConflictResolutionViewController.h"
#import "OUIDocument-Internal.h"
#import "OUIDocumentPicker-Internal.h"
#import "OUIDocumentPickerItemView-Internal.h"
#import "OUIDocumentStore-Internal.h"
#import "OUILaunchViewController.h"
#import "OUIMainViewController-Internal.h"

RCS_ID("$Id$");

static NSString * const OpenAction = @"open";

typedef enum {
    OpenDocumentAnimationZoom,
    OpenDocumentAnimationDissolve,
} OpenDocumentAnimation;

@interface OUISingleDocumentAppController (/*Private*/) <OUIDocumentConflictResolutionViewControllerDelegate>
@property(nonatomic,copy) NSArray *launchAction;
- (void)_documentPickerOpenDocumentAction:(OUIDocumentStoreFileItem *)fileItem;
- (void)_mainThread_finishedLoadingDocument:(OUIDocument *)document animation:(OpenDocumentAnimation)animation;
- (BOOL)_openDocument:(OUIDocumentStoreFileItem *)fileItem animation:(OpenDocumentAnimation)animation;
- (void)_setDocument:(OUIDocument *)document;
- (void)_documentStateChanged:(NSNotification *)note;
- (void)_startConflictResolution:(NSURL *)fileURL;
- (void)_stopConflictResolutionWithCompletion:(void (^)(void))completion;

- (void)_setupGesturesOnTitleTextField;

- (void)_fileItemViewFinishedLoadingPreviews:(OUIDocumentPickerFileItemView *)fileItemView;
- (void)_fileItemViewFinishedLoadingPreviewsNotification:(NSNotification *)note;
- (void)_fileItemContentsChanged:(NSNotification *)note;
- (void)_continueUpdatingPreviewsOrOpenDocument;
@end

@implementation OUISingleDocumentAppController
{
    OUIDocumentStore *_documentStore;
    
    NSMutableSet *_fileItemsNeedingUpdatedPreviews;
    OUIDocumentStoreFileItem *_currentPreviewUpdatingFileItem;
    OUIDocumentStoreFileItem *_fileItemToOpenAfterCurrentPreviewUpdateFinishes;
    
    OUIDocumentConflictResolutionViewController *_conflictResolutionViewController;
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
    
    // Poke OFPreference to get default values registered
#ifdef DEBUG
    NSDictionary *defaults = [NSDictionary dictionaryWithObjectsAndKeys:
                              [NSNumber numberWithBool:YES], @"NSShowNonLocalizableStrings",
                              [NSNumber numberWithBool:YES], @"NSShowNonLocalizedStrings",
                              nil
                              ];
    [[NSUserDefaults standardUserDefaults] registerDefaults:defaults];
#endif
    [OFBundleRegistry registerKnownBundles];
    [OFPreference class];
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
        _closeDocumentBarButtonItem = [[OUIBarButtonItem alloc] initWithTitle:closeDocumentTitle
                                                                        style:UIBarButtonItemStyleBordered target:self action:@selector(closeDocument:)];
    }
    return _closeDocumentBarButtonItem;
}

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
    _undoBarButtonItem.undoManager = nil;
    
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
        
        [[UIApplication sharedApplication] endIgnoringInteractionEvents];

        if (!success) {
            OBFinishPorting; // How do we capture and report the error?
        }
        
        // OBFinishPorting: Should rename this and all the ancillary methods to 'did'. This clears the _book pointer, which must be valid until the close (and possible resulting save) are done.
        [_document willClose];
        self.launchAction = nil;
        
        // Doing the -autorelease in the completion handler wasn't late enough. This may not be either...
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            OBASSERT([NSThread isMainThread]);
            [_document autorelease];
        }];
        
        // Now, start a rescan of the file items
        OUIDocumentPicker *picker = self.documentPicker;
        NSURL *closingURL = [[_document.fileURL copy] autorelease];
        
        [picker.activeScrollView sortItems];
        
        OUIDocumentStoreFileItem *fileItem = [_documentStore fileItemWithURL:closingURL];
        
        OUIWithoutAnimating(^{
            [picker.view layoutIfNeeded];
            [picker scrollItemToVisible:fileItem animated:NO];
        });
        
        OUIDocumentPickerFileItemView *fileItemView = [picker.activeScrollView fileItemViewForFileItem:fileItem];
        OBASSERT(fileItemView);
        [fileItemView startLoadingPreviews];
        
        if (fileItemView.loadingPreviews) {
            [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_fileItemViewFinishedLoadingPreviewsNotification:) name:OUIDocumentPickerItemViewPreviewsDidLoadNotification object:fileItemView];
        } else {
            [self _fileItemViewFinishedLoadingPreviews:fileItemView];
        }
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

- (NSString *)documentTypeForURL:(NSURL *)url;
{
    NSString *uti = [OFSFileInfo UTIForURL:url];
    OBASSERT(uti);
    OBASSERT([uti hasPrefix:@"dyn."] == NO); // should be registered
    return uti;
}

- (OUIDocument *)document;
{
    return _document;
}

#pragma mark -
#pragma mark Sample documents

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
    return [[NSBundle mainBundle] localizedStringForKey:documentName value:nil table:@"SampleNames"];
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

    OUIDocumentStoreFileItem *fileItem = _document.fileItem;
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
        OUIDocumentStoreFileItem *fileItem = _document.fileItem;
        OBASSERT(fileItem); // any document that gets opened already has a fileItem
        
        OUIDocumentPicker *documentPicker = self.documentPicker;
        NSString *documentType = [self documentTypeForURL:fileItem.fileURL];
        
        OUIDocumentStore *documentStore = documentPicker.documentStore;
        
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

- (void)documentDidOpenUndoGroup;
{
    if ([[[[[self.document fileItem] fileURL] URLByDeletingLastPathComponent] lastPathComponent] isEqualToString:@"Inbox"]) {
        OUIDocumentStoreFileItem *fileItem = _document.fileItem;
        OBASSERT(fileItem); // any document that gets opened already has a fileItem
        
        OUIDocumentPicker *documentPicker = self.documentPicker;
        NSString *documentType = [self documentTypeForURL:fileItem.fileURL];
        
        OUIDocumentStore *documentStore = documentPicker.documentStore;
        
        // Make sure we don't close the document while the rename is happening, or some such. It would probably be OK with the synchronization API, but there is no reason to allow it.
        [[UIApplication sharedApplication] beginIgnoringInteractionEvents];
        
        // We have to synchronize with any in flight autosaves
        [_document performAsynchronousFileAccessUsingBlock:^{
            OBASSERT([NSThread isMainThread] == NO);
            
            [documentStore renameFileItem:fileItem baseName:[fileItem name] fileType:documentType completionQueue:[NSOperationQueue mainQueue] handler:^(NSURL *destinationURL, NSError *error){
                OBASSERT([NSThread isMainThread] == YES);
                
                [[UIApplication sharedApplication] endIgnoringInteractionEvents];
                
                // <bug://bugs/61021> Code below checks for "/" in the name, but there could still be other renaming problems that we don't know about.
                if (!destinationURL) {
                    NSLog(@"Error moving %@ from Inbox: %@", [fileItem.fileURL absoluteString], [error toPropertyList]);
                }
                
                _documentTitleTextField.text = _document.fileItem.name;
            }];
        }];
    }

}

#pragma mark -
#pragma mark UIApplicationDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions;
{    
    [self _setupGesturesOnTitleTextField];
    
    _documentStore = [[OUIDocumentStore alloc] initWithDirectoryURL:[OUIDocumentStore userDocumentsDirectoryURL] delegate:self];
                     
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_fileItemContentsChanged:) name:OUIDocumentStoreFileItemContentsChangedNotification object:_documentStore];

    OUIDocumentPicker *documentPicker = self.documentPicker;
    documentPicker.documentStore = _documentStore;
    
    documentPicker.fileItemTappedTarget = self;
    documentPicker.fileItemTappedAction = @selector(_documentPickerOpenDocumentAction:);
    

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
    
    // We have to wait for the document store to get results from its NSMetadataQuery (if iCloud is enabled on this device and the app is using it).
    [_documentStore addAfterInitialDocumentScanAction:^{
        BOOL startedOpeningDocument = NO;
        OUIDocumentStoreFileItem *fileItemToSelect = nil;
        
        NSURL *launchDocumentURL = [launchOptions objectForKey:UIApplicationLaunchOptionsURLKey];
        OUIDocumentStoreFileItem *launchFileItem = [_documentStore fileItemWithURL:launchDocumentURL];
        if (launchDocumentURL == nil && ![_documentStore hasDocuments]) {
            // Copy in a welcome document if one exists and we don't have any other documents
            [self copySampleDocumentsToUserDocuments];
            [documentPicker rescanDocuments];
            
            NSString *welcomeTitle = [self localizedNameForSampleDocumentNamed:@"Welcome"];
            OUIDocumentStoreFileItem *welcomeFileItem = [_documentStore fileItemNamed:welcomeTitle];
            if (welcomeFileItem != nil) {
                startedOpeningDocument = [self _openDocument:welcomeFileItem animation:OpenDocumentAnimationDissolve];
            }
        }
        
        if (launchFileItem != nil) {
            startedOpeningDocument = YES;
            
            [self performSelector:@selector(_loadStartupDocument:) withObject:launchFileItem afterDelay:0.0];
            
        } else {
            // Restore our selected or open document if we didn't get a command from on high.
            NSArray *launchAction = self.launchAction;
            
            if ([launchAction isKindOfClass:[NSArray class]] && [launchAction count] == 2) {
                OUIDocumentStoreFileItem *fileItem = [_documentStore fileItemWithURL:[NSURL URLWithString:[launchAction objectAtIndex:1]]];
                if (fileItem) {
                    [documentPicker scrollItemToVisible:fileItem animated:NO];
                    NSString *action = [launchAction objectAtIndex:0];
                    if ([action isEqualToString:OpenAction]) {
                        [self performSelector:@selector(_loadStartupDocument:) withObject:fileItem afterDelay:0.0];
                        startedOpeningDocument = YES;
                    } else
                        fileItemToSelect = fileItem;
                }
            }
        }
        
        // Iff we didn't open a document, go to the document picker. We don't want to start loading of previews if the user is going directly to a document (particularly the welcome document).
        if (!startedOpeningDocument) {
            [UIView transitionWithView:_mainViewController.view duration:0.25
                               options:UIViewAnimationOptionTransitionCrossDissolve
                            animations:^{
                                OUIWithoutAnimating(^{ // some animations get added anyway if we specify NO ... avoid a weird jump from the start to end frame
                                    [_mainViewController setInnerViewController:documentPicker animated:NO fromView:nil toView:nil];
                                });
                                [_mainViewController.view layoutIfNeeded];
                            }
                            completion:nil];
        }
        
        if (startedOpeningDocument) {
            // Now that we are on screen, if we are waiting for a document to open, we'll just fade it in when it is loaded.
        } else {
            if (!fileItemToSelect)
                [documentPicker scrollToTopAnimated:NO];
            else
                [documentPicker scrollItemToVisible:fileItemToSelect animated:NO];
        }
    }];
    
    _didFinishLaunching = YES;
    
    return YES;
}

/*
 This is split out to avoid a semi-random (probably notification sending order dependent) assertion if we try to open a document at launch time:
 
2011-06-16 14:27:50.109 OmniOutliner-iPad[35144:15b03] *** Assertion failure in -[Document revertToContentsOfURL:completionHandler:], /SourceCache/UIKit_Sim/UIKit-1727.6/UIDocument.m:692
 
 Apple is going to look at this (and has other reports of it).
 
 */

- (void)_loadStartupDocument:(OUIDocumentStoreFileItem *)fileItem;
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

    OUIDocumentPicker *documentPicker = self.documentPicker;
    [documentPicker rescanDocuments];
    OUIDocumentStoreFileItem *fileItem = [documentPicker.documentStore fileItemWithURL:url];
    if (!fileItem)
        return NO;
        
    [self _openDocument:fileItem animation:OpenDocumentAnimationDissolve];
    
    return YES;
}

- (void)_setLaunchActionFromCurrentState;
{
    if (_document)
        self.launchAction = [NSArray arrayWithObjects:OpenAction, [_document.fileURL absoluteString], nil];
    else
        self.launchAction = nil;
}

- (void)applicationDidEnterBackground:(UIApplication *)application;
{
    // We do NOT save the document here. UIDocument subscribes to application lifecycle notifications and will provoke a save on itself.
    [self _setLaunchActionFromCurrentState];
    
    [super applicationDidEnterBackground:application];
}

- (void)applicationWillTerminate:(UIApplication *)application;
{
    [self _setLaunchActionFromCurrentState];
    
    [super applicationWillTerminate:application];
}

#pragma mark -
#pragma mark OUIDocumentPickerDelegate

- (void)createNewDocumentAtURL:(NSURL *)url completionHandler:(void (^)(NSURL *url, NSError *error))completionHandler;
{
    OBPRECONDITION(_document == nil);
    
    Class cls = [self documentClassForURL:url];
    OBASSERT(OBClassIsSubclassOfClass(cls, [OUIDocument class]));
    
    NSError *error = nil;
    OUIDocument *document = [[[cls alloc] initEmptyDocumentToBeSavedToURL:url error:&error] autorelease];
    if (document == nil) {
        if (completionHandler)
            completionHandler(nil, error);
        return;
    }
    
    OBFinishPortingLater("Make sure it gets OFSaveTypeNew");
    
    // We do go ahead and save the document immediately so that we can animate it into view most easily.
    [document closeWithCompletionHandler:^(BOOL success){
        [document willClose];
        if (!success) {
            NSError *error = nil; OBFinishPorting; // need to get the error
            
            if (completionHandler)
                completionHandler(nil, error);
        } else {
            if (completionHandler)
                completionHandler(url, nil);
        }
    }];
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
    return [[NSUserDefaults standardUserDefaults] objectForKey:OUINextLaunchActionDefaultsKey];
}

- (void)setLaunchAction:(NSArray *)launchAction;
{
    [[NSUserDefaults standardUserDefaults] setObject:launchAction forKey:OUINextLaunchActionDefaultsKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)_documentPickerOpenDocumentAction:(OUIDocumentStoreFileItem *)fileItem;
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
    
    // We will have already set _document and prepared for the animation in this case
    BOOL isOpeningNewDocument = [fileItem.fileURL isEqual:_document.fileURL];
    
    if (isOpeningNewDocument) {
        [self _mainThread_finishedLoadingDocument:_document animation:OpenDocumentAnimationZoom];
    } else
        [self _openDocument:fileItem animation:OpenDocumentAnimationZoom];
}

- (void)_mainThread_finishedLoadingDocument:(OUIDocument *)document animation:(OpenDocumentAnimation)animation;
{
    [self _setDocument:document];
    
    NSString *title = _document.fileItem.name;
    OBASSERT(title);
    _documentTitleTextField.text = title;
    
    [_document.viewController view]; // make sure the view is loaded in case -pickerAnimationViewForTarget: doesn't and return a subview thereof.
    
    [self mainThreadFinishedLoadingDocument:document];
    
    switch (animation) {
        case OpenDocumentAnimationZoom: {
            OUIDocumentPickerFileItemView *fileItemView = [self.documentPicker.activeScrollView fileItemViewForFileItem:_document.fileItem];
            OBASSERT(fileItemView);
            UIView *documentView = [self pickerAnimationViewForTarget:_document];
            [_mainViewController setInnerViewController:_document.viewController animated:YES fromView:fileItemView.previewView toView:documentView];
            [self hideActivityIndicator]; // will be on the item preview view for a document tap initiated load
            break;
        }
        case OpenDocumentAnimationDissolve:
            [UIView transitionWithView:_mainViewController.view duration:0.25
                               options:UIViewAnimationOptionTransitionCrossDissolve
                            animations:^{
                                OUIWithoutAnimating(^{ // some animations get added anyway if we specify NO ... avoid a weird jump from the start to end frame
                                    [_mainViewController setInnerViewController:_document.viewController animated:NO fromView:nil toView:nil];
                                });
                                [_mainViewController.view layoutIfNeeded];
                            }
                            completion:nil];
            break;
    }

    // Start automatically tracking undo state from this document's undo manager
    _undoBarButtonItem.undoManager = _document.undoManager;

    // Might be a newly created document that was never edited and trivially returns YES to saving. Make sure there is an item before overwriting our last default value.
    NSURL *url = _document.fileURL;
    OUIDocumentStoreFileItem *fileItem = [_documentStore fileItemWithURL:url];
    if (fileItem) {
        self.launchAction = [NSArray arrayWithObjects:OpenAction, [url absoluteString], nil];
    }

    // Wait until the document is opened to do this, which will let cache entries from opening document A be used in document B w/o being flushed.
    [OAFontDescriptor forgetUnusedInstances];

    // UIWindow will automatically create an undo manager if one isn't found along the responder chain. We want to be darn sure that don't end up getting two undo managers and accidentally splitting our registrations between them.
    OBASSERT([_document undoManager] == [_document.viewController undoManager]);
    OBASSERT([_document undoManager] == [_document.viewController.view undoManager]); // Does your view controller implement -undoManager? We don't do this for you right now.
}

- (BOOL)_openDocument:(OUIDocumentStoreFileItem *)fileItem animation:(OpenDocumentAnimation)animation;
{
    OBPRECONDITION([NSThread isMainThread]);
    OBPRECONDITION(fileItem);
    
    if (fileItem.scope == OUIDocumentStoreScopeUbiquitous) {
        // Need to provoke download, and if this is a launch-time open, we need to return NO to let the caller know it should just go to the document picker instead. Maybe we shouldn't actually provoke download in the launch time case, really. The user might want to tap another document and not compete for download bandwidth.
        if (!fileItem.isDownloaded) {
            NSError *error = nil;
            if (![[NSFileManager defaultManager] startDownloadingUbiquitousItemAtURL:fileItem.fileURL error:&error])
                OUI_PRESENT_ERROR(error);
            return NO;
        }
    }

    if (animation == OpenDocumentAnimationZoom) {
        OUIDocumentPickerFileItemView *fileItemView = [self.documentPicker.activeScrollView fileItemViewForFileItem:fileItem];
        OBASSERT(fileItemView);

        [self showActivityIndicatorInView:fileItemView.previewView];
    }
    
    [self _setDocument:nil];
    
    Class cls = [self documentClassForURL:fileItem.fileURL];
    OBASSERT(OBClassIsSubclassOfClass(cls, [OUIDocument class]));

    NSError *error = nil;
    OUIDocument *document = [[[cls alloc] initWithExistingFileItem:fileItem error:&error] autorelease];
    if (!document) {
        OUI_PRESENT_ERROR(error);
        return NO;
    }
    
    [document openWithCompletionHandler:^(BOOL success){
        OBFinishPortingLater("Need to deal with errors in the read path, possibly by storing them on the document instance");
        [self _mainThread_finishedLoadingDocument:document animation:animation];
    }];
    
    return YES;
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

- (void)_fileItemViewFinishedLoadingPreviews:(OUIDocumentPickerFileItemView *)fileItemView;
{
    OBPRECONDITION(fileItemView != nil);
    OBPRECONDITION(_document.fileItem == fileItemView.item);
    
    UIView *documentView = [self pickerAnimationViewForTarget:_document];
    [_mainViewController setInnerViewController:self.documentPicker animated:YES
                                     fromRegion:^(UIView **outView, CGRect *outRect) {
                                         *outView = documentView;
                                         *outRect = CGRectZero;
                                     } toRegion:^(UIView **outView, CGRect *outRect) {
                                         *outView = fileItemView.previewView;
                                         *outRect = CGRectZero;
                                     } transitionAction:^{
                                         [self.documentPicker rescanDocumentsScrollingToURL:_document.fileItem.fileURL animated:NO];
                                     }];

    [self _setDocument:nil];
    
    // Start updating the previews for any other documents that were edited and have had incoming iCloud changes invalidate their previews.
    [self _continueUpdatingPreviewsOrOpenDocument];
}

- (void)_fileItemViewFinishedLoadingPreviewsNotification:(NSNotification *)note;
{
    OUIDocumentPickerFileItemView *fileItemView = [note object];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:OUIDocumentPickerItemViewPreviewsDidLoadNotification object:fileItemView];
    [self _fileItemViewFinishedLoadingPreviews:fileItemView];
}

- (void)_fileItemContentsChanged:(NSNotification *)note;
{
    OBPRECONDITION([NSThread isMainThread]);
    OBPRECONDITION([note object] == _documentStore);
    
    // We'll want to have an operation queue / interlock with opening documents so that we only have one document opening at a time (between the preview updating and real document opening).
    // Doing something hacky for some to have something to improve upon.
    OUIDocumentStoreFileItem *fileItem = [[note userInfo] objectForKey:OUIDocumentStoreFileItemInfoKey];
    OBASSERT([fileItem isKindOfClass:[OUIDocumentStoreFileItem class]]);
    
    // If we have an open document (the document picker isn't visible), just ignore this. The process of closing a document will update its preview and once we become visible we'll check for other previews that need to be updated.
    if (_document && _document.fileItem == fileItem)
        return;
    
    // We can get notified for a file multiple times in one update. There is a race condition if we get another update while we are generating the preview. We should ideally write the preview with the time stamp of the file when we were reading it, not the time we finished building the preview...
    OBFinishPortingLater("Include the -modificationDate of the current NSFileVersion in the preview name for iCloud documents, or maybe the sha-1 of the NSCoded data of its -persistentIdentifier");
    
    if ([_fileItemsNeedingUpdatedPreviews member:fileItem] == nil) {
        PREVIEW_DEBUG(@"Queueing preview update of %@", fileItem.fileURL);
        if (!_fileItemsNeedingUpdatedPreviews)
            _fileItemsNeedingUpdatedPreviews = [[NSMutableSet alloc] init];
        [_fileItemsNeedingUpdatedPreviews addObject:fileItem];
        
        if (_document == nil) // Start updating previews immediately if there is no open document. Otherwise, queue them until the document is closed
            [self _continueUpdatingPreviewsOrOpenDocument];
    }
}

- (void)_continueUpdatingPreviewsOrOpenDocument;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    if (_currentPreviewUpdatingFileItem)
        return; // Already updating one. When this finishes, this method will be called again
    
    // If the user tapped on a document while a preview was happening, we'll have delayed that action until the current preview update finishes (to avoid having two documents open at once and possibliy running out of memory).
    if (_fileItemToOpenAfterCurrentPreviewUpdateFinishes) {
        PREVIEW_DEBUG(@"Performing delayed open of document at %@", _fileItemToOpenAfterCurrentPreviewUpdateFinishes.fileURL);

        OUIDocumentStoreFileItem *fileItem = [_fileItemToOpenAfterCurrentPreviewUpdateFinishes autorelease];
        _fileItemToOpenAfterCurrentPreviewUpdateFinishes = nil;
        [self _documentPickerOpenDocumentAction:fileItem];
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
    
    [document openWithCompletionHandler:^(BOOL success){
        OBASSERT([NSThread isMainThread]);
        
        OUIDocumentStoreFileItem *fileItem = [_currentPreviewUpdatingFileItem autorelease];
        _currentPreviewUpdatingFileItem = nil;

        OBASSERT([_fileItemsNeedingUpdatedPreviews member:fileItem] == fileItem);
        [_fileItemsNeedingUpdatedPreviews removeObject:fileItem];

        
        if (success) {
            [document _writePreviewsIfNeeded:YES];
            
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

