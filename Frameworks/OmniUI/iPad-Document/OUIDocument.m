// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUIDocument/OUIDocument.h>

#import <OmniFoundation/OmniFoundation.h>
#import <OmniDocumentStore/ODSStore.h>
#import <OmniDocumentStore/ODSScope.h>
#import <OmniDocumentStore/ODSFileItem.h>
#import <OmniDocumentStore/ODSUtilities.h>
#import <OmniFileExchange/OmniFileExchange.h>
#import <OmniUIDocument/OUIDocumentPreview.h>
#import <OmniUIDocument/OUIDocumentViewController.h>
#import <OmniUI/OUIInspector.h>
#import <OmniUIDocument/OUIDocumentAppController.h>
#import <OmniUI/OUIUndoIndicator.h>
#import <OmniUI/UIView-OUIExtensions.h>
#import <OmniUI/OUIShieldView.h>
#import <OmniUI/OUIPasswordAlert.h>
#import <OmniUI/OUIInteractionLock.h>

#import "OUIDocument-Internal.h"
#import "OUIDocumentAppController-Internal.h"

RCS_ID("$Id$");

#if 0 && defined(DEBUG)
    #define DEBUG_UNDO(format, ...) NSLog(@"UNDO: " format, ## __VA_ARGS__)
#else
    #define DEBUG_UNDO(format, ...)
#endif

OBDEPRECATED_METHOD(-initWithExistingFileItem:conflictFileVersion:error:); // Our syncing can't create conflict NSFileVersions, so we don't use NSFileVersion any more.
OBDEPRECATED_METHOD(+placeholderPreviewImageNameForFileURL:landscape:); // 'area'
OBDEPRECATED_METHOD(+placeholderPreviewImageNameForFileURL:area:); // we return an image now, so no 'Name' in selector

OBDEPRECATED_METHOD(-initWithExistingFileItemFromTemplate:error:);
OBDEPRECATED_METHOD(-initEmptyDocumentToBeSavedToURL:templateURL:error:);

NSString * const OUIDocumentPreviewsUpdatedForFileItemNotification = @"OUIDocumentPreviewsUpdatedForFileItemNotification";

#if DEBUG_DOCUMENT_DEFINED
#import <libkern/OSAtomic.h>
static int32_t OUIDocumentInstanceCount = 0;
#endif

@interface OUIDocument () <OUIShieldViewDelegate>
@property (nonatomic, readwrite, copy) NSString *lastQueuedUpdateMessage;
@property (nonatomic, strong) OUIShieldView *shieldView;
@end

@interface OUIDocument (/**NSUndoManager Observer*/)
@property (strong,nonatomic) NSUndoManager *observedUndoManager;
@end

@interface OUIDocument ()
@property (nonatomic) BOOL isDefinitelyClosing;
@end

OB_HIDDEN
@interface OUIDocumentEncryptionPassphrasePromptOperation : OFAsynchronousOperation
@property (weak) OUIDocument *document;
@property (readonly, strong) NSError *error;
@property (readonly, copy) NSString *password;
@end

@implementation OUIDocument
{
    ODSScope *_documentScope;

    UIViewController <OUIDocumentViewController> *_documentViewController;
    OUIUndoIndicator *_undoIndicator;
    
    void (^_savedCloseCompletionBlock)(BOOL success);
    
    BOOL _hasUndoGroupOpen;
    BOOL _isClosing;
    BOOL _forPreviewGeneration;
    BOOL _editingDisabled;
    BOOL _hasDisabledUserInteraction;
    
    id _rebuildingViewControllerState;
    
    NSUInteger _requestedViewStateChangeCount; // Used to augment the normal autosave.
    NSUInteger _savedViewStateChangeCount;
    
    CFAbsoluteTime _lastLocalRenameTime;
    
    BOOL _accommodatingDeletion;
    NSURL *_originalURLPriorToAccomodatingDeletion;
    
    BOOL _inRelinquishPresentedItemToWriter;
    NSURL *_originalURLPriorToPresentedItemDidMoveToURL;
    void (^_afterCloseRelinquishToWriter)(void (^reacquire)(void));
    
    // Used while saving a new document until the document scope has one for us.
    ODSFileItem *_transientFileItem;
    
    OFFileEdit *_lastWrittenFileEdit;
}

#if DEBUG_DOCUMENT_DEFINED
+ (id)allocWithZone:(NSZone *)zone;
{
    int32_t count = OSAtomicIncrement32Barrier(&OUIDocumentInstanceCount);
    OUIDocument *doc = [super allocWithZone:zone];
    DEBUG_DOCUMENT(@"ALLOC %p (count %d)", doc, count);
    return doc;
}
#endif

static NSString * const OUIDocumentUndoManagerRunLoopPrivateMode = @"com.omnigroup.OmniUIDocument.PrivateUndoMode";

+ (void)initialize;
{
    OBINITIALIZE;

    // 22979440: NSUndoManager.runLoopModes is ineffective.
    // We can hack around this by registering a timer in our private mode. That makes the mode 'real' enough that the NSUndoManager observer will actually fire.
    NSTimer *timer = [NSTimer timerWithTimeInterval:DBL_MAX target:self selector:@selector(_privateUndoModeTimerFired:) userInfo:nil repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:timer forMode:OUIDocumentUndoManagerRunLoopPrivateMode];
}

+ (void)_privateUndoModeTimerFired:(NSTimer *)timer
{
}

+ (BOOL)shouldShowAutosaveIndicator;
{
#if 1 && defined(DEBUG_shannon)
    return YES;
#endif
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"OUIDocumentShouldShowAutosaveIndicator"];
}

// existing document
- initWithExistingFileItem:(ODSFileItem *)fileItem error:(NSError **)outError;
{
    OBPRECONDITION(fileItem);
    OBPRECONDITION(fileItem.fileURL);

    return [self initWithFileItem:fileItem url:fileItem.fileURL error:outError];
}

- initWithContentsOfTemplateAtURL:(NSURL *)templateURLOrNil toBeSavedToURL:(NSURL *)saveURL error:(NSError **)outError;
{
    OBPRECONDITION(![NSThread isMainThread], "Subclassers are supposed to read the template, so this should be on a background queue.");
    
    return [self initWithFileItem:nil url:saveURL error:outError];
}

- initWithContentsOfImportableFileAtURL:(NSURL *)importableURL toBeSavedToURL:(NSURL *)saveURL error:(NSError **)outError;
{
    if ([NSThread isMainThread]) {
        OBFinishPortingLater("<bug:///147561> Subclassers are supposed to read the contents at importableURL, so this should be on a background queue.");
    }

    return [self initWithFileItem:nil url:saveURL error:outError];
}

- initEmptyDocumentToBeSavedToURL:(NSURL *)url error:(NSError **)outError;
{
    OBPRECONDITION(url);

    return [self initWithFileItem:nil url:url error:outError];
}

// Use one of our two initializers
- initWithFileURL:(NSURL *)fileURL;
{
    OBRejectUnusedImplementation(self, _cmd);
    return nil;
}

- initWithFileItem:(ODSFileItem *)fileItem url:(NSURL *)url error:(NSError **)outError;
{
    DEBUG_DOCUMENT(@"INIT %p with %@ %@", self, [fileItem shortDescription], url);

    OBPRECONDITION(fileItem || url);
    OBPRECONDITION(!fileItem || [fileItem.fileURL isEqual:url]);

#ifdef OMNI_ASSERTIONS_ON
    Class implementingClass = OBClassImplementingMethod([self class], @selector(initEmptyDocumentToBeSavedToURL:error:));
    OBPRECONDITION([NSStringFromClass(implementingClass) hasPrefix:@"OUI"], "Should subclass -initEmptyDocumentToBeSavedToURL:templateURL:error:");
#endif
    
    if (!(self = [super initWithFileURL:url]))
        return nil;
    
    _documentScope = (OFXDocumentStoreScope *)[fileItem scope];
    
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
    
    self.undoManager = undoManager;

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_inspectorDidEndChangingInspectedObjects:) name:OUIInspectorDidEndChangingInspectedObjectsNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_updateUndoIndicator) name:OFUndoManagerEnablednessDidChangeNotification object:self.undoManager];

    return self;
}

- (void)dealloc;
{
#if DEBUG_DOCUMENT_DEFINED
    int32_t count = OSAtomicDecrement32Barrier(&OUIDocumentInstanceCount);
    DEBUG_DOCUMENT(@"DEALLOC %p (count %d)", self, count);
#endif
    OBASSERT(_lastQueuedUpdateMessage == nil);
    OBASSERT(_accommodatingDeletion == NO);
    OBASSERT(_originalURLPriorToAccomodatingDeletion == nil);
    OBASSERT(_afterCloseRelinquishToWriter == nil);
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    _documentViewController.document = nil;
    
    // UIView cannot get torn down on background threads. Capture these in locals to avoid the block doing a -retain on us while we are in -dealloc
    UIViewController *viewController = _documentViewController;
    OBStrongRetain(viewController);
    
    OUIUndoIndicator *undoIndicator = _undoIndicator;
    OBStrongRetain(undoIndicator);
    _undoIndicator = nil;
    
    main_sync(^{
        OBStrongRelease(viewController);
        OBStrongRelease(undoIndicator);
    });
}

