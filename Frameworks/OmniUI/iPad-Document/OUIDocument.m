// Copyright 2010-2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUIDocument/OUIDocument.h>

@import OmniFoundation;
@import OmniFileExchange;
@import OmniUI;

#import <OmniUIDocument/OUIDocumentViewController.h>
#import <OmniUIDocument/OUIDocumentAppController.h>
#import <OmniUIDocument/OUIDocumentSceneDelegate.h>

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

#if DEBUG_DOCUMENT_DEFINED
#import <libkern/OSAtomic.h>
static int32_t OUIDocumentInstanceCount = 0;
#endif

@interface OUIDocument () <OUIShieldViewDelegate>
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
@property (nonatomic, strong) NSString *hint;
@end

@implementation OUIDocument
{
    UIViewController <OUIDocumentViewController> *_documentViewController;
    OUIUndoIndicator *_undoIndicator;
    
    void (^_savedCloseCompletionBlock)(BOOL success);
    
    BOOL _hasUndoGroupOpen;
    BOOL _forPreviewGeneration;
    BOOL _editingDisabled;
    __weak UIView *_viewWithUserInteractionDisabled;
    
    id _rebuildingViewControllerState;
    
    NSUInteger _requestedViewStateChangeCount; // Used to augment the normal autosave.
    NSUInteger _savedViewStateChangeCount;
    
    BOOL _accommodatingDeletion;
    NSURL *_originalURLPriorToAccomodatingDeletion;
    
    BOOL _inRelinquishPresentedItemToWriter;
    NSURL *_originalURLPriorToPresentedItemDidMoveToURL;
    void (^_afterCloseRelinquishToWriter)(void (^reacquire)(void));
    
    NSURL *_securityScopedURL;
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

+ (NSURL *)builtInBlankTemplateURL;
{
    return nil;
}

+ (BOOL)shouldImportFileAtURL:(NSURL *)fileURL;
{
    return NO;
}

+ (BOOL)shouldShowAutosaveIndicator;
{
    return [[OFPreference preferenceForKey:@"OUIDocumentShouldShowAutosaveIndicator" defaultValue:@(NO)] boolValue];
}

// existing document
- (instancetype)initWithExistingFileURL:(NSURL *)fileURL error:(NSError **)outError;
{
    OBPRECONDITION(fileURL);

    return [self initWithFileURL:fileURL error:outError];
}

- (instancetype)initWithContentsOfTemplateAtURL:(NSURL *)templateURLOrNil toBeSavedToURL:(NSURL *)saveURL activityViewController:(UIViewController *)activityViewController error:(NSError **)outError;
{
    OBPRECONDITION(![NSThread isMainThread], "Subclassers are supposed to read the template, so this should be on a background queue.");
    
    self = [self initWithFileURL:saveURL error:outError];
    self.activityViewController = activityViewController;

    if (self != nil && [templateURLOrNil startAccessingSecurityScopedResource]) {
        [templateURLOrNil stopAccessingSecurityScopedResource];
        _securityScopedURL = templateURLOrNil;
    }

    return self;
}

- (instancetype)initWithContentsOfImportableFileAtURL:(NSURL *)importableURL toBeSavedToURL:(NSURL *)saveURL error:(NSError **)outError;
{
    OBPRECONDITION(![NSThread isMainThread], "Subclassers are supposed to read the contents at importableURL, so this should be on a background queue.");

    // We should not be opened, but we want to be able to save to where we *will* be located.
    return [self initWithFileURL:saveURL error:outError];
}

- (instancetype)initEmptyDocumentToBeSavedToURL:(NSURL *)url error:(NSError **)outError;
{
    return [self initWithFileURL:url error:outError];
}

// Use one of our two initializers
- (instancetype)initWithFileURL:(NSURL *)fileURL;
{
    OBRejectUnusedImplementation(self, _cmd);
    return nil;
}

- (instancetype)initWithFileURL:(NSURL *)fileURL error:(NSError **)outError;
{
    DEBUG_DOCUMENT(@"INIT %p with %@", self, fileURL);
    OBRecordBacktraceWithContext("Init", OBBacktraceBuffer_Generic, (__bridge const void *)self);

    OBPRECONDITION(fileURL);

#ifdef OMNI_ASSERTIONS_ON
    Class implementingClass = OBClassImplementingMethod([self class], @selector(initEmptyDocumentToBeSavedToURL:error:));
    OBPRECONDITION([NSStringFromClass(implementingClass) hasPrefix:@"OUI"], "Should subclass -initEmptyDocumentToBeSavedToURL:templateURL:error:");
#endif
    
    if (!(self = [super initWithFileURL:fileURL]))
        return nil;
    
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

    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(_inspectorDidEndChangingInspectedObjects:) name:OUIInspectorDidEndChangingInspectedObjectsNotification object:nil];
    [center addObserver:self selector:@selector(_updateUndoIndicator) name:OFUndoManagerEnablednessDidChangeNotification object:self.undoManager];

    return self;
}

