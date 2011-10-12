// Copyright 2010-2011 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIDocument.h>

#import <OmniFoundation/NSFileManager-OFSimpleExtensions.h>
#import <OmniUI/OUIAlertView.h>
#import <OmniUI/OUIDocumentPicker.h>
#import <OmniUI/OUIDocumentPreview.h>
#import <OmniUI/OUIDocumentStoreFileItem.h>
#import <OmniUI/OUIDocumentViewController.h>
#import <OmniUI/OUIErrors.h>
#import <OmniUI/OUIInspector.h>
#import <OmniUI/OUIMainViewController.h>
#import <OmniUI/OUISingleDocumentAppController.h>
#import <OmniUI/OUIUndoIndicator.h>
#import <OmniUI/UIView-OUIExtensions.h>

#import "OUIDocumentStore-Internal.h"
#import "OUIDocumentStoreFileItem-Internal.h"
#import "OUIDocument-Internal.h"
#import <OmniFileStore/OFSFileManager.h>

RCS_ID("$Id$");

#if 0 && defined(DEBUG)
    #define DEBUG_UNDO(format, ...) NSLog(@"UNDO: " format, ## __VA_ARGS__)
#else
    #define DEBUG_UNDO(format, ...)
#endif

// OUIDocument
OBDEPRECATED_METHOD(-saveToURL:isAutosave:error:); // -writeToURL:forSaveType:error:
OBDEPRECATED_METHOD(-loadDocumentContents:); // -[UIDocument loadFromContents:ofType:error:]
OBDEPRECATED_METHOD(-writeToURL:forSaveType:error:); // -[UIDocument contentsForType:error:]
OBDEPRECATED_METHOD(-willAutosave);
OBDEPRECATED_METHOD(-initWithExistingDocumentProxy:error:); // -initWithExistingFileItem:error:

// OUIDocumentViewController
OBDEPRECATED_METHOD(-documentWillAutosave); // -documentWillSave

@interface OUIDocument (/*Private*/)
+ (NSURL *)_previewDirectoryURL;
- _initWithFileItem:(OUIDocumentStoreFileItem *)fileItem url:(NSURL *)url error:(NSError **)outError;
- (void)_willSave;
- (void)_updateUndoIndicator;
- (void)_undoManagerDidUndo:(NSNotification *)note;
- (void)_undoManagerDidRedo:(NSNotification *)note;
- (void)_undoManagerDidOpenGroup:(NSNotification *)note;
- (void)_undoManagerWillCloseGroup:(NSNotification *)note;
- (void)_undoManagerDidCloseGroup:(NSNotification *)note;
@end

@implementation OUIDocument
{
@private
    OUIDocumentStoreFileItem *_fileItem;
    
    UIViewController <OUIDocumentViewController> *_viewController;
    OUIUndoIndicator *_undoIndicator;
    
    BOOL _hasUndoGroupOpen;
    BOOL _isClosing;
    
    id _rebuildingViewControllerState;
}

+ (BOOL)shouldShowAutosaveIndicator;
{
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"OUIDocumentShouldShowAutosaveIndicator"];
}

// existing document
- initWithExistingFileItem:(OUIDocumentStoreFileItem *)fileItem error:(NSError **)outError;
{
    OBPRECONDITION(fileItem);
    OBPRECONDITION(fileItem.fileURL);
    
    return [self _initWithFileItem:fileItem url:fileItem.fileURL error:outError];
}

- initEmptyDocumentToBeSavedToURL:(NSURL *)url error:(NSError **)outError;
{
    OBPRECONDITION(url);
    
    if (!(self = [self _initWithFileItem:nil url:url error:outError]))
        return nil;
    
    // Mark ourselves as needing saving
    [self updateChangeCount:UIDocumentChangeDone];
    
    return self;
}