- (ODSFileItem *)fileItem;
{
    NSURL *fileURL = self.fileURL;
    ODSFileItem *fileItemInScope = [_documentScope fileItemWithURL:fileURL];
    if (fileItemInScope != nil) {
        _transientFileItem = nil; // No longer needed if we have a real file item.
        
        return fileItemInScope;
    }
    
    if (fileURL == nil)
        return nil;
    
    if (_transientFileItem && OFURLEqualsURL(_transientFileItem.fileURL, fileURL))
        return _transientFileItem;
    
    // This is most likely being hit since we are creating a new document and we are about to set the file item's edit in -saveToURL:forSaveOperation:completionHandler:. So, leave the fileEdit nil on this transient item instead of hitting the assertion in ODSFileItem that it should only be created from a URL on a background thread.
#if 1
    OFFileEdit *fileEdit = nil;
    __autoreleasing NSNumber *isDirectoryNumber = nil;
    __autoreleasing NSError *resourceError = nil;
    if (![fileURL getResourceValue:&isDirectoryNumber forKey:NSURLIsDirectoryKey error:&resourceError]) {
#ifdef DEBUG
        // One way to get here is closing a document that was deleted by a cloud provider while our app was backgrounded. Not sure if we should handle that differently.
        NSLog(@"Error getting directory key for %@: %@", fileURL, [resourceError toPropertyList]);
#endif
    }
    BOOL isDirectory = [isDirectoryNumber boolValue];
#else
    __autoreleasing NSError *error;
    OFFileEdit *fileEdit = [[OFFileEdit alloc] initWithFileURL:fileURL error:&error];
    BOOL isDirectory = fileEdit.directory;
    if (!fileEdit) {
        [error log:@"Cannot create file edit for file at %@", fileURL];
    }
#endif
    
    NSDate *userModificationDate = self.fileModificationDate;
    if (!userModificationDate) {
        // New document; the code we are calling likes to have a placeholder date.
        userModificationDate = [NSDate date];
    }
    
    _transientFileItem = [_documentScope makeFileItemForURL:fileURL isDirectory:isDirectory fileEdit:fileEdit userModificationDate:userModificationDate];
    return _transientFileItem;
}

- (void)willEditDocumentTitle;
{
    // Subclass for specific actions on title edit, such as dismiss inspectors.
}

- (void)setUndoManager:(NSUndoManager *)undoManager;
{
    NSUndoManager *oldUndoManager = self.observedUndoManager;
    if (oldUndoManager) {
        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];

        [center removeObserver:self name:NSUndoManagerDidUndoChangeNotification object:oldUndoManager];
        [center removeObserver:self name:NSUndoManagerDidRedoChangeNotification object:oldUndoManager];

        [center removeObserver:self name:NSUndoManagerDidOpenUndoGroupNotification object:oldUndoManager];
        [center removeObserver:self name:NSUndoManagerWillCloseUndoGroupNotification object:oldUndoManager];
        [center removeObserver:self name:NSUndoManagerDidCloseUndoGroupNotification object:oldUndoManager];

        self.observedUndoManager = nil;
    }

    [super setUndoManager:undoManager];

    if (undoManager) {
        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];

        [center addObserver:self selector:@selector(_undoManagerDidUndo:) name:NSUndoManagerDidUndoChangeNotification object:undoManager];
        [center addObserver:self selector:@selector(_undoManagerDidRedo:) name:NSUndoManagerDidRedoChangeNotification object:undoManager];

        [center addObserver:self selector:@selector(_undoManagerDidOpenGroup:) name:NSUndoManagerDidOpenUndoGroupNotification object:undoManager];
        [center addObserver:self selector:@selector(_undoManagerWillCloseGroup:) name:NSUndoManagerWillCloseUndoGroupNotification object:undoManager];
        [center addObserver:self selector:@selector(_undoManagerDidCloseGroup:) name:NSUndoManagerDidCloseUndoGroupNotification object:undoManager];

        // Add a private runloop mode so that we can force the undo manager to close its undo group w/o letting other runloop observers fire. In particular, we don't want to let the CoreAnimation run loop observer fire when it shouldn't.
        // <bug:///121879> (Crasher: Using Share menu on unsaved text - unexpected start state)
        NSArray *undoModes = undoManager.runLoopModes;
        if (![undoModes containsObject:OUIDocumentUndoManagerRunLoopPrivateMode]) {
            OBASSERT([undoModes isEqual:@[NSDefaultRunLoopMode]]); // need to reevaluate this approach if the NSUndoManager's default configuration changes
            NSMutableArray *modes = [[NSMutableArray alloc] initWithArray:undoModes];
            [modes addObject:OUIDocumentUndoManagerRunLoopPrivateMode];
            undoManager.runLoopModes = modes;
        }
    }
    self.observedUndoManager = undoManager;
}

- (void)finishUndoGroup;
{
    if (!_hasUndoGroupOpen)
        return; // Nothing to do!
    
    DEBUG_UNDO(@"finishUndoGroup");

    if ([_documentViewController respondsToSelector:@selector(documentWillCloseUndoGroup)])
        [_documentViewController documentWillCloseUndoGroup];
    
    [self willFinishUndoGroup];
    
    // Our group might be the only one open, but the auto-created group might be open still too (for example, with a single-event action like -delete:)
    OBASSERT([self.undoManager groupingLevel] >= 1);
    _hasUndoGroupOpen = NO;
    
    // This should drop the count to zero, provoking an -updateChangeCount:UIDocumentChangeDone
    [self.undoManager endUndoGrouping];
    
    // If the edit started in this cycle of the runloop, the automatic group opened by the system may not have closed and any following edits will get grouped with it.
    if ([self.undoManager groupingLevel] > 0) {
        OBASSERT([self.undoManager groupingLevel] == 1);

        // Terrible hack to let the by-event undo group close, plus a check that the hack worked...
        OBASSERT([self.undoManager.runLoopModes containsObject:OUIDocumentUndoManagerRunLoopPrivateMode]);
        [[NSRunLoop currentRunLoop] runMode:OUIDocumentUndoManagerRunLoopPrivateMode beforeDate:[NSDate distantPast]];
    }

    OBPOSTCONDITION([self.undoManager groupingLevel] == 0);
    OBPOSTCONDITION(!_hasUndoGroupOpen);
}

- (IBAction)undo:(id)sender;
{
    if (![self shouldUndo])
        return;
    
    // Make sure any edits get finished and saved in the current undo group
    OUIWithoutAnimating(^{
        [_documentViewController.view.window endEditing:YES/*force*/];
        [self.defaultFirstResponder becomeFirstResponder]; // Likely the document view controller itself
        [_documentViewController.view layoutIfNeeded];
    });
    
    [self finishUndoGroup]; // close any nested group we created
    
    [self.undoManager undo];
    
    [self didUndo];
}

- (void)forceUndoGroupClosed
{
    while (self.undoManager.groupingLevel > 0) {
        _hasUndoGroupOpen = YES;
        [self finishUndoGroup];
    }
}

- (IBAction)redo:(id)sender;
{
    if (![self shouldRedo])
        return;
    
    // Make sure any edits get finished and saved in the current undo group
    [_documentViewController.view.window endEditing:YES/*force*/];
    [self.defaultFirstResponder becomeFirstResponder]; // Likely the document view controller itself
    [self finishUndoGroup]; // close any nested group we created
    
    [self.undoManager redo];
    
    [self didRedo];
}

- (void)reacquireSubItemsAfterMovingFromURL:(NSURL *)oldURL completionHandler:(void (^)(void))completionHandler;
{
    OBPRECONDITION(![NSThread isMainThread]); // Should be called in -[UIDocument performAsynchronousFileAccessUsingBlock:].
    
    // If this method isn't subclassed, or if the subclass calls us, we need to do the completion handler.
    if (completionHandler)
        completionHandler();
}

- (void)viewStateChanged;
{
    OBPRECONDITION([NSThread isMainThread]);
    OBPRECONDITION(_forPreviewGeneration == NO); // Make sure we don't provoke a save due to just opening a document to make a preview!
    
    if (([self documentState] & UIDocumentStateClosed) != 0)
        return;
    _requestedViewStateChangeCount++;
}

- (void)beganUncommittedDataChange;
{
    // Unlike view state, here we do eventually plan to make a data change, but haven't done so yet.
    // This can be useful when an in-progress text field change is made and we want to periodically autosave the edits.
    if (([self documentState] & UIDocumentStateClosed) != 0)
        return;
    [self updateChangeCount:UIDocumentChangeDone];
}

- (UIViewController *)viewControllerToPresent;
{
    OBRequestConcreteImplementation(self, _cmd);
}

- (void)setApplicationLock:(OUIInteractionLock *)applicationLock;
{
    if (_applicationLock == applicationLock) {
        return;
    }
    [_applicationLock unlock];
    _applicationLock = applicationLock;
}

- (UIResponder *)defaultFirstResponder;
{
    UIViewController <OUIDocumentViewController> *viewController = self.documentViewController;
    
    if ([viewController respondsToSelector:_cmd])
        return viewController.defaultFirstResponder;
    return viewController;
}

- (void)didClose;
{
    // Dump our view controller, which could have backpointers to us.
    _documentViewController = nil;
}

- (void)didWriteToURL:(NSURL *)url;
{
    __autoreleasing NSError *error;
    OFFileEdit *fileEdit = [[OFFileEdit alloc] initWithFileURL:url error:&error];
    if (!fileEdit) {
        [error log:@"Error creating file edit from %@", url];
    }
    
    // To avoid possible races with mulitple saves being queued up, we could maybe enqueue this on the main queue so that it is stored before the -closeWithCompletionHandler: completion handler is called. But, UIDocument doesn't make any guarantees about how that's scheduled (they may have added it to the NSOperationQueue already but with a dependency). Instead, we'll try to be careful (and this is going to be a very rare problem hopefully).
    @synchronized(self) {
        OBASSERT(_lastWrittenFileEdit == nil);
        _lastWrittenFileEdit = [fileEdit copy];
    }
}

#pragma mark -
#pragma mark UIDocument subclass