- (void)dealloc;
{
#if DEBUG_DOCUMENT_DEFINED
    int32_t count = OSAtomicDecrement32Barrier(&OUIDocumentInstanceCount);
    DEBUG_DOCUMENT(@"DEALLOC %p (count %d)", self, count);
#endif
    OBASSERT(_accommodatingDeletion == NO);
    OBASSERT(_originalURLPriorToAccomodatingDeletion == nil);
    OBASSERT(_afterCloseRelinquishToWriter == nil);
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    _documentViewController.document = nil;
    
    // UIView cannot get torn down on background threads. Capture these in locals to avoid the block doing a -retain on us while we are in -dealloc
    UIViewController *viewController = _documentViewController;
    OBStrongRetain(viewController);
    _documentViewController = nil;
    
    OUIUndoIndicator *undoIndicator = _undoIndicator;
    OBStrongRetain(undoIndicator);
    _undoIndicator = nil;
    
    main_sync(^{
        OBStrongRelease(viewController);
        OBStrongRelease(undoIndicator);
    });
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

    NSUndoManager *undoManager = self.undoManager;

    DEBUG_UNDO(@"finishUndoGroup");
    OBRecordBacktraceWithContext("Finish undo group", OBBacktraceBuffer_Generic, (__bridge const void *)undoManager);

    if ([_documentViewController respondsToSelector:@selector(documentWillCloseUndoGroup)])
        [_documentViewController documentWillCloseUndoGroup];
    
    [self willFinishUndoGroup];
    
    // Our group might be the only one open, but the auto-created group might be open still too (for example, with a single-event action like -delete:)
    OBASSERT([undoManager groupingLevel] >= 1);
    _hasUndoGroupOpen = NO;
    
    // This should drop the count to zero, provoking an -updateChangeCount:UIDocumentChangeDone
    [undoManager endUndoGrouping];
    
    // If the edit started in this cycle of the runloop, the automatic group opened by the system may not have closed and any following edits will get grouped with it.
    if ([undoManager groupingLevel] > 0) {
        OBASSERT([undoManager groupingLevel] == 1);

        // Terrible hack to let the by-event undo group close, plus a check that the hack worked...
        OBASSERT([undoManager.runLoopModes containsObject:OUIDocumentUndoManagerRunLoopPrivateMode]);
        [[NSRunLoop currentRunLoop] runMode:OUIDocumentUndoManagerRunLoopPrivateMode beforeDate:[NSDate distantPast]];
    }

    OBPOSTCONDITION([undoManager groupingLevel] == 0);
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
    OBASSERT_NOTNULL(editorStateCount);
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
    OBRecordBacktraceWithContext("Open started", OBBacktraceBuffer_Generic, (__bridge const void *)self);

    if ([[OFPreference preferenceForKey:@"OUIDocumentAutoresolvesConflicts" defaultValue:@(NO)] boolValue])
          [self _autoresolveConflicts];

    __weak OUIDocument *welf = self;
    [super openWithCompletionHandler:^(BOOL success){
        OBRecordBacktraceWithContext("Open completion", OBBacktraceBuffer_Generic, (__bridge const void *)self);

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
    OBRecordBacktraceWithContext("Close started", OBBacktraceBuffer_Generic, (__bridge const void *)self);

    if (!self.isDefinitelyClosing && (self.documentState & UIDocumentStateClosed) != 0) {
        OBRecordBacktraceWithContext("Close already closed", OBBacktraceBuffer_Generic, (__bridge const void *)self);

        // we may be being asked to close before we have finished opening.  note that and save the completion handler for when we can actually close.
        // we will close if/when we have successfully opened.
        _savedCloseCompletionBlock = [completionHandler copy];
        if (!_savedCloseCompletionBlock) {
            _savedCloseCompletionBlock = ^(BOOL success){};  // we depend on this block being non-nil to know that we need to close as soon as we've opened.
        }
        return;
    }
    
    DEBUG_DOCUMENT(@"%@ %@", [self shortDescription], NSStringFromSelector(_cmd));

    OUIWithoutAnimating(^{
        // If the user is just switching to another app quickly and coming right back (maybe to paste something at us), we don't want to end editing.
        // Instead, we should commit any partial edits, but leave the editor up.
        
        OBASSERT_IF(self.forPreviewGeneration, self.hasUnsavedChanges == NO, "Don't modify a document while generating a preview");
        
        [self _willSave];

        if (!self.forPreviewGeneration && _documentViewController != nil) {
            // When saving, we don't end editing since the user might just be switching to another app quickly and coming right back (maybe to paste something at us). But here we are closing and should commit our edits and shut down the field editor. The edits should have been committed when we were backgrounded, but it is nicer to clean up any editor here before views get removed from the view hierarchy.
            // However, do this in a way that doesn't actually provoke view loading if it wasn't previously necessary (e.g. `_documentViewController` was created by side effect for printing, sharing, etc.).
            UIView *viewControllerToPresentView = self.viewControllerToPresent.isViewLoaded ? self.viewControllerToPresent.view : nil;
            [viewControllerToPresentView endEditing:YES];
            [viewControllerToPresentView layoutIfNeeded];
        }

        // Make sure -setNeedsDisplay calls (provoked by -_willSave) have a chance to get flushed before we invalidate the document contents
        OUIDisplayNeededViews();
    });

    if (_hasUndoGroupOpen) {
        OBASSERT([self.undoManager groupingLevel] == 1);
        [self.undoManager endUndoGrouping];
    }
    
    // The closing path will save using the autosaveWithCompletionHandler:. We need to be able to tell if we should do a real full non-autosave write though.
    OBASSERT(_isClosing == NO);
    _isClosing = YES;
    
    completionHandler = [completionHandler copy];
    
    // Make sure that if the app is backgrounded, we don't get left in the middle of a close operation (still being a file presenter) where the user could delete us (via iTunes or iCloud) and then on foregrounding of the app UIDocument can get confused.
    OFBackgroundActivity *activity = [OFBackgroundActivity backgroundActivityWithIdentifier:@"com.omnigroup.OmniUI.OUIDocument.close"];

    void (^closedCompletion)(BOOL success) = ^void(BOOL success) {
        DEBUG_DOCUMENT(@"%@ %@ success %d", [self shortDescription], NSStringFromSelector(_cmd), success);
        OBRecordBacktraceWithContext("Close completion", OBBacktraceBuffer_Generic, (__bridge const void *)self);

        [self _updateUndoIndicator];

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

        [activity finished];
    };

    if ((self.documentState & UIDocumentStateClosed) != 0) {
        OBRecordBacktraceWithContext("Close already closed 2", OBBacktraceBuffer_Generic, (__bridge const void *)self);
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
    OBRecordBacktraceWithContext("Autosave start", OBBacktraceBuffer_Generic, (__bridge const void *)self);

    if ([self hasUnsavedChanges]) { // If we somehow end up here with unsaved changes, don't call -_willSave.
        [self _willSave];
    }

    [super autosaveWithCompletionHandler:^(BOOL success){
        DEBUG_UNDO(@"  Autosave success = %d", success);
        OBRecordBacktraceWithContext("Autosave completed", OBBacktraceBuffer_Generic, (__bridge const void *)self);

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
    OBRecordBacktraceWithContext("Save start", OBBacktraceBuffer_Generic, (__bridge const void *)self);

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
    
    OBASSERT(!OFIsInInbox(url));
    
    // In iOS 5, when backgrounding the app, the -autosaveWithCompletionHandler: method would be called. In iOS 6, this is called directly.
    [self _willSave];

    completionHandler = [completionHandler copy];

    BOOL isChangingFileType = !OFISEQUAL(self.fileType, self.savingFileType);
    BOOL shouldRemoveCachedResourceValue = ((saveOperation == UIDocumentSaveForOverwriting) && isChangingFileType);

    OBASSERT_NULL(_currentSaveURL);
    _currentSaveOperation = saveOperation;
    _currentSaveURL = [url copy];

    [super saveToURL:url forSaveOperation:saveOperation completionHandler:^(BOOL success) {
        DEBUG_DOCUMENT(@"  save success %d", success);
        OBRecordBacktraceWithContext("Save completed", OBBacktraceBuffer_Generic, (__bridge const void *)self);

        OBASSERT_NOTNULL(_currentSaveURL);
        _currentSaveURL = nil;

        if (success) {
            if (shouldRemoveCachedResourceValue) {
                OBASSERT(url);

                // NSURL caches resource values that it has retrieved and OFUTIForFileURLPreferringNative() uses the resource values to determine the UTI. If we're going to change the file from flat to package (most likely case this is happening) then we need to clear the cache for the 'is directory' flag so that OFUTIForFileURLPreferringNative() returns the correct UTI next time we try to open the document. By the way, the NSURL documentation states that it's resource value cache is cleared at the turn of each runloop, but clearly it's not. Will try to repro and file a radar.
                [url removeCachedResourceValueForKey:NSURLIsDirectoryKey];
            }
        }

        if (completionHandler)
            completionHandler(success);
    }];
}

- (void)accessSecurityScopedResourcesForBlock:(void (^ NS_NOESCAPE)(void))block;
{
    @autoreleasepool {
        if (_securityScopedURL != nil && ![_securityScopedURL startAccessingSecurityScopedResource])
            _securityScopedURL = nil;
        @try {
            block();
        } @finally {
            [_securityScopedURL stopAccessingSecurityScopedResource];
        }
    }
}

- (void)disableEditing;
{
    OBPRECONDITION([NSThread isMainThread]);
    OBPRECONDITION(_editingDisabled == NO);
    
    DEBUG_DOCUMENT(@"Disable editing");
    OBRecordBacktraceWithContext("Disable editing", OBBacktraceBuffer_Generic, (__bridge const void *)self);
    _editingDisabled = YES;
    
    if (_rebuildingViewControllerState != nil || self.forPreviewGeneration)
        return;

    OUIWithoutAnimating(^{
        // Incoming edit from the cloud, most likely. We should have been asked to save already via the coordinated write (might produce a conflict). Still, lets make sure we aren't editing.
        [_documentViewController.view endEditing:YES];
        [self.defaultFirstResponder becomeFirstResponder]; // Likely the document view controller itself
    });

    [self _disableUserInteraction];
}

- (void)_disableUserInteraction;
{
    [self _reenableUserInteraction]; // Make sure we don't accidentally leave user interaction disabled on a view we're not tracking.

    // Disable interaction not only on our documentViewController (because it may be contained within another view controller) but on the viewController used for our presentation.
    UIView *viewToDisable = self.viewControllerToPresent.view;
    viewToDisable.userInteractionEnabled = NO;
    _viewWithUserInteractionDisabled = viewToDisable;
}

- (void)_reenableUserInteraction;
{
    UIView *viewWithUserInteractionDisabled = _viewWithUserInteractionDisabled;
    if (viewWithUserInteractionDisabled != nil) {
        // Re-enable interaction on the view we disabled earlier
        viewWithUserInteractionDisabled.userInteractionEnabled = YES;
        _viewWithUserInteractionDisabled = nil;
    }
}

- (void)enableEditing;
{
    OBPRECONDITION([NSThread isMainThread]);
    OBPRECONDITION(_editingDisabled == YES);
    
    DEBUG_DOCUMENT(@"Enable editing");
    OBRecordBacktraceWithContext("Enable editing", OBBacktraceBuffer_Generic, (__bridge const void *)self);
    _editingDisabled = NO;

    if (_rebuildingViewControllerState != nil)
        return; // Let's keep editing disabled until we finish rebuilding our view controller

    [self _reenableUserInteraction];

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
    OBRecordBacktraceWithContext("Handle error", OBBacktraceBuffer_Generic, (__bridge const void *)self);

    if (_forPreviewGeneration) {
        // Just log it instead of popping up an alert for something the user didn't actually poke to open anyway.
        [error log: @"Error while generating preview for %@", [self.fileURL absoluteString]];
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

        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            UIViewController *errorViewController = _documentViewController;
            if (errorViewController == nil) {
                NSArray <OUIDocumentSceneDelegate *> *sceneDelegates = [OUIDocumentSceneDelegate documentSceneDelegatesForDocument:self];
                errorViewController = sceneDelegates.firstObject.window.rootViewController;
            }

            //<bug:///178851> (iOS-OmniGraffle Bug: Can't create new document with many cloud storage providers [Dropbox, OneDrive, GoogleDrive, file package, error])
            if (([error.domain isEqualToString:@"com.google.DriveKit"] && error.code == 11) || ([[[error.userInfo valueForKey:@"NSUnderlyingError"] domain] isEqualToString:@"com.google.DriveKit"] && [[error.userInfo valueForKey:@"NSUnderlyingError"] code] == 11)) {
                [OUIAppController presentError:error fromViewController:errorViewController cancelButtonTitle:nil optionalActionTitle:nil optionalAction:nil];
            } else {
                OUI_PRESENT_ALERT_FROM(error, errorViewController); // Note: If we don't have a view controller yet, this will present the error the next time a scene becomes active
            }
        }];
    } else {
        [error log:@"Error encountered by document"];
    }
    
    [self finishedHandlingError:error recovered:NO];
}

- (void)userInteractionNoLongerPermittedForError:(NSError *)error;
{
    // Since we subclass -handleError:userInteractionPermitted:, we have to implement this too, according to the documentation.
    DEBUG_DOCUMENT(@"%s:%d -- %s", __FILE__, __LINE__, __PRETTY_FUNCTION__);
    OBRecordBacktraceWithContext("Interaction not allowed for error", OBBacktraceBuffer_Generic, (__bridge const void *)self);
    [super userInteractionNoLongerPermittedForError:error];
}

- (void)_failRevertAndCloseAndReturnToDocumentPickerWithCompletionHandler:(void (^)(BOOL success))completionHandler;
{
    OBPRECONDITION(!_forPreviewGeneration); // Otherwise, we'd close some other open document
    
    completionHandler = [completionHandler copy];
    
    // The document may not exist (deletions while we were backgrounded, which don't go through -accommodatePresentedItemDeletionWithCompletionHandler:, but at any rate we can't read it.
    
    NSArray <OUIDocumentSceneDelegate *> *sceneDelegates = [OUIDocumentSceneDelegate documentSceneDelegatesForDocument:self];
    __block NSUInteger remainingDelegatesCount = sceneDelegates.count;
    for (OUIDocumentSceneDelegate *sceneDelegate in sceneDelegates) {
        [sceneDelegate closeDocumentWithCompletionHandler:^{
            [NSOperationQueue.mainQueue addOperationWithBlock:^{
                remainingDelegatesCount--;
                if (remainingDelegatesCount == 0)
                    [self _cleanupAndSignalFailedRevertWithCompletionHandler:completionHandler];
            }];
        }];
    }
}

- (void)_cleanupAndSignalFailedRevertWithCompletionHandler:(void (^)(BOOL success))completionHandler;
{
    OBASSERT((id)completionHandler == [completionHandler copy]); // should have already been promoted to the heap
    
    if (completionHandler)
        completionHandler(NO);
}

- (void)revertToContentsOfURL:(NSURL *)url completionHandler:(void (^)(BOOL success))completionHandler;
{
    completionHandler = [completionHandler copy];
    // On iOS 13, -[UIDocument _applicationDidBecomeActive:] calls this on the "UIDocument File Access (serial)" thread when the file being edited has been modified since the last time the app was active
    [NSOperationQueue.mainQueue addOperationWithBlock:^{
        OBPRECONDITION([NSThread isMainThread]);
        OBPRECONDITION(_rebuildingViewControllerState == nil);

        DEBUG_DOCUMENT(@"%s:%d -- %s %@", __FILE__, __LINE__, __PRETTY_FUNCTION__, url);
        OBRecordBacktraceWithContext("Revert started", OBBacktraceBuffer_Generic, (__bridge const void *)self);

        // If an open document is deleted via iCloud or iTunes, we don't get -accommodatePresentedItemDeletionWithCompletionHandler:. We do this before calling super so that we don't get an error about the missing file.
        __autoreleasing NSError *reachableError = nil;
        if (![url checkResourceIsReachableAndReturnError:&reachableError]) {
            OBRecordBacktraceWithContext("Disable failed", OBBacktraceBuffer_Generic, (__bridge const void *)self);
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

        [super revertToContentsOfURL:url completionHandler:^(BOOL success){
            OBRecordBacktraceWithContext("Revert completed", OBBacktraceBuffer_Generic, (__bridge const void *)self);
            if (!success) {
                __strong OUIDocument *strongDoc = document;
                [strongDoc didFailToRebuildViewController];
                [oldPresentedViewController dismissViewControllerAnimated:NO completion:nil];
                strongDoc.isDefinitelyClosing = YES;
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
                if (!_editingDisabled)
                    [self _reenableUserInteraction];

                [self didRebuildViewController:state];

                [self updateViewControllerToPresent];
            }
        }];
    }];
}

#pragma mark - NSFilePresenter

- (void)relinquishPresentedItemToWriter:(void (^)(void (^reacquirer)(void)))writer;
{
    OBPRECONDITION(_inRelinquishPresentedItemToWriter == NO);
    
    DEBUG_DOCUMENT("Relinquish to writer");
    OBRecordBacktraceWithContext("Relinquish to writer", OBBacktraceBuffer_Generic, (__bridge const void *)self);
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
            OBRecordBacktraceWithContext("Starting to reacquire after writer", OBBacktraceBuffer_Generic, (__bridge const void *)self);

            void (^finishReacquiring)(void) = ^{
                DEBUG_DOCUMENT("Finishing reacquiring after writer");
                OBRecordBacktraceWithContext("Finishing reacquiring after writer", OBBacktraceBuffer_Generic, (__bridge const void *)self);

                OBASSERT(_inRelinquishPresentedItemToWriter == YES);
                _inRelinquishPresentedItemToWriter = NO;
                
                if (superReacquirer)
                    superReacquirer();
            };
            
            if (_originalURLPriorToPresentedItemDidMoveToURL && ((self.documentState & UIDocumentStateClosed) == 0)) {
                NSURL *originalURL = _originalURLPriorToPresentedItemDidMoveToURL;
                _originalURLPriorToPresentedItemDidMoveToURL = nil;
                
                DEBUG_DOCUMENT("Reacquiring sub-items after moving from %@ to %@", originalURL, self.fileURL);
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
    OBRecordBacktraceWithContext("Accomodate deletion started", OBBacktraceBuffer_Generic, (__bridge const void *)self);

    completionHandler = [completionHandler copy];
    
    [super accommodatePresentedItemDeletionWithCompletionHandler:^(NSError *errorOrNil){
        
        DEBUG_DOCUMENT(@"Deletion accomodation completion handler started, errorOrNil: %@", errorOrNil);
        OBRecordBacktraceWithContext("Accomodate deletion completed", OBBacktraceBuffer_Generic, (__bridge const void *)self);
        OBASSERT(![NSThread isMainThread]);
        
        void (^closeFinished)(void) = ^{
            if (completionHandler)
                completionHandler(errorOrNil);
            
            [self.documentViewController.presentedViewController dismissViewControllerAnimated:YES completion:nil];
            
            OBASSERT(_accommodatingDeletion == YES);
            _accommodatingDeletion = NO;
            
            DEBUG_DOCUMENT(@"Finished accomodating deletion of %@ (DELETE)", _originalURLPriorToAccomodatingDeletion);
            _originalURLPriorToAccomodatingDeletion = nil;
        };
        
        // Apparently we can still be in the list of file presenters even after we've closed after generating a preview. If so, no need to do any of the following work, because we're already closed and done with.
        if (([self documentState] & UIDocumentStateClosed) != 0) {
            main_async(^{
                closeFinished();
            });
            return;
        }
        
        closeFinished = [closeFinished copy];

        // By this point, our document has been moved to a ".ubd" Dead Zone, but the document is still open and pointing at that dead file.
        main_async(^{
            // The document will be deleted as soon as we return and call the completion handler (so we can zoom out to its file item).
            NSArray <OUIDocumentSceneDelegate *> *delegates = [OUIDocumentSceneDelegate documentSceneDelegatesForDocument:self];
            if ([delegates count] == 0) {
                OBASSERT_NOT_REACHED("We are still here, so how are we not in the array");
                closeFinished();
            } else {
                OBASSERT([delegates count] == 1);
                [delegates.firstObject closeDocumentWithCompletionHandler:closeFinished];
            }
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
    NSArray <OUIDocumentSceneDelegate *> *sceneDelegates = [OUIDocumentSceneDelegate documentSceneDelegatesForDocument:self];
    for (OUIDocumentSceneDelegate *sceneDelegate in sceneDelegates) {
        [sceneDelegate documentWillRebuildViewController:self];
    }
    return [NSDictionary dictionary];
}

- (void)didRebuildViewController:(NSDictionary *)state;
{
    NSArray <OUIDocumentSceneDelegate *> *sceneDelegates = [OUIDocumentSceneDelegate documentSceneDelegatesForDocument:self];
    for (OUIDocumentSceneDelegate *sceneDelegate in sceneDelegates) {
        [sceneDelegate documentDidRebuildViewController:self];
    }
}

- (void)didFailToRebuildViewController;
{
    NSArray <OUIDocumentSceneDelegate *> *sceneDelegates = [OUIDocumentSceneDelegate documentSceneDelegatesForDocument:self];
    for (OUIDocumentSceneDelegate *sceneDelegate in sceneDelegates) {
        [sceneDelegate documentDidFailToRebuildViewController:self];
    }
}

#pragma mark - Preview support

+ (OUIImageLocation *)placeholderPreviewImageForFileURL:(NSURL *)fileURL area:(OUIDocumentPreviewArea)area;
{
    OBRequestConcreteImplementation(self, _cmd);
}

+ (OUIImageLocation *)encryptedPlaceholderPreviewImageForFileURL:(NSURL *)fileURL area:(OUIDocumentPreviewArea)area;
{
    OBRequestConcreteImplementation(self, _cmd);
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
        _undoIndicator = [OUIUndoIndicator sharedIndicator];
        _undoIndicator.parentView = _documentViewController.view;
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
    NSUndoManager *undoManager = self.undoManager;

    OBRecordBacktraceWithContext("Undo group did undo", OBBacktraceBuffer_Generic, (__bridge const void *)undoManager);
    DEBUG_UNDO(@"%@ level:%ld", [note name], [undoManager groupingLevel]);
    [self _updateUndoIndicator];
}

- (void)_undoManagerDidRedo:(NSNotification *)note;
{
    NSUndoManager *undoManager = self.undoManager;

    OBRecordBacktraceWithContext("Undo group did redo", OBBacktraceBuffer_Generic, (__bridge const void *)undoManager);
    DEBUG_UNDO(@"%@ level:%ld", [note name], [undoManager groupingLevel]);
    [self _updateUndoIndicator];
}

- (void)_undoManagerDidOpenGroup:(NSNotification *)note;
{
    OBASSERT(self.forPreviewGeneration == NO); // Make sure we don't provoke a save due to just opening a document to make a preview!

    NSUndoManager *undoManager = self.undoManager;

    OBRecordBacktraceWithContext("did open", OBBacktraceBuffer_Generic, (__bridge const void *)undoManager);
    DEBUG_UNDO(@"%@ level:%ld", [note name], [undoManager groupingLevel]);
    
    // Immediately open a nested group. This will allows NSUndoManager to automatically open groups for us on the first undo operation, but prevents it from closing the whole group.
    if ([undoManager groupingLevel] == 1) {
        DEBUG_UNDO(@"  ... nesting");
        _hasUndoGroupOpen = YES;
        [undoManager beginUndoGrouping];
        
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
    NSUndoManager *undoManager = self.undoManager;

    OBRecordBacktraceWithContext("will close", OBBacktraceBuffer_Generic, (__bridge const void *)undoManager);
    DEBUG_UNDO(@"%@ level:%ld", [note name], [undoManager groupingLevel]);
    [self _updateUndoIndicator];
}

- (void)_undoManagerDidCloseGroup:(NSNotification *)note;
{
    NSUndoManager *undoManager = self.undoManager;

    OBRecordBacktraceWithContext("did close", OBBacktraceBuffer_Generic, (__bridge const void *)undoManager);
    DEBUG_UNDO(@"%@ level:%ld", [note name], [undoManager groupingLevel]);
    [self _updateUndoIndicator];
}

- (void)_undoManagerCheckpoint:(NSNotification *)note;
{
    NSUndoManager *undoManager = self.undoManager;

    OBRecordBacktraceWithContext("checkpoint", OBBacktraceBuffer_Generic, (__bridge const void *)undoManager);
    DEBUG_UNDO(@"%@ level:%ld", [note name], [undoManager groupingLevel]);
}

- (void)_inspectorDidEndChangingInspectedObjects:(NSNotification *)note;
{
    [self finishUndoGroup];
}

//

+ (NSString *)displayNameForFileURL:(NSURL *)fileURL;
{
    return [self editingNameForFileURL:fileURL];
}

+ (NSString *)editingNameForFileURL:(NSURL *)fileURL;
{
    return [[[fileURL path] lastPathComponent] stringByDeletingPathExtension];
}

+ (NSString *)exportingNameForFileURL:(NSURL *)fileURL;
{
    return [self displayNameForFileURL:fileURL];
}

- (NSString *)editingName;
{
    OBPRECONDITION([NSThread isMainThread]);

    return [[self class] editingNameForFileURL:self.fileURL];
}

- (NSString *)exportingName;
{
    OBPRECONDITION([NSThread isMainThread]);

    return [[self class] exportingNameForFileURL:self.fileURL];
}

+ (NSSet *)keyPathsForValuesAffectingName;
{
    return [NSSet setWithObjects:OFKeyPathWithClass(OUIDocument, fileURL), nil];
}

- (NSString *)name;
{
    return [[self class] displayNameForFileURL:self.fileURL];
}

- (BOOL)canRename;
{
    NSURL *documentURL = self.fileURL.URLByStandardizingPath;
    if (documentURL == nil)
        return NO;

    NSURL *localDocumentsURL = OUIDocumentAppController.sharedController.localDocumentsURL;
    if (localDocumentsURL != nil && [documentURL.path hasPrefix:localDocumentsURL.path]) {
        return YES; // Yes, we can rename documents in our local storage
    }

    NSURL *iCloudDocumentsURL = OUIDocumentAppController.sharedController.iCloudDocumentsURL;
    if (iCloudDocumentsURL != nil && [documentURL.path hasPrefix:iCloudDocumentsURL.path]) {
        return YES; // Yes, we can rename documents in our iCloud documents folder
    }

    return NO;
}

- (void)renameToName:(NSString *)name completionBlock:(void (^)(BOOL success, NSError *error))completionBlock;
{
    // Make sure we don't close the document while the rename is happening, or some such. It would probably be OK with the synchronization API, but there is no reason to allow it.
    OUIInteractionLock *lock = [OUIInteractionLock applicationLock];

    [self performAsynchronousFileAccessUsingBlock:^{
        NSFileManager *manager = [NSFileManager defaultManager];
        NSURL *originalURL = self.fileURL; // Possible we've moved or changed file types since the rename operation started?

        NSString  *newFileName = [name stringByAppendingPathExtension:[originalURL pathExtension]];
        NSURL *newURL = [[originalURL URLByDeletingLastPathComponent] URLByAppendingPathComponent:newFileName];

        __autoreleasing NSError *moveError = nil;

        BOOL success = [manager moveItemAtURL:originalURL toURL:newURL error:&moveError];
        NSError *strongError = success ? nil : moveError;
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            [lock unlock];
            completionBlock(success, strongError);
        }];
    }];
}

+ (NSArray <NSString *> *)availableExportTypesForFileType:(NSString *)fileType isFileExportToLocalDocuments:(BOOL)isFileExportToLocalDocuments;
{
    return nil;
}

- (NSArray <NSString *> *)availableExportTypesToLocalDocuments:(BOOL)isFileExportToLocalDocuments;
{
    return [[self class] availableExportTypesForFileType:self.fileType isFileExportToLocalDocuments:isFileExportToLocalDocuments];
}

#pragma mark OUIShieldViewDelegate
- (void)shieldViewWasTouched:(OUIShieldView *)shieldView;
{
}

#pragma mark OFDocumentEncryption (OFCMSKeySource)

- (NSString *)promptForPasswordWithCount:(NSInteger)previousFailureCount hint:(NSString *)passwordHint error:(NSError * _Nullable __autoreleasing *)outError;
{
    if ([NSThread isMainThread]) {
        OBFinishPortingWithNote("<bug:///147831> (iOS-OmniOutliner Bug: OUIDocument.m:1692: Show prompt in promptForPasswordWithCount:hint:error: when in main thread)");
    }
    
    OUIDocumentEncryptionPassphrasePromptOperation *prompt = [[OUIDocumentEncryptionPassphrasePromptOperation alloc] init];
    prompt.document = self;
    prompt.hint = passwordHint;
    
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
    OUIDocument * __weak _document;
    NSString *_enteredPassword;
    NSError *_enteredError;
}

@synthesize document = _document, error = _enteredError, password = _enteredPassword;

- (void)start;
{
    [super start];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        OUIDocument *strongDoc = self.document;

        UIViewController *parentViewController = strongDoc.activityViewController; // Share/Print activities
        if (parentViewController == nil) {
            // Maybe opening in the document picker.
            OUIDocumentSceneDelegate *sceneDelegate = [[OUIDocumentSceneDelegate documentSceneDelegatesForDocument:strongDoc] firstObject];
            OBASSERT_NOTNULL(sceneDelegate);

            parentViewController = sceneDelegate.window.rootViewController;
        }

        UIViewController *presentedViewController;
        while ((presentedViewController = parentViewController.presentedViewController)) {
            parentViewController = presentedViewController;
        }

        if (!strongDoc || self.cancelled || parentViewController == nil) {
            _enteredError = [NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError userInfo:nil];
            [self finish];
            return;
        }

        NSString *promptMessage;
        if (strongDoc.name != nil) {
            promptMessage = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"The document \"%@\" requires a password to open.", @"OmniUIDocument", OMNI_BUNDLE, @"dialog box title when prompting for the password/passphrase for an encrypted document - parameter is the display-name of the file being opened"),
                                   strongDoc.name];
        }
        else {
            // When OmniGraffle imports an OmniOutliner file, the document we have on hand is not the Outliner document.
            promptMessage = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"The document requires a password to open.", @"OmniUIDocument", OMNI_BUNDLE, @"dialog box title when prompting for the password/passphrase for an encrypted document - parameter is the display-name of the file being opened")];
        }

        OUIPasswordPromptViewController *dialog = [[OUIPasswordPromptViewController alloc] init];
        dialog.title = promptMessage;
        dialog.hintText = _hint;
        dialog.handler = ^(BOOL shouldContinue, NSString *password) {
            if (!shouldContinue) {
                _enteredError = [NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError userInfo:nil];
            } else {
                _enteredPassword = password;
            }
            [self finish];
        };

        [[OUIInteractionLock activeLocks] makeObjectsPerformSelector:@selector(unlock)];
        [parentViewController presentViewController:dialog animated:YES completion:nil];
    });
}

@end


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