- _initWithFileItem:(OUIDocumentStoreFileItem *)fileItem url:(NSURL *)url error:(NSError **)outError;
{
    OBPRECONDITION(fileItem || url);
    OBPRECONDITION(!fileItem || [fileItem.fileURL isEqual:url]);
    
    if (!(self = [super initWithFileURL:url]))
        return nil;
    
    _fileItem = [fileItem retain];
    
    OBASSERT_NOT_IMPLEMENTED(self, setProxy:); // We no longer call this 'proxy' and we now update file item URLs via NSFilePresenter now so we don't need to swap them out.
    OBASSERT_NOT_IMPLEMENTED(self, proxyURLChanged); // Finds out via NSFilePresenter

    // When groups fall off the end of this limit and deallocate objects inside them, those objects come back and try to remove themselves from the undo manager.  This asplodes.
    // <bug://bugs/60414> (Crash in [NSUndoManager removeAllActionsWithTarget:])
#if 0
    NSInteger levelsOfUndo = [[NSUserDefaults standardUserDefaults] integerForKey:@"LevelsOfUndo"];
    if (levelsOfUndo <= 0)
        levelsOfUndo = 10;
    [_undoManager setLevelsOfUndo:levelsOfUndo];
#endif

    /*
     We want to be able to break undo groups up manually as best fits our UI and we want to reliably capture selection state at the beginning/end of undo groups. So, we sign up for undo manager notifications to create nested groups, but we let UIDocument manage the -updateChangeCount: (it will only send UIDocumentChangeDone when the top-level group is closed).
     */
    
    NSUndoManager *undoManager = [[NSUndoManager alloc] init];
    
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    
    [center addObserver:self selector:@selector(_undoManagerDidUndo:) name:NSUndoManagerDidUndoChangeNotification object:undoManager];
    [center addObserver:self selector:@selector(_undoManagerDidRedo:) name:NSUndoManagerDidRedoChangeNotification object:undoManager];
    
    [center addObserver:self selector:@selector(_undoManagerDidOpenGroup:) name:NSUndoManagerDidOpenUndoGroupNotification object:undoManager];
    [center addObserver:self selector:@selector(_undoManagerWillCloseGroup:) name:NSUndoManagerWillCloseUndoGroupNotification object:undoManager];
    [center addObserver:self selector:@selector(_undoManagerDidCloseGroup:) name:NSUndoManagerDidCloseUndoGroupNotification object:undoManager];
    
    [center addObserver:self selector:@selector(_inspectorDidEndChangingInspectedObjects:) name:OUIInspectorDidEndChangingInspectedObjectsNotification object:nil];
    
    self.undoManager = undoManager;
    [undoManager release];
    
    return self;
}

- (void)dealloc;
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    _viewController.document = nil;
    
    // UIView cannot get torn down on background threads. Capture these in locals to avoid the block doing a -retain on us while we are in -dealloc
    UIViewController *viewController = _viewController;
    _viewController = nil;
    
    OUIUndoIndicator *undoIndicator = _undoIndicator;
    _undoIndicator = nil;
    
    main_sync(^{
        [viewController release];
        [undoIndicator release];
    });
    
    [_fileItem release];
    [_rebuildingViewControllerState release];
    
    [super dealloc];
}

@synthesize fileItem = _fileItem;

@synthesize viewController = _viewController;

- (BOOL)saveAsNewDocumentToURL:(NSURL *)url error:(NSError **)outError;
{
    OBFinishPorting;
#if 0
    OBPRECONDITION(_url == nil || [_url isEqual:url]);
    OBPRECONDITION(_fileItem == nil);
    return [self _writeToURL:url forSaveType:OFSaveTypeNew error:outError];
#endif
}

- (void)finishUndoGroup;
{
    if (!_hasUndoGroupOpen)
        return; // Nothing to do!
    
    DEBUG_UNDO(@"finishUndoGroup");

    if ([_viewController respondsToSelector:@selector(documentWillCloseUndoGroup)])
        [_viewController documentWillCloseUndoGroup];
    
    [self willFinishUndoGroup];
    
    // Our group might be the only one open, but the auto-created group might be open still too (for example, with a single-event action like -delete:)
    OBASSERT([self.undoManager groupingLevel] >= 1);
    _hasUndoGroupOpen = NO;
    
    // This should drop the count to zero, provoking an -updateChangeCount:UIDocumentChangeDone
    [self.undoManager endUndoGrouping];
}

- (IBAction)undo:(id)sender;
{
    if (![self shouldUndo])
        return;
    
    // Make sure any edits get finished and saved in the current undo group
    OUIWithoutAnimating(^{
        [_viewController.view.window endEditing:YES/*force*/];
        [_viewController.view layoutIfNeeded];
    });
    
    [self finishUndoGroup]; // close any nested group we created
    
    [self.undoManager undo];
    
    [self didUndo];
}

- (IBAction)redo:(id)sender;
{
    if (![self shouldRedo])
        return;
    
    // Make sure any edits get finished and saved in the current undo group
    [_viewController.view.window endEditing:YES/*force*/];
    [self finishUndoGroup]; // close any nested group we created
    
    [self.undoManager redo];
    
    [self didRedo];
}

- (void)scheduleAutosave;
{
    [self updateChangeCount:UIDocumentChangeDone];
}

- (void)willClose;
{
    // For subclasses
}

#pragma mark -
#pragma mark UIDocument subclass

- (BOOL)hasUnsavedChanges;
{
    BOOL result = [super hasUnsavedChanges];
    DEBUG_DOCUMENT(@"%@ %@ hasUnsavedChanges -> %d", [self shortDescription], NSStringFromSelector(_cmd), result);
    return result;
}

- (void)updateChangeCount:(UIDocumentChangeKind)change;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    DEBUG_DOCUMENT(@"%@ %@ %ld", [self shortDescription], NSStringFromSelector(_cmd), change);
    
    // This registers the autosave timer
    [super updateChangeCount:change];
    
    if (change != UIDocumentChangeCleared) {
        [[[OUIAppController controller] undoBarButtonItem] setEnabled:[self.undoManager canUndo] || [self.undoManager canRedo]];
    }
    
    [self _updateUndoIndicator];
}