- (BOOL)hasUnsavedChanges;
{
    // This gets called on the background queue as part of autosaving. This is read-only, but presumably UIDocument needs to deal with possible races with edits happening on the main queue.
    //OBPRECONDITION([NSThread isMainThread]);

    BOOL hasUnsavedViewState = (_requestedViewStateChangeCount != _savedViewStateChangeCount);
    BOOL hasUnsavedData = [super hasUnsavedChanges];
    BOOL result = hasUnsavedViewState || hasUnsavedData;
    DEBUG_DOCUMENT(@"%@ %@ hasUnsavedChanges -> %d (view:%d data:%d)", [self shortDescription], NSStringFromSelector(_cmd), result, hasUnsavedViewState, hasUnsavedData);
    
    OBPOSTCONDITION(!result || _forPreviewGeneration == NO); // Make sure we don't provoke a save due to just opening a document to make a preview!

    return result;
}

- (void)updateChangeCount:(UIDocumentChangeKind)change;
{
    OBPRECONDITION([NSThread isMainThread]);
    OBPRECONDITION(_forPreviewGeneration == NO); // Make sure we don't provoke a save due to just opening a document to make a preview!

    DEBUG_DOCUMENT(@"%@ %@ %ld", [self shortDescription], NSStringFromSelector(_cmd), change);
    
    // This registers the autosave timer
    [super updateChangeCount:change];
    
    if (change != UIDocumentChangeCleared) {
        [OUIUndoBarButtonItem updateState];
    }
    
    [self _updateUndoIndicator];
}

static NSString * const ViewStateChangeTokenKey = @"viewStateChangeCount";
static NSString * const OriginalChangeTokenKey = @"originalToken";

- (id)changeCountTokenForSaveOperation:(UIDocumentSaveOperation)saveOperation;
{
    // New documents get created and saved on a background thread, but normal documents should be on the main thread
    OBPRECONDITION((self.fileURL == nil) != [NSThread isMainThread]);
    
    //OBPRECONDITION(saveOperation == UIDocumentSaveForOverwriting); // UIDocumentSaveForCreating for saving when we get getting saved to the ".ubd" dustbin during -accommodatePresentedItemDeletionWithCompletionHandler:
    
    // The normal token from UIDocument is a private class NSDocumentDifferenceSizeTriple which records "dueToRecentChangesBeforeSaving", "betweenPreservingPreviousVersionAndSaving" and "betweenPreviousSavingAndSaving", but that could change. UIDocument says we can return anything we want, though and seems to just use -isEqual: (there is no -compare: on the private class as of 5.1 beta 3). We want to also record editor state when asked.
    
    id originalToken = [super changeCountTokenForSaveOperation:saveOperation];
    OBASSERT(originalToken);
    
    NSDictionary *token = [NSDictionary dictionaryWithObjectsAndKeys:
                           [NSNumber numberWithUnsignedInteger:_requestedViewStateChangeCount], ViewStateChangeTokenKey,
                           originalToken, OriginalChangeTokenKey,
                           nil];
    
    DEBUG_DOCUMENT(@"%@ %@ changeCountTokenForSaveOperation:%ld -> %@ %@", [self shortDescription], NSStringFromSelector(_cmd), saveOperation, [token class], token);
    return token;
}

- (void)updateChangeCountWithToken:(id)changeCountToken forSaveOperation:(UIDocumentSaveOperation)saveOperation;
{
    // This always gets called on the main thread, even when saving new documents on the background
    OBPRECONDITION([NSThread isMainThread]);
    
    DEBUG_DOCUMENT(@"%@ %@ updateChangeCountWithToken:%@ forSaveOperation:%ld", [self shortDescription], NSStringFromSelector(_cmd), changeCountToken, saveOperation);
    
    OBASSERT([changeCountToken isKindOfClass:[NSDictionary class]]); // Since we returned one...
    OBASSERT([changeCountToken count] == 2); // the two keys we put in
    
    NSNumber *editorStateCount = [(NSDictionary *)changeCountToken objectForKey:ViewStateChangeTokenKey];
    OBASSERT(editorStateCount);
    _savedViewStateChangeCount = [editorStateCount unsignedIntegerValue];
    
    id originalToken = [(NSDictionary *)changeCountToken objectForKey:OriginalChangeTokenKey];
    OBASSERT(originalToken);
    
    [super updateChangeCountWithToken:originalToken forSaveOperation:saveOperation];
}

- (void)_autoresolveConflicts;
{
    NSURL *url = self.fileURL;
    NSFileVersion *currentVersion = [NSFileVersion currentVersionOfItemAtURL:url];
    NSArray *otherVersions = [NSFileVersion otherVersionsOfItemAtURL:url];
    if (otherVersions.count == 0)
        return;

    DEBUG_DOCUMENT(@"Auto-resolving document conflict on open");
    NSFileVersion *latestVersion = currentVersion;
    for (NSFileVersion *otherVersion in otherVersions) {
        if ([otherVersion.modificationDate isAfterDate:latestVersion.modificationDate]) {
            latestVersion = otherVersion;
        }
    }

    // TODO: When you use NSFileVersionReplacingByMoving you remove a version of the file, and should do it as part of a coordinated write to the file. The advice about this for +addVersionOfItemAtURL:withContentsOfURL:options:error: applies here too. When you use it to promote a version to a separate file you actually write to two files, and should do it as part of a coordinated write to two files, using -[NSFileCoordinator coordinateWritingItemAtURL:options:writingItemAtURL:options:error:byAccessor:], most likely using NSFileCoordinatorWritingForReplacing for the file you're promoting the version to.
    DEBUG_DOCUMENT(@"Using latest version (%@ at %@)", latestVersion.localizedNameOfSavingComputer, latestVersion.modificationDate);
    if (latestVersion != currentVersion) {
        DEBUG_DOCUMENT(@"Replacing current version (%@ at %@) with (%@ at %@)", currentVersion.localizedNameOfSavingComputer, currentVersion.modificationDate, latestVersion.localizedNameOfSavingComputer, latestVersion.modificationDate);
        [latestVersion replaceItemAtURL:url options:0 error:nil];
    }

    [NSFileVersion removeOtherVersionsOfItemAtURL:url error:nil];
    NSArray *conflictVersions = [NSFileVersion unresolvedConflictVersionsOfItemAtURL:url];
    for (NSFileVersion *conflictVersion in conflictVersions) {
        DEBUG_DOCUMENT(@"Resolving conflict with version (%@ at %@)", conflictVersion.localizedNameOfSavingComputer, conflictVersion.modificationDate);
        conflictVersion.resolved = YES;
    }
}

- (void)openWithCompletionHandler:(void (^)(BOOL success))completionHandler;
{
    OBPRECONDITION(self.documentState & (UIDocumentStateClosed|UIDocumentStateEditingDisabled)); // Revert just has UIDocumentStateEditingDisabled set.
    
    DEBUG_DOCUMENT(@"%@ %@", [self shortDescription], NSStringFromSelector(_cmd));

#ifdef OMNI_ASSERTIONS_ON
    // We don't want opening the document to provoke download -- we should provoke that earlier and only open when it is fully downloaded
    {
        OBASSERT(self.fileItem != nil);
        //OBASSERT(_fileItem.isDownloaded); // Might be opening the auto-nominated conflict winner during a revert
    }
#endif

    if ([[OFPreference preferenceForKey:@"OUIDocumentAutoresolvesConflicts" defaultValue:@(NO)] boolValue])
          [self _autoresolveConflicts];

    __weak OUIDocument *welf = self;
    [super openWithCompletionHandler:^(BOOL success){
        OUIDocument *strelf = welf;
        DEBUG_DOCUMENT(@"%@ %@ success %d", [self shortDescription], NSStringFromSelector(_cmd), success);
        
#if 0
        // Silly hack to help in testing whether we properly write blank previews and avoid re-opening previously open documents. You can test the re-opening case by making a good document, opening it, renaming it to the bad name and then backgrounding the app (so that we record the last open document).
        if ([[[[strelf.fileURL path] lastPathComponent] stringByDeletingPathExtension] localizedCaseInsensitiveCompare:@"Opening this file will crash"] == NSOrderedSame) {
            NSLog(@"Why yes, it will.");
            abort();
        }
#endif
        
        BOOL goingToCloseImmediatelyAnyway = (_savedCloseCompletionBlock != nil);

        if (success) {
            
            if (!goingToCloseImmediatelyAnyway) {
                OBASSERT(_documentViewController == nil);
                _documentViewController = [self makeViewController];
                OBASSERT([_documentViewController conformsToProtocol:@protocol(OUIDocumentViewController)]);
                OBASSERT(_documentViewController.document == nil); // we'll set it; -makeViewController shouldn't bother
                _documentViewController.document = strelf;
                
                // Don't provoke loading of views before they are configured for preview generation (also our view controller will never be presented).
                if (!strelf.forPreviewGeneration) {
                    [strelf updateViewControllerToPresent];
                    
                    [strelf _queueUpdateMessageProvider:^NSString *{
                        NSString *lastEditedMessage = [strelf _lastEditedMessage];
                        return lastEditedMessage;
                    }];
                }
            }

            // clear out any undo actions created during init
            [strelf.undoManager removeAllActions];
            
            // this implicitly kills any groups; make sure our flag gets cleared too.
            OBASSERT([strelf.undoManager groupingLevel] == 0);
            _hasUndoGroupOpen = NO;
        }
        
        BOOL reallyReportSuccess = success && !goingToCloseImmediatelyAnyway;
        completionHandler(reallyReportSuccess);  // if we're just going to close immediately because we were already asked to close before we even finished opening (see <bug:///125526> (Bug: ~10 second freeze after deleting 'Complex' stencil)), then pass NO as the success flag to the open completion handler to avoid doing useless work.
        
        if (goingToCloseImmediatelyAnyway) {
            [strelf closeWithCompletionHandler:_savedCloseCompletionBlock];
            _savedCloseCompletionBlock = nil;
        }
    }];
}