- (id)changeCountTokenForSaveOperation:(UIDocumentSaveOperation)saveOperation;
{
    OBPRECONDITION([NSThread isMainThread]);
    //OBPRECONDITION(saveOperation == UIDocumentSaveForOverwriting); // UIDocumentSaveForCreating for saving when we get getting saved to the ".ubd" dustbin during -accommodatePresentedItemDeletionWithCompletionHandler:
    
    id token = [super changeCountTokenForSaveOperation:saveOperation];
    
    DEBUG_DOCUMENT(@"%@ %@ changeCountTokenForSaveOperation:%ld -> %@ %@", [self shortDescription], NSStringFromSelector(_cmd), saveOperation, [token class], token);
    return token;
}

- (void)updateChangeCountWithToken:(id)changeCountToken forSaveOperation:(UIDocumentSaveOperation)saveOperation;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    DEBUG_DOCUMENT(@"%@ %@ updateChangeCountWithToken:%@ forSaveOperation:%ld", [self shortDescription], NSStringFromSelector(_cmd), changeCountToken, saveOperation);
    
    [super updateChangeCountWithToken:changeCountToken forSaveOperation:saveOperation];
}

- (void)openWithCompletionHandler:(void (^)(BOOL success))completionHandler;
{
    DEBUG_DOCUMENT(@"%@ %@", [self shortDescription], NSStringFromSelector(_cmd));

#ifdef OMNI_ASSERTIONS_ON
    // We don't want opening the document to provoke download -- we should provoke that earlier and only open when it is fully downloaded
    {
        OBASSERT(_fileItem);
        OBASSERT(_fileItem.isDownloaded);
    }
#endif
    
    /*
     The "simple" read path does the read on a background queue but does the transform from the read contents to the object model (-loadFromContents:ofType:error:) on the same thread that this method was called on. So we could either continue managing our own background thread, or we could use the advanced API (-readFromURL:error:) which already gets run in the background thread.
     
     Additionally, the simple API loads the entire file wrapper, which we likely don't want (for attachments). So, we'll mandate that OUIDocuments need to use the advanced API, since we were loading the document model in background thread anyway and so that we can load attachments lazily.
     
     To do the lazy attachment loading, we need to use -performAsynchronousFileAccessUsingBlock: to get onto the background reading queue and we need to do a coordinated read in the block to take out a read lock vs. ubiquity.
     
     */
#ifdef OMNI_ASSERTIONS_ON
    {
        // Have to implement the read API
        Class readClass = OBClassImplementingMethod([self class], @selector(readFromURL:error:));
        OBASSERT(readClass);
        OBASSERT(readClass != [UIDocument class]);

        // and one of the write APIs
        Class writeSafelyClass = OBClassImplementingMethod([self class], @selector(writeContents:andAttributes:safelyToURL:forSaveOperation:error:));
        Class writeRawClass = OBClassImplementingMethod([self class], @selector(writeContents:toURL:forSaveOperation:originalContentsURL:error:));
        
        OBASSERT(writeSafelyClass || writeRawClass);
        OBASSERT((writeSafelyClass != [UIDocument class]) || (writeRawClass != [UIDocument class]));
    }
#endif
    
    [super openWithCompletionHandler:^(BOOL success){
        DEBUG_DOCUMENT(@"%@ %@ success %d", [self shortDescription], NSStringFromSelector(_cmd), success);
        if (success) {
            
            OBASSERT(_viewController == nil);
            _viewController = [[self makeViewController] retain];
            OBASSERT([_viewController conformsToProtocol:@protocol(OUIDocumentViewController)]);
            OBASSERT(_viewController.document == nil); // we'll set it; -makeViewController shouldn't bother
            _viewController.document = self;
            
            // clear out any undo actions created during init
            [self.undoManager removeAllActions];
            
            // this implicitly kills any groups; make sure our flag gets cleared too.
            OBASSERT([self.undoManager groupingLevel] == 0);
            _hasUndoGroupOpen = NO;
        }
        
        completionHandler(success);
    }];
}

- (void)closeWithCompletionHandler:(void (^)(BOOL success))completionHandler;
{
    DEBUG_DOCUMENT(@"%@ %@", [self shortDescription], NSStringFromSelector(_cmd));

    OUIWithoutAnimating(^{
        // If the user is just switching to another app quickly and coming right back (maybe to paste something at us), we don't want to end editing.
        // Instead, we should commit any partial edits, but leave the editor up.
        
        [self _willSave];
        //[_window endEditing:YES];
        
        UIWindow *window = [[OUISingleDocumentAppController controller] window];
        [window layoutIfNeeded];
        
        // Make sure -setNeedsDisplay calls (provoked by -_willSave) have a chance to get flushed before we invalidate the document contents
        OUIDisplayNeededViews();
    });

    if (_hasUndoGroupOpen) {
        OBASSERT([self.undoManager groupingLevel] == 1);
        [self.undoManager endUndoGrouping];
    }
    
    BOOL hadChanges = [self hasUnsavedChanges];
    
    // The closing path will save using the autosaveWithCompletionHandler:. We need to be able to tell if we should do a real full non-autosave write though.
    OBASSERT(_isClosing == NO);
    _isClosing = YES;
    
    [super closeWithCompletionHandler:^(BOOL success){
        DEBUG_DOCUMENT(@"%@ %@ success %d", [self shortDescription], NSStringFromSelector(_cmd), success);

        [self _updateUndoIndicator];
        
        if (_fileItem) { // New document being closed to save its initial state before being opened to edit?
            
            // Update the date, in case we were written.
            _fileItem.date = self.fileModificationDate;
            
            // The date refresh is asynchronous, so we'll force preview loading in the case that we know we should consider the previews out of date.
            [self _writePreviewsIfNeeded:(hadChanges == NO)];
        }
        
        OBASSERT(_isClosing == YES);
        _isClosing = NO;
        
        if (completionHandler)
            completionHandler(success);
    }];
}

/*
 NOTE: This method does not always get called for UIDocument initiated saves. For example, if you make a change (calling -updateChangeCount:) and then pretty the power button to lock the screen, -hasUnsavedChanges is called and then the document is written directly, rather than calling the autosave method.
 
 Also, we cannot defer autosaving. If we just call completionHandler(NO), the autosave timer doesn't get rescheduled immediately.
 */
- (void)autosaveWithCompletionHandler:(void (^)(BOOL))completionHandler;
{
    OBPRECONDITION([self hasUnsavedChanges]);
    OBPRECONDITION(![self.undoManager isUndoing]);
    OBPRECONDITION(![self.undoManager isRedoing]);
    
    DEBUG_UNDO(@"Autosave running...");

    [self _willSave];

    [super autosaveWithCompletionHandler:^(BOOL success){
        DEBUG_UNDO(@"  Autosave success = %d", success);
        
        // Do this *after* our possible preview saving. We may be getting called by the -closeWithCompletionHandler: where the completion block might invalidate some of the document state.
        if (completionHandler)
            completionHandler(success);

        [self _updateUndoIndicator];
    }];
}

- (void)saveToURL:(NSURL *)url forSaveOperation:(UIDocumentSaveOperation)saveOperation completionHandler:(void (^)(BOOL success))completionHandler;
{
    DEBUG_DOCUMENT(@"Save with operation %ld to %@", saveOperation, [url absoluteString]);
    
    OBASSERT(![[[[url path] stringByDeletingLastPathComponent] lastPathComponent] isEqualToString:@"Inbox"]);
    
    [super saveToURL:url forSaveOperation:saveOperation completionHandler:^(BOOL success){
        DEBUG_DOCUMENT(@"  save success %d", success);
        if (completionHandler)
            completionHandler(success);
    }];
}

- (void)disableEditing;
{
    OBPRECONDITION([NSThread isMainThread]);
    OBPRECONDITION(_rebuildingViewControllerState == nil);
    
    DEBUG_DOCUMENT(@"Disable editing");
    
    // Incoming edit from iCloud, most likely. We should have been asked to save already via the coordinated write (might produce a conflict). Still, lets make sure we aren't editing.
    [_viewController.view endEditing:YES];
    
    [[UIApplication sharedApplication] beginIgnoringInteractionEvents];
}

- (void)enableEditing;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    DEBUG_DOCUMENT(@"Enable editing");

    [[UIApplication sharedApplication] endIgnoringInteractionEvents];
}

- (void)handleError:(NSError *)error userInteractionPermitted:(BOOL)userInteractionPermitted;
{
    DEBUG_DOCUMENT(@"Handle error with user interaction:%d: %@", userInteractionPermitted, [error toPropertyList]);

    if (userInteractionPermitted)
        OUI_PRESENT_ALERT(error);
    [self finishedHandlingError:error recovered:NO];
}

- (void)userInteractionNoLongerPermittedForError:(NSError *)error;
{
    // Since we subclass -handleError:userInteractionPermitted:, we have to implement this too, according to the documentation.
    DEBUG_DOCUMENT(@"%s:%d -- %s", __FILE__, __LINE__, __PRETTY_FUNCTION__);
    [super userInteractionNoLongerPermittedForError:error];
}