- (void)closeWithCompletionHandler:(void (^)(BOOL success))completionHandler;
{
    OBPRECONDITION((self.documentState & UIDocumentStateClosed) == 0);
    
    if (!self.isDefinitelyClosing && (self.documentState & UIDocumentStateClosed) != 0) {
        // we may be being asked to close before we have finished opening.  note that and save the completion handler for when we can actually close.
        // we will close if/when we have successfully opened.
        _savedCloseCompletionBlock = [completionHandler copy];
        if (!_savedCloseCompletionBlock) {
            _savedCloseCompletionBlock = ^(BOOL success){};  // we depend on this block being non-nil to know that we need to close as soon as we've opened.
        }
        return;
    }
    
    DEBUG_DOCUMENT(@"%@ %@", [self shortDescription], NSStringFromSelector(_cmd));

    // Make sure to break retain cycles, if this is up.
    [self dismissUpdateMessage];
    
    // We save the view state on close, even if there is no saving (since the user might not have edited anything).
    __block NSDictionary *viewState = nil;
    
    OUIWithoutAnimating(^{
        // If the user is just switching to another app quickly and coming right back (maybe to paste something at us), we don't want to end editing.
        // Instead, we should commit any partial edits, but leave the editor up.
        
        OBASSERT_IF(self.forPreviewGeneration, self.hasUnsavedChanges == NO, "Don't modify a document while generating a preview");
        
        [self _willSave];

        if (!self.forPreviewGeneration && _documentViewController != nil) {
            // When saving, we don't end editing since the user might just be switching to another app quickly and coming right back (maybe to paste something at us). But here we are closing and should commit our edits and shut down the field editor. The edits should have been committed when we were backgrounded, but it is nicer to clean up any editor here before views get removed from the view hierarchy.
            UIView *viewControllerToPresentView = self.viewControllerToPresent.view;
            [viewControllerToPresentView endEditing:YES];
            [viewControllerToPresentView layoutIfNeeded];

            if ([_documentViewController respondsToSelector:@selector(documentViewState)]) {
                viewState = [_documentViewController documentViewState];
            }
        }

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
    
    // If there is an error opening the document, we immediately close it.
    BOOL hadError = ([self documentState] & UIDocumentStateSavingError) != 0;
    
    completionHandler = [completionHandler copy];
    
    // Make sure that if the app is backgrounded, we don't get left in the middle of a close operation (still being a file presenter) where the user could delete us (via iTunes or iCloud) and then on foregrounding of the app UIDocument can get confused.
    OFBackgroundActivity *activity = [OFBackgroundActivity backgroundActivityWithIdentifier:@"com.omnigroup.OmniUI.OUIDocument.close"];

    void (^closedCompletion)(BOOL success) = ^void(BOOL success) {
        DEBUG_DOCUMENT(@"%@ %@ success %d", [self shortDescription], NSStringFromSelector(_cmd), success);

        [self _updateUndoIndicator];

        void (^previewCompletion)(void) = ^{
            OBASSERT(_isClosing == YES);
            _isClosing = NO;

            if (completionHandler)
            completionHandler(success);

            if (_afterCloseRelinquishToWriter) {
                // A document that was open to generate previews has been closed. We need to finish up accomodating that deletion now.
                OBASSERT(self.forPreviewGeneration);
                void (^afterCloseRelinquishToWriter)(void (^reacquire)(void)) = _afterCloseRelinquishToWriter;
                _afterCloseRelinquishToWriter = nil;
                afterCloseRelinquishToWriter(nil);
            }

            // Let the document picker know that a new preview is available. We do this here rather than in OUIDocumentPreviewGenerator since if a new document is opened while an existing document is already open (and thus the old document is closed), say by tapping on a document while in Mail and while our app is running and showing a document, then the preview generator might not ever do the generation.
            [[NSNotificationCenter defaultCenter] postNotificationName:OUIDocumentPreviewsUpdatedForFileItemNotification object:self.fileItem userInfo:nil];

            [activity finished];
        };

        ODSFileItem *fileItem = self.fileItem;
        if (fileItem != nil && !hadError) { // New document being closed to save its initial state before being opened to edit?

            // Our save path should have updated our file item's latest fileEdit.
            if (fileItem.fileModificationDate != nil) {
                OBASSERT([fileItem.fileModificationDate isEqual:self.fileModificationDate]);
            }
            // The date refresh is asynchronous, so we'll force preview loading in the case that we know we should consider the previews out of date.
            OFFileEdit *fileEdit = fileItem.fileEdit;
            if (fileEdit != nil) {
                [self _writePreviewsIfNeeded:(hadChanges == NO) fileEdit:fileEdit withCompletionHandler:previewCompletion];

                [OUIDocumentAppController setDocumentState:viewState forFileEdit:fileEdit];
            } else {
                previewCompletion();
            }
        } else {
            previewCompletion();
        }
    };

    if ((self.documentState & UIDocumentStateClosed) != 0) {
        closedCompletion(YES);
    } else {
        [super closeWithCompletionHandler:closedCompletion];
    }
}

/*
 NOTE: This method does not always get called for UIDocument initiated saves. For example, if you make a change (calling -updateChangeCount:) and then pretty the power button to lock the screen, -hasUnsavedChanges is called and then the document is written directly, rather than calling the autosave method.
 
 Also, we cannot defer autosaving. If we just call completionHandler(NO), the autosave timer doesn't get rescheduled immediately.
 */
- (void)autosaveWithCompletionHandler:(void (^)(BOOL))completionHandler;
{
    OBPRECONDITION(![self.undoManager isUndoing]);
    OBPRECONDITION(![self.undoManager isRedoing]);
    
    DEBUG_UNDO(@"Autosave running...");

    if ([self hasUnsavedChanges]) { // If we somehow end up here with unsaved changes, don't call -_willSave.
        [self _willSave];
    }

    [super autosaveWithCompletionHandler:^(BOOL success){
        DEBUG_UNDO(@"  Autosave success = %d", success);
        
        // Do this *after* our possible preview saving. We may be getting called by the -closeWithCompletionHandler: where the completion block might invalidate some of the document state.
        if (completionHandler)
            completionHandler(success);

        [self _updateUndoIndicator];
    }];
}

- (id)contentsForType:(NSString *)typeName error:(NSError **)outError;
{
    OBASSERT_NOT_REACHED("If you fail to implement this, you'll get a nil error passed to -saveToURL:forSaveOperation:completionHandler: and the completion handler will never be called!"); // 14208162: If document doesn't subclass -contentsForType:error:, strange behavior results
    OBUserCancelledError(outError);
    OBChainError(outError);
    return nil;
}

- (void)saveToURL:(NSURL *)url forSaveOperation:(UIDocumentSaveOperation)saveOperation completionHandler:(void (^)(BOOL success))completionHandler;
{
    OBPRECONDITION([NSThread isMainThread]); // Needed for the call to -_willSave below since it will tell the view controller, which will muck with views and model state as it saves partial edits.

    DEBUG_DOCUMENT(@"Save with operation %ld to %@", saveOperation, [url absoluteString]);

    if (_accommodatingDeletion) {
        // This will happen when the user has opted to "Keep" a document that was deleted on another device.
        // At this point, the document has been moved into the dead zone and UIDocument tries to save itself (because we left it open) and the save will fail. Just bail.
        OBASSERT(_originalURLPriorToAccomodatingDeletion);
        OBASSERT([[url absoluteString] containsString:@"/.ubd/"]); // In the dead zone.
        OBASSERT([[url absoluteString] containsString:@"/dead-"]);
        
        DEBUG_DOCUMENT(@"   ... skipping saving while recovering from dead zone.");
        if (completionHandler)
            completionHandler(YES);
        return;
    }
    
    OBASSERT(!ODSIsInInbox(url));
    
    @synchronized(self) {
        OBASSERT(_lastWrittenFileEdit == nil);
        _lastWrittenFileEdit = nil; // but just in case...
    }

    // In iOS 5, when backgrounding the app, the -autosaveWithCompletionHandler: method would be called. In iOS 6, this is called directly.
    [self _willSave];

    OFFileEdit *originalFileEdit = self.fileModificationDate ? self.fileItem.fileEdit : nil; // our fileURL will be set already for never-saved documents, but our modification date won't. Try to avoid making a transient fileItem for no purpose.
    
    NSDictionary *viewState = nil;
    if ([_documentViewController respondsToSelector:@selector(documentViewState)]) {
        viewState = [_documentViewController documentViewState];
    }

    completionHandler = [completionHandler copy];

    BOOL isChangingFileType = !OFISEQUAL(self.fileType, self.savingFileType);
    bool ensureUniqueName = NO;
    if (isChangingFileType) {
        // TODO: This will hit an assertion if it actually executed. See bug:///137297 (iOS-OmniGraffle Crasher: Assertion fail shortly after editing document -[ODSScope urlForNewDocumentInFolderAtURL:baseName:fileType:])
        // In this particular case, though we are going to end up with the same URL (we are upgrading a document from flat file to file wrapper but with the same path extension).
        ensureUniqueName = _documentScope != nil && ![[url pathExtension] isEqual:[self fileNameExtensionForType:self.savingFileType saveOperation:saveOperation]];

        if (ensureUniqueName) {
            ODSFileItem *fileItem = self.fileItem;
            OBASSERT(fileItem, "If we are converting file types, we assume the original file existed (this is not a new unsaved document)");
            url = [_documentScope urlForNewDocumentInFolder:fileItem.parentFolder baseName:[fileItem.name stringByDeletingPathExtension] fileType:self.savingFileType];
            if ([url.pathExtension isEqualToString:fileItem.fileURL.pathExtension]) {
                // this should mean that no rename is necessary.  we should overwrite this file with the same name instead of using the unnecessary unique name we just generated (e.g. we are changing from a flat .graffle to a package .graffle)
                url = fileItem.fileURL;
            }
        }
    }
    
    BOOL shouldRemoveCachedResourceValue = ((saveOperation == UIDocumentSaveForOverwriting) && isChangingFileType);

    OBASSERT_NULL(_currentSaveURL);
    _currentSaveOperation = saveOperation;
    _currentSaveURL = [url copy];

    void (^saveBlock)(void (^updateCompletionHandler)(BOOL success, NSURL *destinationURL, NSError *error)) = ^void (void (^updateCompletionHandler)(BOOL success, NSURL *destinationURL, NSError *error)) {
        [super saveToURL:url forSaveOperation:saveOperation completionHandler:^(BOOL success){
            DEBUG_DOCUMENT(@"  save success %d", success);

            OBASSERT_NOTNULL(_currentSaveURL);
            _currentSaveURL = nil;

            // Subclasses must call -didWriteToURL: from their file saving path.
            OBASSERT_NOTNULL(_lastWrittenFileEdit);
            
            // This means that our view state rolls forward in version with us (and our old view state will be hanging out). So, we remove the old edit state at this point too.
            if (originalFileEdit) // New document?
                [OUIDocumentAppController setDocumentState:nil forFileEdit:originalFileEdit];
            [OUIDocumentAppController setDocumentState:viewState forFileEdit:_lastWrittenFileEdit];
            
            self.fileItem.fileEdit = _lastWrittenFileEdit;
            _lastWrittenFileEdit = nil;

            [self _recordLastEdit];

            if (shouldRemoveCachedResourceValue) {
                OBASSERT(url);
                
                // NSURL caches resource values that it has retrieved and OFUTIForFileURLPreferringNative() uses the resource values to determine the UTI. If we're going to change the file from flat to package (most likely case this is happening) then we need to clear the cache for the 'is directory' flag so that OFUTIForFileURLPreferringNative() returns the correct UTI next time we try to open the document. By the way, the NSURL documentation states that it's resource value cache is cleared at the turn of each runloop, but clearly it's not. Will try to repro and file a radar.
                [url removeCachedResourceValueForKey:NSURLIsDirectoryKey];
            }
            BOOL skipBackupAttributeSuccess = [[NSFileManager defaultManager] removeExcludedFromBackupAttributeToItemAtURL:url error:NULL];
#ifdef OMNI_ASSERTIONS_ON
            OBPOSTCONDITION(skipBackupAttributeSuccess);
#else
            (void)skipBackupAttributeSuccess;
#endif

            if (updateCompletionHandler)
                updateCompletionHandler(success, url, nil);

            if (completionHandler)
                completionHandler(success);
        }];
    };

    if (ensureUniqueName) {
        OBASSERT(self.fileItem);
        // this ensures that our fileItem gets its URL updated to match.
        [_documentScope updateFileItem:self.fileItem withBlock:saveBlock completionHandler:nil];
    } else
        saveBlock(nil);
}

- (void)disableEditing;
{
    OBPRECONDITION([NSThread isMainThread]);
    OBPRECONDITION(_rebuildingViewControllerState == nil);
    OBPRECONDITION(_editingDisabled == NO);
    
    DEBUG_DOCUMENT(@"Disable editing");
    _editingDisabled = YES;
    
    OUIWithoutAnimating(^{
        [[OUIDocumentAppController controller] documentDidDisableEnditing:self]; // "did" in that our editingDisabled property is now YES.
        
        // Incoming edit from the cloud, most likely. We should have been asked to save already via the coordinated write (might produce a conflict). Still, lets make sure we aren't editing.
        [_documentViewController.view endEditing:YES];
        [self.defaultFirstResponder becomeFirstResponder]; // Likely the document view controller itself
        
        // If we had a previous alert up, discard it. Do this after returning from our current context to avoid the "wait_fences: failed to receive reply: 10004003".
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            [self dismissUpdateMessage];
        }];
    });
    
    if (!_hasDisabledUserInteraction && !self.forPreviewGeneration) {
        _hasDisabledUserInteraction = YES;
        // Disable interaction not only on our documentViewController (because it may be contained within another view controller) but on the viewController used for our presentation.
        self.viewControllerToPresent.view.userInteractionEnabled = NO;
    }
}