- (void)revertToContentsOfURL:(NSURL *)url completionHandler:(void (^)(BOOL success))completionHandler;
{
    OBPRECONDITION([NSThread isMainThread]);
    OBPRECONDITION(_rebuildingViewControllerState == nil);

    [_rebuildingViewControllerState release];
    _rebuildingViewControllerState = [[self willRebuildViewController] retain];

    // Incoming edit from iCloud, most likely. We should have been asked to save already via the coordinated write (might produce a conflict). Still, lets abort editing.
    [_viewController.view endEditing:YES];

    // Forget our view controller since UIDocument's reloading will call -openWithCompletionHandler: again and we'll make a new view controller
    // Note; doing a view controller rebuild via -relinquishPresentedItemToWriter: seems hard/impossible not only due to the crazy spaghetti mess of blocks but also because it is invoked on UIDocument's background thread, while we need to mess with UIViews.
    UIViewController <OUIDocumentViewController> *oldViewController = [_viewController autorelease];
    _viewController = nil;
    oldViewController.document = nil;

    completionHandler = [[completionHandler copy] autorelease];
    
    OBFinishPortingLater("Use this when doing incorporation of remote changes.");
    [super revertToContentsOfURL:url completionHandler:^(BOOL success){
        if (completionHandler)
            completionHandler(success);
        
        if (!success) {
            OBFinishPorting; // Close the document and go back to the picker?
        } else {
            OBASSERT([NSThread isMainThread]);

            // We should have a re-built view controller now, but it isn't on screen yet
            OBASSERT(_viewController);
            OBASSERT(_viewController.document == self);
            OBASSERT(![_viewController isViewLoaded] || _viewController.view.window == nil);
            
            id state = [_rebuildingViewControllerState autorelease];
            _rebuildingViewControllerState = nil;
            [self didRebuildViewController:state];
            
            OUISingleDocumentAppController *controller = [OUISingleDocumentAppController controller];
            OUIMainViewController *mainViewController = controller.mainViewController;
            [mainViewController setInnerViewController:_viewController animated:YES fromView:nil toView:nil];
            
            if (self.documentState & UIDocumentStateInConflict) {
                // We are getting reloaded from the auto-nominated file version. OUISingleDocumentAppController will be running the conflict resolution sheet, so the user already knows something is going on and we shouldn't annoy them here.
            } else {
                NSFileVersion *currentVersion = [NSFileVersion currentVersionOfItemAtURL:self.fileURL];
                
                NSString *messageFormat = NSLocalizedStringFromTableInBundle(@"Last edited on %@.", @"OmniUI", OMNI_BUNDLE, @"Message format for alert informing user that the document has been reloaded with iCloud edits from another device");
                NSString *message = [NSString stringWithFormat:messageFormat, currentVersion.localizedNameOfSavingComputer];
                
                message = [message stringByAppendingFormat:@"\n%@", [OUIDocumentStoreFileItem displayStringForDate:currentVersion.modificationDate]];
                
                UIAlertView *alert = [[UIAlertView alloc] initWithTitle:[self alertTitleForIncomingEdit]
                                                                message:message delegate:message cancelButtonTitle:@"OK" otherButtonTitles:nil];
                [alert show];
                [alert release];
            }
        }
    }];
}

#pragma mark -
#pragma mark NSFilePresenter

- (void)accommodatePresentedItemDeletionWithCompletionHandler:(void (^)(NSError *errorOrNil))completionHandler;
{
    OBPRECONDITION(![NSThread isMainThread]);
    
    NSURL *originalFileURL = [[self.fileURL copy] autorelease];
    
    [super accommodatePresentedItemDeletionWithCompletionHandler:^(NSError *errorOrNil){
        OBASSERT(![NSThread isMainThread]);

        if (completionHandler)
            completionHandler(errorOrNil);

        // By this point, our document has been moved to a ".ubd" Dead Zone, but the docuemnt is still open and pointing at that dead file.
        main_async(^{
            // The user has already chosen to delete this document elsewhere, so Delete is the "no action"/"cancel" button.
            OUIAlertView *alert = [[OUIAlertView alloc] initWithTitle:NSLocalizedStringFromTableInBundle(@"Document Deleted in\nAnother Location", @"OmniUI", OMNI_BUNDLE, @"alert view title")
                                                              message:NSLocalizedStringFromTableInBundle(@"If you keep it, it will remain stored in iCloud.", @"OmniUI", OMNI_BUNDLE, @"alert view message")
                                                    cancelButtonTitle:NSLocalizedStringFromTableInBundle(@"Delete", @"OmniUI", OMNI_BUNDLE, @"alert button title")
                                                         cancelAction:^{
                                                             // The document is already deleted. Just close!
                                                             OBFinishPortingLater("The document picker should have to preview for this -- we should just fade out or somewhat.");
                                                             [[OUISingleDocumentAppController controller] closeDocument:nil];
                                                         }];
            [alert addButtonWithTitle:NSLocalizedStringFromTableInBundle(@"Keep", @"OmniUI", OMNI_BUNDLE, @"alert button title")
                               action:^{
                                   [self saveToURL:originalFileURL forSaveOperation:UIDocumentSaveForCreating completionHandler:^(BOOL success){
                                       OBFinishPortingLater("Can we just coordinated move the dead file back?");
                                       OBFinishPortingLater("Handle errors");
                                       NSLog(@"resaved %d, fileURL %@", success, [self fileURL]);
                                   }];
                               }];
            [alert show];
            [alert release];
        });
    }];
}

#pragma mark -
#pragma mark Subclass responsibility

- (UIViewController <OUIDocumentViewController> *)makeViewController;
{
    OBRequestConcreteImplementation(self, _cmd);
}

#pragma mark -
#pragma mark Optional subclass methods

- (void)willFinishUndoGroup;
{
}

- (BOOL)shouldUndo;
{
    return YES;
}

- (BOOL)shouldRedo;
{
    return YES;
}

- (void)didUndo;
{
}