- (void)enableEditing;
{
    OBPRECONDITION([NSThread isMainThread]);
    OBPRECONDITION(_editingDisabled == YES);
    
    DEBUG_DOCUMENT(@"Enable editing");
    _editingDisabled = NO;

    if (_hasDisabledUserInteraction) {
        _hasDisabledUserInteraction = NO;
        // Re-enable interaction not only on our documentViewController (because it may be contained within another view controller) but on the viewController used for our presentation.
        self.viewControllerToPresent.view.userInteractionEnabled = YES;
    }

    // Show any alert that was queued and display deferred since we were still in the middle of -relinquishPresentedItemToWriter:.
    // It might be better to set our own flag in a subclass implementation of -relinquishPresentedItemToWriter:, but this should be the same effect.
    if (self.lastQueuedUpdateMessage != nil && self.viewControllerToPresent.isViewLoaded) {
        [self displayLastQueuedUpdateMessage];
    }
    
    if (_accommodatingDeletion) {
        // This will happen at the end of the relinquish-to-writer block that wraps the deletion accomodation, if the user has tapped on "Keep" when asked what to do about the incoming delete. Our file will be off in the dead zone.
        OBASSERT(_originalURLPriorToAccomodatingDeletion);
        OBASSERT([[self.fileURL absoluteString] containsString:@"/.ubd/"]); // In the dead zone.
        OBASSERT([[self.fileURL absoluteString] containsString:@"/dead-"]);
        
        // Clear this so that the save won't bail on us.
        NSURL *saveURL = _originalURLPriorToAccomodatingDeletion;
        _originalURLPriorToAccomodatingDeletion = nil;
        _accommodatingDeletion = NO;

        // Save to the original location.
        [self saveToURL:saveURL forSaveOperation:UIDocumentSaveForCreating completionHandler:^(BOOL success){
            // Sadly, this doesn't update the fileURL -- it still points to the dead zone. BUT, at some point in the future, UIDocument magically sets its -fileURL back to the original, maybe when -[UIDocument relinquishPresentedItemToWriter:]'s reacquire block is executedit sees the file is there and puts the fileURL property back?
            // OBASSERT([self.fileURL isEqual:_originalURLPriorToAccomodatingDeletion]);
            DEBUG_DOCUMENT(@"resaved %d, fileURL %@", success, [self fileURL]);
        }];
    }
}

- (void)handleError:(NSError *)error userInteractionPermitted:(BOOL)userInteractionPermitted;
{
    DEBUG_DOCUMENT(@"Handle error with user interaction:%d: %@", userInteractionPermitted, [error toPropertyList]);

    if (_forPreviewGeneration) {
        // Just log it instead of popping up an alert for something the user didn't actually poke to open anyway.
        NSLog(@"Error while generating preview for %@: %@", [self.fileURL absoluteString], [error toPropertyList]);
    } else if (userInteractionPermitted) {
        if ([error hasUnderlyingErrorDomain:NSPOSIXErrorDomain code:ENOENT] ||
            [error hasUnderlyingErrorDomain:NSCocoaErrorDomain code:NSFileNoSuchFileError]) {
            // This can happen (currently) if you delete a file in iTunes and then attempt to open it in the app (since iTunes/iOS don't do file coordination right). The error text in this case is pretty poor. The Cocoa error just has "The operation couldn't be completed. (Cocoa error 260.)". The underlying POSIX error does say something about the file being missing, but it seems bad to assume it will continue to do so (or that we'll have such an underlying error).
            NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
                                      NSLocalizedStringFromTableInBundle(@"The operation couldn't be completed.", @"OmniUIDocument", OMNI_BUNDLE, @"Error description for a document operation failing due to a missing file."), NSLocalizedDescriptionKey,
                                      NSLocalizedStringFromTableInBundle(@"This document is not accessible. It is possible the file was deleted, renamed or moved via iTunes or an external document provider. Please try removing the file and adding it again.", @"OmniUIDocument", OMNI_BUNDLE, @"Error reason for a document operation failing due to a missing file."), NSLocalizedFailureReasonErrorKey,
                                      error, NSUnderlyingErrorKey,
                                      nil];
            error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileNoSuchFileError userInfo:userInfo];
        }
        
        OUI_PRESENT_ALERT(error);
    } else {
        [error log:@"Error encountered by document"];
    }
    
    [self finishedHandlingError:error recovered:NO];
}

- (void)userInteractionNoLongerPermittedForError:(NSError *)error;
{
    // Since we subclass -handleError:userInteractionPermitted:, we have to implement this too, according to the documentation.
    DEBUG_DOCUMENT(@"%s:%d -- %s", __FILE__, __LINE__, __PRETTY_FUNCTION__);
    [super userInteractionNoLongerPermittedForError:error];
}

- (void)_failRevertAndCloseAndReturnToDocumentPickerWithCompletionHandler:(void (^)(BOOL success))completionHandler;
{
    OBPRECONDITION(!_forPreviewGeneration); // Otherwise, we'd close some other open document
    
    completionHandler = [completionHandler copy];
    
    // The document may not exist (deletions while we were backgrounded, which don't go through -accommodatePresentedItemDeletionWithCompletionHandler:, but at any rate we can't read it.
        OUIDocumentAppController *controller = [OUIDocumentAppController controller];
        [controller closeDocumentWithCompletionHandler:^{
            [self _cleanupAndSignalFailedRevertWithCompletionHandler:completionHandler];
        }];
}

- (void)_cleanupAndSignalFailedRevertWithCompletionHandler:(void (^)(BOOL success))completionHandler;
{
    OBASSERT((id)completionHandler == [completionHandler copy]); // should have already been promoted to the heap
    
    if (completionHandler)
        completionHandler(NO);
}

- (void)revertToContentsOfURL:(NSURL *)url completionHandler:(void (^)(BOOL success))completionHandler;
{
    OBPRECONDITION([NSThread isMainThread]);
    OBPRECONDITION(_rebuildingViewControllerState == nil);

    DEBUG_DOCUMENT(@"%s:%d -- %s %@", __FILE__, __LINE__, __PRETTY_FUNCTION__, url);

    // If an open document is deleted via iCloud or iTunes, we don't get -accommodatePresentedItemDeletionWithCompletionHandler:. We do this before calling super so that we don't get an error about the missing file.
    __autoreleasing NSError *reachableError = nil;
    if (![url checkResourceIsReachableAndReturnError:&reachableError]) {
        [self _failRevertAndCloseAndReturnToDocumentPickerWithCompletionHandler:completionHandler];
        return;
    }

    _rebuildingViewControllerState = [self willRebuildViewController];

    // Incoming edit from the cloud, most likely. We should have been asked to save already via the coordinated write (might produce a conflict). Still, lets abort editing.
    [_documentViewController.view endEditing:YES];
    [self.defaultFirstResponder becomeFirstResponder]; // Likely the document view controller itself

    // Forget our view controller since UIDocument's reloading will call -openWithCompletionHandler: again and we'll make a new view controller
    // Note; doing a view controller rebuild via -relinquishPresentedItemToWriter: seems hard/impossible not only due to the crazy spaghetti mess of blocks but also because it is invoked on UIDocument's background thread, while we need to mess with UIViews.
    __weak OUIDocument *document = self;
    UIViewController <OUIDocumentViewController> *oldDocumentViewController = _documentViewController;
    UIViewController *oldPresentedViewController = self.viewControllerToPresent;
    _documentViewController = nil;
    oldDocumentViewController.document = nil;
    completionHandler = [completionHandler copy];
    
    [super revertToContentsOfURL:url completionHandler:^(BOOL success){
        if (!success) {
            __strong OUIDocument *strongDoc = document;
            [[OUIDocumentAppController controller] documentDidFailToRebuildViewController:strongDoc];
            [oldPresentedViewController dismissViewControllerAnimated:NO completion:nil];
            document.isDefinitelyClosing = YES;
            // Possibly deleted via iTunes while the document was open and we were backgrounded. Hit this as part of <bug:///77658> ([Crash] After deleting a lot of docs via iTunes you crash on next launch of app) and logged Radar 10775218: UIDocument should manage background tasks when performing state transitions. We should be working around this with our own background task management now.
            NSLog(@"Failed to revert document %@", self);
            
            [self _failRevertAndCloseAndReturnToDocumentPickerWithCompletionHandler:completionHandler];
        } else {
            OBASSERT([NSThread isMainThread]);

            // We should have a re-built view controller now, but it isn't on screen yet
            OBASSERT(_documentViewController);
            OBASSERT(_documentViewController.document == self);
            OBASSERT(![_documentViewController isViewLoaded] || _documentViewController.view.window == nil);
            
            if (completionHandler)
                completionHandler(success);
            
            id state = _rebuildingViewControllerState;
            _rebuildingViewControllerState = nil;
            [self didRebuildViewController:state];
            
            [self updateViewControllerToPresent];

            [self _queueUpdateMessageProvider:^NSString *{
                NSString *lastEditedMessage = [self _lastEditedMessage];
                return lastEditedMessage;
            }];
        }
    }];
}

#pragma mark - NSFilePresenter

- (void)relinquishPresentedItemToWriter:(void (^)(void (^reacquirer)(void)))writer;
{
    OBPRECONDITION(_inRelinquishPresentedItemToWriter == NO);
    
    DEBUG_DOCUMENT("Relinquish to writer");
    _inRelinquishPresentedItemToWriter = YES;

    // If a preview is being generated, block the writer until we finish. The writer could try to delete us, move us or change our contents, none of which we want to deal with while in the middle of generating a preview (and we don't have a good way to cancel the preview generation).
    if (self.forPreviewGeneration) {
        OBASSERT(_afterCloseRelinquishToWriter == nil);
        
        _afterCloseRelinquishToWriter = [writer copy];
        return;
    }
    

    [super relinquishPresentedItemToWriter:^(void (^superReacquirer)(void)){
        superReacquirer = [superReacquirer copy];
        
        writer(^{
            DEBUG_DOCUMENT("Starting to reacquire after writer");

            void (^finishReacquiring)(void) = ^{
                DEBUG_DOCUMENT("Finishing reacquiring after writer");
                
                OBASSERT(_inRelinquishPresentedItemToWriter == YES);
                _inRelinquishPresentedItemToWriter = NO;
                
                if (superReacquirer)
                    superReacquirer();
            };
            
            if (_originalURLPriorToPresentedItemDidMoveToURL && ((self.documentState & UIDocumentStateClosed) == 0)) {
                NSURL *originalURL = _originalURLPriorToPresentedItemDidMoveToURL;
                _originalURLPriorToPresentedItemDidMoveToURL = nil;
                
                DEBUG_DOCUMENT("Reacquiring sub-items after moving from %@", originalURL);
                [self performAsynchronousFileAccessUsingBlock:^{
                    [self reacquireSubItemsAfterMovingFromURL:originalURL completionHandler:finishReacquiring];
                }];
            } else {
                finishReacquiring();
            }
        });
    }];
}

- (void)accommodatePresentedItemDeletionWithCompletionHandler:(void (^)(NSError *errorOrNil))completionHandler;
{
    OBPRECONDITION(![NSThread isMainThread]);
    OBPRECONDITION(_accommodatingDeletion == NO);
    OBPRECONDITION(_originalURLPriorToAccomodatingDeletion == nil);
    OBPRECONDITION(_inRelinquishPresentedItemToWriter);
    OBPRECONDITION(!self.forPreviewGeneration || (([self documentState] & UIDocumentStateClosed) != 0)); // We should have blocked deletion while generating a preview by delaying relinquishing to writer, or if we're already actually closed then the forPreviewGeneration flag doesn't matter
    
    _accommodatingDeletion = YES; // Transient flag set while we are actually accommodating deletion.
    _originalURLPriorToAccomodatingDeletion = [self.fileURL copy];
    
    DEBUG_DOCUMENT(@"Accomodating deletion of %@", _originalURLPriorToAccomodatingDeletion);

    completionHandler = [completionHandler copy];
    
    [super accommodatePresentedItemDeletionWithCompletionHandler:^(NSError *errorOrNil){
        
        DEBUG_DOCUMENT(@"Deletion accomodation completion handler started, errorOrNil: %@", errorOrNil);
        OBASSERT(![NSThread isMainThread]);

        OUIDocumentAppController *appController = [OUIDocumentAppController controller];
        
        void (^closeFinished)(void) = ^{
            if (completionHandler)
                completionHandler(errorOrNil);
            
            [(UIViewController *)appController.documentPicker dismissViewControllerAnimated:YES completion:nil];
            
            OBASSERT(_accommodatingDeletion == YES);
            _accommodatingDeletion = NO;
            
            _originalURLPriorToAccomodatingDeletion = nil;
            
            DEBUG_DOCUMENT(@"Finished accomodating deletion of %@ (DELETE)", _originalURLPriorToAccomodatingDeletion);
        };
        
        // Apparently we can still be in the list of file presenters even after we've closed after generating a preview. If so, no need to do any of the following work, because we're already closed and done with.
        if (([self documentState] & UIDocumentStateClosed) != 0) {
            closeFinished();
            return;
        }
        
        closeFinished = [closeFinished copy];

        // By this point, our document has been moved to a ".ubd" Dead Zone, but the document is still open and pointing at that dead file.
        main_async(^{
            // The document will be deleted as soon as we return and call the completion handler (so we can zoom out to its file item).
            [appController closeDocumentWithCompletionHandler:closeFinished];
        });
    }];
}

@synthesize currentSaveOperation=_currentSaveOperation;
- (UIDocumentSaveOperation)currentSaveOperation;
{
    if (!_currentSaveURL)
        @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"Asked for the current save operation when none is occurring" userInfo:nil];
    
    return _currentSaveOperation;
}

- (void)presentedItemDidMoveToURL:(NSURL *)newURL;
{
    OBPRECONDITION([NSOperationQueue currentQueue] == [self presentedItemOperationQueue]);
    OBPRECONDITION(_inRelinquishPresentedItemToWriter);
    OBPRECONDITION(_originalURLPriorToPresentedItemDidMoveToURL == nil);
    
    _originalURLPriorToPresentedItemDidMoveToURL = [self.fileURL copy];

    [super presentedItemDidMoveToURL:newURL];
    OBASSERT([self.fileURL isEqual:newURL]);

    if (_accommodatingDeletion)
        return; // Don't pop up an alert about moving into the dead zone.
    
    NSURL *originalURLPriorToPresentedItemDidMoveToURL = _originalURLPriorToPresentedItemDidMoveToURL;
    __weak typeof(self) weakSelf = self;
    [self _queueUpdateMessageProvider:^NSString *{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        NSString *updateMessage = nil;
        
        // TODO: Test changing file extension? Maybe have 'type changed' variant?
        // TODO: Test incoming delete. We should not alert if we got closed
        if (OFNOTEQUAL([originalURLPriorToPresentedItemDidMoveToURL lastPathComponent], [newURL lastPathComponent])) {
            NSString *messageFormat = NSLocalizedStringFromTableInBundle(@"Renamed to %@.", @"OmniUIDocument", OMNI_BUNDLE, @"Message format for alert informing user that the document has been renamed on another device");
            
            NSString *displayName = [[strongSelf.fileItem class] displayNameForFileURL:newURL fileType:strongSelf.fileType];
            OBFinishPortingLater("<bug:///147832> (iOS-OmniOutliner Bug: OUIDocument.m:1245 - Can't ask the file item for its editing name. Need a class method of some sort)");
            updateMessage = [NSString stringWithFormat:messageFormat, displayName];
        } else {
            // The code above handles both renames and deletions. If we get althey way to here, we will assume a move has happend. Unfortunately, there is no way to know where the standard 'Shared Documents' part of the path ends and the user created/visible path begins. Because of this, we can't provide any relevant folder/path information. For now, we'll just let the user know that the document was moved.
            updateMessage = NSLocalizedStringFromTableInBundle(@"Document moved.", @"OmniUIDocument", OMNI_BUNDLE, @"Message letting the user know that their document was moved from one folder to another.");
            
        }
        
        return updateMessage;
    }];
}