- (void)didRedo;
{
}

- (UIView *)viewToMakeFirstResponderWhenInspectorCloses;
{
    return _viewController.view;
}

- (NSString *)alertTitleForIncomingEdit;
{
    return NSLocalizedStringFromTableInBundle(@"Document Updated", @"OmniUI", OMNI_BUNDLE, @"Title for alert informing user that the document has been reloaded with iCloud edits from another device");
}

- (id)willRebuildViewController;
{
    return nil;
}

- (void)didRebuildViewController:(id)state;
{
}

#pragma mark -
#pragma mark Preview support

static BOOL _isValidPreviewURL(NSURL *url, NSDate *fileDate)
{
    if (!url)
        return NO; // New document or otherwise don't know where to put the preview.
    
    NSError *error = nil;
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:[url path] error:&error];
    if (!attributes) {
        if (![error hasUnderlyingErrorDomain:NSPOSIXErrorDomain code:ENOENT])
            NSLog(@"Unable to get attributes of %@: %@", [url absoluteString], [error toPropertyList]);
        return NO;
    }
    
    // We treat zero-length preview files as 'valid' so that we don't try to regenerate previews for files that cause the app to crash when generating previews. Still might crash each time we open/edit/close them in this edge case, though...
    return OFISEQUAL([attributes fileType], NSFileTypeRegular) && ([[attributes fileModificationDate] compare:fileDate] != NSOrderedAscending);
}

static BOOL _previewsValidForDate(Class self, OUIDocumentStoreFileItem *fileItem, NSDate *date)
{
    return _isValidPreviewURL([self fileURLForPreviewOfFileItem:fileItem withLandscape:YES], date) && _isValidPreviewURL([self fileURLForPreviewOfFileItem:fileItem withLandscape:NO], date);
}

+ (CGSize)previewSizeForTargetSize:(CGSize)targetSize aspectRatio:(CGFloat)aspectRatio;
{
    // Aspect radio is w/h. Assume the preview has h=1, then its width is the aspect ratio. We can then figure out the max scale factor in each direction.
    CGFloat previewWidth = aspectRatio;
    CGFloat previewHeight = 1;
    
    CGFloat widthScale = targetSize.width/previewWidth;
    CGFloat heightScale = targetSize.height/previewHeight;
    CGFloat scale = MIN(widthScale, heightScale);
    
    CGSize size = CGSizeMake(previewWidth * scale, previewHeight * scale);
    
    return size;
}

+ (NSURL *)fileURLForPreviewOfFileItem:(OUIDocumentStoreFileItem *)fileItem withLandscape:(BOOL)landscape;
{
    OBPRECONDITION(fileItem);

    NSURL *directoryURL = [self _previewDirectoryURL];
    
    NSURL *fileURL = fileItem.fileURL;
    if (!fileURL)
        return nil; // New documents won't have this.
    
    // We need to keep the file extension here! We could have Foo.oo3 and Foo.opml and they might have different previews
    NSString *fileName = [fileItem.fileURL lastPathComponent];
    
    fileName = [fileName stringByAppendingPathExtension:landscape ? @"landscape" : @"portrait"];
    fileName = [fileName stringByAppendingPathExtension:@"png"];
    
    return [[directoryURL URLByAppendingPathComponent:fileName] absoluteURL];
}

+ (OUIDocumentPreview *)loadPreviewForFileItem:(OUIDocumentStoreFileItem *)fileItem withLandscape:(BOOL)landscape error:(NSError **)outError;
{
    UIImage *image = nil;
    NSDate *date = nil;
    OUIDocumentPreviewType type = OUIDocumentPreviewTypeEmpty;
    
    do {
        NSURL *previewURL = [self fileURLForPreviewOfFileItem:fileItem withLandscape:landscape];
        if (!previewURL)
            break;
        
        NSError *error = nil;
        NSData *data = [[NSData alloc] initWithContentsOfURL:previewURL options:NSDataReadingUncached error:&error];
        if (!data) {
            if ([error hasUnderlyingErrorDomain:NSPOSIXErrorDomain code:ENOENT])
                type = OUIDocumentPreviewTypePlaceholder;
            else
                NSLog(@"Unable to load preview for %@: %@", [self shortDescription], [error toPropertyList]);
            break;
        }
        if (![data length]) {
            // Placeholder marker written to avoid repeated crashing
            [data release];
            break;
        }
        
        NSError *resourceError = nil;
        if (![previewURL getResourceValue:&date forKey:NSURLContentModificationDateKey error:&resourceError]) {
            NSLog(@"Error getting modification date for %@: %@", [previewURL absoluteString], [resourceError toPropertyList]);
            date = [NSDate date];
        }
        
        image = [[[UIImage alloc] initWithData:data] autorelease];
        [data release];
        if (!image) {
            NSLog(@"Unable to create preview image from contents of %@", previewURL);
            break;
        }
        
        type = OUIDocumentPreviewTypeRegular;
    } while (0);
    
    if (!image) {
        image = [self placeholderPreviewImageForFileItem:fileItem landscape:landscape];
        date = [fileItem date];
        OBASSERT(image); // Probably not worth adding an OmniUI global default image; the preview view can just draw a white square
    }
    
    return [[[OUIDocumentPreview alloc] initWithFileItem:fileItem date:date image:image landscape:landscape type:type] autorelease];
}

+ (UIImage *)placeholderPreviewImageForFileItem:(OUIDocumentStoreFileItem *)fileItem landscape:(BOOL)landscape;
{
    OBRequestConcreteImplementation(self, _cmd);
}

+ (BOOL)writePreviewsForDocument:(OUIDocument *)document error:(NSError **)outError;
{
    // Subclass responsibility
    OBRequestConcreteImplementation(self, _cmd);
}


+ (UIImage *)cameraRollImageForFileItem:(OUIDocumentStoreFileItem *)fileItem;
{
    OBFinishPorting;
#if 0
    // Use the default behavior of drawing the document's preview.
    OUIDocumentPickerFileItemView *fileItemView = _view;
    
    CGSize maxSize = self.view.window.bounds.size; // This is the portrait size always
    if (UIDeviceOrientationIsLandscape([[UIDevice currentDevice] orientation]))
        SWAP(maxSize.width, maxSize.height);
    
    UIImage *result = nil;
    OUIDocumentPreview *preview = fileItemView.preview;
    
    if ([preview isKindOfClass:[OUIDocumentPDFPreview class]]) {
        OUIDocumentPDFPreview *pdfPreview = (OUIDocumentPDFPreview *)preview;
        
        CGRect maxBounds = CGRectMake(0, 0, maxSize.width, maxSize.height);
        
        CGAffineTransform xform = [pdfPreview transformForTargetRect:maxBounds preserveAspectRatio:YES];
        CGRect paperRect = pdfPreview.untransformedPageRect;
        CGRect transformedTarget = CGRectApplyAffineTransform(paperRect, xform);
        
        OUIGraphicsBeginImageContext(transformedTarget.size);
        {
            CGContextRef ctx = UIGraphicsGetCurrentContext();
            
            OQFlipVerticallyInRect(ctx, CGRectMake(0, 0, transformedTarget.size.width, transformedTarget.size.height)); // flip w/in the image
            CGContextTranslateCTM(ctx, -transformedTarget.origin.x, -transformedTarget.origin.y); // the sizing transform centers us in the original rect we gave, but we ended up giving a smaller rect to just fit the content.
            CGContextConcatCTM(ctx, xform); // size the page to the target rect we wanted
            
            // Fill the background with white in case the PDF doesn't have an embedded background color.
            CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceGray();
            CGFloat whiteComponents[] = {1.0, 1.0};
            CGColorRef white = CGColorCreate(colorSpace, whiteComponents);
            CGContextSetFillColorWithColor(ctx, white);
            CGColorRelease(white);
            CGColorSpaceRelease(colorSpace);
            CGContextFillRect(ctx, paperRect);
            
            // the PDF is happy to draw outside its page rect.
            CGContextAddRect(ctx, paperRect);
            CGContextClip(ctx);
            
            [pdfPreview drawInTransformedContext:ctx];
            
            result = UIGraphicsGetImageFromCurrentImageContext();
        }
        OUIGraphicsEndImageContext();
    } else {
        result = preview.cachedImage;
    }
    
    return result;
#endif
}

#pragma mark -
#pragma mark Internal

static void _writeEmptyPreview(OUIDocument *self, BOOL landscape)
{
    NSURL *previewURL = [[self class] fileURLForPreviewOfFileItem:self.fileItem withLandscape:landscape];
    NSError *error = nil;
    if (![[NSData data] writeToURL:previewURL options:0 error:&error])
        NSLog(@"Error writing empty data for preview to %@: %@", previewURL, [error toPropertyList]);
}

- (void)_writePreviewsIfNeeded:(BOOL)onlyIfNeeded;
{
    OBPRECONDITION([NSThread isMainThread]);
    OBPRECONDITION(_fileItem);
    // This doesn't work -- what we want is 'has been opened and has reasonable content'. When writing previews when closing and edited document, this will be UIDocumentStateClosed, but when writing previews due to an incoming iCloud change or document dragged in from iTunes, this will be UIDocumentStateNormal.
    //OBPRECONDITION(self.documentState == UIDocumentStateNormal);
    
    if (onlyIfNeeded && _previewsValidForDate([self class], _fileItem, _fileItem.date))
        return;
    
    // First, write an empty data file each preview, in case preview writing fails.
    _writeEmptyPreview(self, YES);
    _writeEmptyPreview(self, NO);
    
    PREVIEW_DEBUG(@"'%@' Writing previews", _fileItem.name);
    NSError *previewError = nil;
    if (![[self class] writePreviewsForDocument:self error:&previewError]) {
        NSLog(@"Error writing preview while closing %@: %@", [_fileItem.fileURL absoluteString], [previewError toPropertyList]);
    } else {
        // TODO: Remove the previews otherwise? Add timestamp validation when loading the previews?
    }
}