- (NSString *)_persistentPathForFile;
{
    ODSFileItem *fileItem = self.fileItem;
    if (!fileItem) {
        return nil;
    }
    
    ODSScope *scope = fileItem.scope;
    NSString *scopeIdentifier = scope.identifier;
    NSString *scopeRelativePath;
    if (scope.isExternal) {
        scopeRelativePath = [fileItem.fileURL path];
    } else {
        NSURL *scopeRootURL = scope.documentsURL;
        scopeRelativePath = OFFileURLRelativePath(scopeRootURL, fileItem.fileURL);
    }
    return [NSString stringWithFormat:@"%@/%@", scopeIdentifier, scopeRelativePath];
}

static OFPreference *LastEditsPreference;

- (NSMutableDictionary *)_lastEditsDictionary;
{
    static NSMutableDictionary *lastEdits;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        LastEditsPreference = [OFPreference preferenceForKey:@"OUIDocumentLastEdits" defaultValue:@{}];
        lastEdits = [[LastEditsPreference dictionaryValue] mutableCopy];
        OBASSERT([lastEdits isKindOfClass:[NSMutableDictionary class]]);
    });
    OBPOSTCONDITION([lastEdits isKindOfClass:[NSMutableDictionary class]]);
    return lastEdits;
}

- (NSDate *)_lastRecordedEditDate;
{
    NSMutableDictionary *lastEdits = [self _lastEditsDictionary];
    NSString *path = [self _persistentPathForFile];
    if (!path)
        return nil;
    return [lastEdits objectForKey:path];
}

- (void)_recordLastEdit;
{
    NSMutableDictionary *lastEdits = [self _lastEditsDictionary];
    NSDate *modDate = self.fileModificationDate;
    if (!modDate) {
        // New document; the code we are calling likes to have a placeholder date.
        modDate = [NSDate date];
    }

    NSString *path = [self _persistentPathForFile];
    if (path)
        [lastEdits setObject:modDate forKey:path];
    [LastEditsPreference setDictionaryValue:lastEdits];
}

- (nullable NSString *)_lastEditedMessage;
{
    NSDate *lastRecordedEditDate = [self _lastRecordedEditDate];
    NSURL *url = self.fileURL;
    NSString *editDateString;
    __autoreleasing NSDate *editDate;
    NSURL *securedURL = nil;
    if ([url startAccessingSecurityScopedResource])
        securedURL = url;
    BOOL foundEditDate = [url getResourceValue:&editDate forKey:NSURLContentModificationDateKey error:NULL];
    [securedURL stopAccessingSecurityScopedResource];
    if (!foundEditDate) {
        return nil; // We don't know when this URL was last modified, so let's skip it
    }

    static OFRelativeDateFormatter *relativeDateFormatter;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        relativeDateFormatter = [[OFRelativeDateFormatter alloc] init];
        [relativeDateFormatter setFormatterBehavior:NSDateFormatterBehavior10_4];
        OBASSERT([relativeDateFormatter formatterBehavior] == NSDateFormatterBehavior10_4);
        [relativeDateFormatter setDateStyle:NSDateFormatterShortStyle];
        [relativeDateFormatter setTimeStyle:NSDateFormatterShortStyle];
        [relativeDateFormatter setUseRelativeDayNames:YES];
    });

    editDateString = [relativeDateFormatter stringForObjectValue:editDate];
    NSString *lastEditFormat;
    if (lastRecordedEditDate == nil) {
        lastEditFormat = NSLocalizedStringFromTableInBundle(@"Last edit: %@", @"OmniUIDocument", OMNI_BUNDLE, @"Notice for the user about the last edit to a document (unknown device)");
    } else if (OFISEQUAL(lastRecordedEditDate, editDate)) {
        lastEditFormat = NSLocalizedStringFromTableInBundle(@"Last edit: %@ on this device", @"OmniUIDocument", OMNI_BUNDLE, @"Notice for the user about the last edit to a document (this device)");
    } else {
        lastEditFormat = NSLocalizedStringFromTableInBundle(@"Last edit: %@ on another device", @"OmniUIDocument", OMNI_BUNDLE, @"Notice for the user about the last edit to a document (another device)");
    }
    
    NSString *lastEditMessage = [NSString stringWithFormat:lastEditFormat, editDateString];
    return lastEditMessage;
}

#pragma mark -
#pragma mark Subclass responsibility

- (UIViewController <OUIDocumentViewController> *)makeViewController;
{
    OBRequestConcreteImplementation(self, _cmd);
}
- (void)updateViewControllerToPresent;
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
    return _documentViewController.view;
}

- (NSString *)alertTitleForIncomingEdit;
{
    return NSLocalizedStringFromTableInBundle(@"Document Updated", @"OmniUIDocument", OMNI_BUNDLE, @"Title for alert informing user that the document has been reloaded with edits from another device");
}

- (id)tearDownViewController;
{
    id state = [self willRebuildViewController];
    [_documentViewController.view endEditing:YES];
    [_documentViewController.view removeFromSuperview];
    [_documentViewController removeFromParentViewController];
    _documentViewController = nil;
    return state;
}

- (void)recreateViewControllerWithViewState:(id)viewState;
{
    _documentViewController = [self makeViewController];
    _documentViewController.document = self;
    [self didRebuildViewController:viewState];
    [self updateViewControllerToPresent];
    [self _updateUndoIndicator];

    [self.defaultFirstResponder becomeFirstResponder]; // Likely the document view controller itself
}

- (NSDictionary *)willRebuildViewController;
{
    [[OUIDocumentAppController controller] documentWillRebuildViewController:self];
    return [NSDictionary dictionary];
}

- (void)didRebuildViewController:(NSDictionary *)state;
{
    [[OUIDocumentAppController controller] documentDidRebuildViewController:self];
}

- (void)_syncCurrentScope;
{
    OFXDocumentStoreScope *scope = (OFXDocumentStoreScope *)_documentScope;
    OBASSERT([scope isKindOfClass:[OFXDocumentStoreScope class]]); // Or we shouldn't have called this method

    [scope.syncAgent sync:^{}];
}

- (void)_manualSync:(id)sender;
{
    OFXDocumentStoreScope *scope = (OFXDocumentStoreScope *)_documentScope;
    OBASSERT([scope isKindOfClass:[OFXDocumentStoreScope class]]); // Or we shouldn't have called this method

    OFXAgentActivity *agentActivity = [OUIDocumentAppController controller].agentActivity;
    OFXAccountActivity *activity = [agentActivity activityForAccount:scope.account];
    OBASSERT(activity);
    
    NSError *lastSyncError = activity.lastError;
    if (lastSyncError != nil) {
        [[OUIDocumentAppController controller] presentSyncError:lastSyncError forAccount:scope.account inViewController:self.documentViewController retryBlock:^{
            [self _syncCurrentScope];
        }];
        return;
    } else if ([self hasUnsavedChanges]) {
        [self autosaveWithCompletionHandler:^(BOOL success){
            if (success) {
                [self _syncCurrentScope];
            }
        }];
    } else {
        [self _syncCurrentScope];
    }
}

#pragma mark - Preview support

+ (OUIImageLocation *)placeholderPreviewImageForFileURL:(NSURL *)fileURL area:(OUIDocumentPreviewArea)area;
{
//    OBFinishPortingLater("bug:///138402 (iOS-OmniGraffle Crasher: Crash when closing a document)");
//    return nil;
    OBRequestConcreteImplementation(self, _cmd);
}

+ (OUIImageLocation *)encryptedPlaceholderPreviewImageForFileURL:(NSURL *)fileURL area:(OUIDocumentPreviewArea)area;
{
    OBRequestConcreteImplementation(self, _cmd);
}

+ (void)writePreviewsForDocument:(OUIDocument *)document withCompletionHandler:(void (^)(void))completionHandler;
{
    // Subclass responsibility
    OBRequestConcreteImplementation(self, _cmd);
}

#pragma mark -
#pragma mark Internal

- (void)_willBeRenamedLocally;
{
    // Terrible hack to avoid our alert when renaming an open document. When we rename a document via the toolbar item, the ODSFileItem gets renamed. This pokes NSFilePresenter methods on the open document to update its fileURL. If the rename originates locally, we call this which squelches this sort of alert locally. Sadly, UIDocument doesn't have a cleaner way to rename a local open document (that I know of).
    _lastLocalRenameTime = CFAbsoluteTimeGetCurrent();
}

- (void)_writePreviewsIfNeeded:(BOOL)onlyIfNeeded fileEdit:(OFFileEdit *)fileEdit withCompletionHandler:(void (^)(void))completionHandler;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    // This doesn't work -- what we want is 'has been opened and has reasonable content'. When writing previews when closing and edited document, this will be UIDocumentStateClosed, but when writing previews due to an incoming iCloud change or document dragged in from iTunes, this will be UIDocumentStateNormal.
    //OBPRECONDITION(self.documentState == UIDocumentStateNormal);

    if (onlyIfNeeded && [OUIDocumentPreview hasPreviewsForFileEdit:fileEdit]) {
        if (completionHandler)
            completionHandler();
        return;
    }
    
    // First, write an empty data file each preview, in case preview writing fails.
    [OUIDocumentPreview writeEmptyPreviewsForFileEdit:fileEdit];
    
    DEBUG_PREVIEW_GENERATION(1, @"Writing previews for %@ at %@", fileEdit.originalFileURL, [fileEdit.fileModificationDate xmlString]);
    
    [[self class] writePreviewsForDocument:self withCompletionHandler:completionHandler];
}

#pragma mark -
#pragma mark Private

- (void)_willSave;
{
    BOOL hadUndoGroupOpen = _hasUndoGroupOpen;
    
    // This may make a new top level undo group that wouldn't get closed until after the autosave finishes and returns to the event loop. If we had no such top-level undo group before starting the save (we were idle in the event loop when an autosave or close fired up), we want to ensure our save operation also runs with a closed undo group (might be some app-specific logic in -willFinishUndoGroup that does additional edits).
    if ([_documentViewController respondsToSelector:@selector(documentWillSave)])
        [_documentViewController documentWillSave];
    
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
    if (!_undoIndicator && [[self class] shouldShowAutosaveIndicator] && [_documentViewController isViewLoaded]) {
        _undoIndicator = [[OUIUndoIndicator alloc] initWithParentView:_documentViewController.view];
        if (_documentViewController.navigationController.isNavigationBarHidden == NO) {
            _undoIndicator.frameYOffset = CGRectGetMaxY([_documentViewController.navigationController.navigationBar frame]);
        }
    }
    
    _undoIndicator.groupingLevel = [self.undoManager groupingLevel];
    _undoIndicator.hasUnsavedChanges = [self hasUnsavedChanges];
    _undoIndicator.undoIsEnabled = self.undoManager.isUndoRegistrationEnabled;
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
    OBASSERT(self.forPreviewGeneration == NO); // Make sure we don't provoke a save due to just opening a document to make a preview!

    DEBUG_UNDO(@"%@ level:%ld", [note name], [self.undoManager groupingLevel]);
    
    // Immediately open a nested group. This will allows NSUndoManager to automatically open groups for us on the first undo operation, but prevents it from closing the whole group.
    if ([self.undoManager groupingLevel] == 1) {
        DEBUG_UNDO(@"  ... nesting");
        _hasUndoGroupOpen = YES;
        [self.undoManager beginUndoGrouping];
        
        // Let our view controller know, if it cares (may be able to delete this now, graffle no longer uses it)
        if ([_documentViewController respondsToSelector:@selector(documentDidOpenUndoGroup)])
            [_documentViewController documentDidOpenUndoGroup];
        
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

///  A block that is envoked on the main thread that returns any type of 'update' message to be displayed. (Ex. last updated date/time or if the documet is moved/renamed.)
typedef NSString * (^MessageProvider)(void);

/// Enqueues an MessageProvider onto the main queue.
- (void)_queueUpdateMessageProvider:(MessageProvider)messageProvider;
{
    OBPRECONDITION(messageProvider != nil);
    OBPRECONDITION(!_accommodatingDeletion);
    
    if (messageProvider == nil || self.forPreviewGeneration) {
        // No point in doing any of thise if we don't acutally have a message to show or if we aren't a user-visible open document
        return;
    }
    
    messageProvider = [messageProvider copy];
    
    // See commentary in -_willBeRenamedLocally about this hack.
    if (CFAbsoluteTimeGetCurrent() - _lastLocalRenameTime < 5) {
        return;
    }
    
    __weak typeof(self) weakSelf = self;
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if ([strongSelf shouldShowUpdateMessage] == NO) {
            return;
        }

        // Cancel any current alert.
        self.lastQueuedUpdateMessage = nil;
        [self dismissUpdateMessage];
        
        // We verify that messageBlock is non-nil above, so we don't need to check here before calling.
        NSString *message = messageProvider();

        // Queue up new message.
        self.lastQueuedUpdateMessage = message;
        
        // Only displays new message if we aren't in the middle of -relinquishPresentedItemToWriter:. We'll try again in -enableEditing
        if (self.editingDisabled == NO && self.viewControllerToPresent.isViewLoaded) {
            [self displayLastQueuedUpdateMessage];
        }
    }];
}

- (BOOL)shouldShowUpdateMessage;
{
    return NO;
}

- (void)displayLastQueuedUpdateMessage NS_REQUIRES_SUPER;
{
    OBASSERT([NSThread isMainThread]);
    OBASSERT(self.lastQueuedUpdateMessage != nil);
    
    OBASSERT(self.viewControllerToPresent.isViewLoaded);
    OBASSERT(self.shieldView == nil);
    
    self.shieldView = [OUIShieldView shieldViewWithView:self.viewControllerToPresent.view];
    self.shieldView.delegate = self;
    self.shieldView.shouldForwardAllEvents = YES;
    [self.viewControllerToPresent.view addSubview:self.shieldView];
}

- (void)dismissUpdateMessage NS_REQUIRES_SUPER;
{
    OBASSERT([NSThread isMainThread]);
    
    self.lastQueuedUpdateMessage = nil;
    
    [self.shieldView removeFromSuperview];
    self.shieldView = nil;
}

#pragma mark OUIShieldViewDelegate
- (void)shieldViewWasTouched:(OUIShieldView *)shieldView;
{
    [self dismissUpdateMessage];
}

#pragma mark OFDocumentEncryption (OFCMSKeySource)

- (NSString *)promptForPasswordWithCount:(NSInteger)previousFailureCount hint:(NSString *)passwordHint error:(NSError * _Nullable __autoreleasing *)outError;
{
    if ([NSThread isMainThread]) {
        OBFinishPortingWithNote("<bug:///147831> (iOS-OmniOutliner Bug: OUIDocument.m:1692: Show prompt in promptForPasswordWithCount:hint:error: when in main thread)");
    }
    
    OUIDocumentEncryptionPassphrasePromptOperation *prompt = [[OUIDocumentEncryptionPassphrasePromptOperation alloc] init];
    prompt.document = self;
    // TOOD: Password hint.
    
    [[[OUIAppController controller] backgroundPromptQueue] addOperation:prompt];
    
    [prompt waitUntilFinished];
    
    NSString *result = prompt.password;
    if (result) {
        return result;
    } else {
        if (outError)
            *outError = prompt.error;
        return nil;
    }
}

- (BOOL)isUserInteractionAllowed;
{
    return !self.forPreviewGeneration;
}

@end

@implementation OUIDocumentEncryptionPassphrasePromptOperation
{
    OUIDocument * __weak document;
    NSString *enteredPassword;
    NSError *enteredError;
}

@synthesize document = document,
error = enteredError,
password = enteredPassword;

- (void)start;
{
    [super start];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        ODSItem *fileItem;
        UIViewController *presenter;
        
        {
            OUIDocument *strongDoc = self.document;

            if (!strongDoc || self.cancelled) {
                enteredError = [NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError userInfo:nil];
                [self finish];
                return;
            }
            
            fileItem = strongDoc.fileItem;
            presenter = strongDoc.documentViewController;

        }

        BOOL needToChangeUserInteractionEnabled = NO;
        UINavigationController *navController = nil;
        if (!presenter) {
            UIWindow *window = [[[UIApplication sharedApplication] delegate] window];
            presenter = [window rootViewController];
            BOOL userinteractionEnabled = window.userInteractionEnabled;
            UIViewController *presentedViewController = [presenter presentedViewController];
            if (presentedViewController) {
                if ([presentedViewController isKindOfClass:UINavigationController.class]) {
                    navController = (UINavigationController *)presentedViewController;
                    presenter = navController.topViewController;
                } else {
                    presenter = presentedViewController;
                }
                if (!userinteractionEnabled) {
                    window.userInteractionEnabled = YES;
                    needToChangeUserInteractionEnabled = YES;
                }
            }
        }

        NSString *promptMessage = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"The document \"%@\" requires a password to open.", @"OmniUIDocument", OMNI_BUNDLE, @"dialog box title when prompting for the password/passphrase for an encrypted document - parameter is the display-name of the file being opened"),
                                   fileItem.name];
        
        OUIPasswordAlert *dialog = [[OUIPasswordAlert alloc] initWithTitle:promptMessage options:0];

        dialog.finished = ^(OUIPasswordAlert *a, OUIPasswordAlertAction action){
            switch (action) {
                default:
                case OUIPasswordAlertActionCancel:
                    enteredError = [NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError userInfo:nil];
                    break;
                case OUIPasswordAlertActionLogIn:
                    enteredPassword = a.password;
                    break;
            }
            if (needToChangeUserInteractionEnabled) {
                UIWindow *window = [[[UIApplication sharedApplication] delegate] window];
                window.userInteractionEnabled = NO;
            }
            [self finish];
        };

        [self.document.applicationLock unlock];
        self.document.applicationLock = nil;
        [dialog showFromController:presenter];
    });
}

@end


// A helper function to centralize the check for -openWithCompletionHandler: leaving the document 'open-ish' when it fails.
// Radar 10694414: If UIDocument -openWithCompletionHandler: fails, it is still a presenter
void OUIDocumentHandleDocumentOpenFailure(OUIDocument *document, void (^completionHandler)(BOOL success))
{
    OBASSERT([NSThread isMainThread]);
    
    // Failed to read the document. The error will have already been presented via OUIDocument's -handleError:userInteractionPermitted:.
    OBASSERT(document.documentState == (UIDocumentStateClosed|UIDocumentStateSavingError)); // don't have to close it here.
    
    // Make sure UIDocument didn't leak a file presenter registration. It did in 5.x, but that was fixed in 6.0 (which we require now).
    OBASSERT([[NSFileCoordinator filePresenters] indexOfObjectIdenticalTo:document] == NSNotFound);
    if (completionHandler)
        completionHandler(NO); // Still need to call this (document preview generation passes a non-nil completion block, for example).
}

OFSaveType OFSaveTypeForUIDocumentSaveOperation(UIDocumentSaveOperation saveOperation)
{
    switch (saveOperation) {
        case UIDocumentSaveForCreating:
            return OFSaveTypeNew;
        case UIDocumentSaveForOverwriting:
            return OFSaveTypeReplaceExisting;
        default:
            OBASSERT_NOT_REACHED("Unknown save operation %lu", (unsigned long)saveOperation);
            return OFSaveTypeReplaceExisting;
    }
}