#pragma mark -
#pragma mark Private

+ (NSURL *)_previewDirectoryURL;
{
    static NSURL *previewDirectoryURL = nil;
    static dispatch_once_t onceToken;
    
    dispatch_once(&onceToken, ^{
        NSError *error = nil;
        
        NSFileManager *manager = [NSFileManager defaultManager];
        NSURL *caches = [manager URLForDirectory:NSCachesDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:YES error:&error];
        if (caches) {
            previewDirectoryURL = [[caches URLByAppendingPathComponent:@"DocumentPreviews"] retain];
            
            if (![manager directoryExistsAtPath:[[previewDirectoryURL absoluteURL] path]]) {
                if (![manager createDirectoryAtURL:previewDirectoryURL withIntermediateDirectories:NO attributes:nil error:&error]) {
                    [previewDirectoryURL release];
                    previewDirectoryURL = nil;
                }
            }
        }
        
        // TODO: Validate the previews vs. the version number of the app, or maybe a preview version number? Might be nice to rebuild the previews in the case that the app gets a new look. OTOH, maybe iTunes will torch our caches directory automatically on a version update.
        
        if (!previewDirectoryURL) {
            OBASSERT_NOT_REACHED("Unable to create caches directory!");
            NSLog(@"Unable to create preview image directory: %@", [error toPropertyList]);
        }
    });
    
    return previewDirectoryURL;
}

- (void)_willSave;
{
    BOOL hadUndoGroupOpen = _hasUndoGroupOpen;
    
    // This may make a new top level undo group that wouldn't get closed until after the autosave finishes and returns to the event loop. If we had no such top-level undo group before starting the save (we were idle in the event loop when an autosave or close fired up), we want to ensure our save operation also runs with a closed undo group (might be some app-specific logic in -willFinishUndoGroup that does additional edits).
    if ([_viewController respondsToSelector:@selector(documentWillSave)])
        [_viewController documentWillSave];
    
    // Close our nested group, if one was created and the view controller didn't call -finishUndoGroup itself.
    if (!hadUndoGroupOpen && _hasUndoGroupOpen)
        [self finishUndoGroup];
    
    // If there is still the automatically created group open, try to close it too since we haven't returned to the event loop. The model needs a consistent state and may perform delayed actions in undo group closing notifications.
    if (!_hasUndoGroupOpen && [self.undoManager groupingLevel] == 1) {
        // Terrible hack to let the by-event undo group close, plus a check that the hack worked...
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantPast]];
        OBASSERT(!_hasUndoGroupOpen);
    }
}

- (void)_updateUndoIndicator;
{
    if (!_undoIndicator && [[self class] shouldShowAutosaveIndicator] && [_viewController isViewLoaded])
        _undoIndicator = [[OUIUndoIndicator alloc] initWithParentView:_viewController.view];
    
    _undoIndicator.groupingLevel = [self.undoManager groupingLevel];
    _undoIndicator.hasUnsavedChanges = [self hasUnsavedChanges];
}

- (void)_undoManagerDidUndo:(NSNotification *)note;
{
    DEBUG_UNDO(@"%@ level:%ld", [note name], [self.undoManager groupingLevel]);
    [self _updateUndoIndicator];
}

- (void)_undoManagerDidRedo:(NSNotification *)note;
{
    DEBUG_UNDO(@"%@ level:%ld", [note name], [self.undoManager groupingLevel]);
    [self _updateUndoIndicator];
}

- (void)_undoManagerDidOpenGroup:(NSNotification *)note;
{
    DEBUG_UNDO(@"%@ level:%ld", [note name], [self.undoManager groupingLevel]);
    
    // Immediately open a nested group. This will allows NSUndoManager to automatically open groups for us on the first undo operation, but prevents it from closing the whole group.
    if ([self.undoManager groupingLevel] == 1) {
        DEBUG_UNDO(@"  ... nesting");
        _hasUndoGroupOpen = YES;
        [self.undoManager beginUndoGrouping];
        
        // Let our view controller know, if it cares (may be able to delete this now, graffle no longer uses it)
        if ([_viewController respondsToSelector:@selector(documentDidOpenUndoGroup)])
            [_viewController documentDidOpenUndoGroup];
        
        if ([[OUIAppController controller] respondsToSelector:@selector(documentDidOpenUndoGroup)])
            [[OUIAppController controller] performSelector:@selector(documentDidOpenUndoGroup)];
   }

    [self _updateUndoIndicator];
}

- (void)_undoManagerWillCloseGroup:(NSNotification *)note;
{
    DEBUG_UNDO(@"%@ level:%ld", [note name], [self.undoManager groupingLevel]);
    [self _updateUndoIndicator];
}

- (void)_undoManagerDidCloseGroup:(NSNotification *)note;
{
    DEBUG_UNDO(@"%@ level:%ld", [note name], [self.undoManager groupingLevel]);
    [self _updateUndoIndicator];
}

- (void)_inspectorDidEndChangingInspectedObjects:(NSNotification *)note;
{
    [self finishUndoGroup];
}

@end
