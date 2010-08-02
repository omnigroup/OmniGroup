// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIDocument.h>

#import <OmniUI/OUIDocumentPicker.h>
#import <OmniUI/OUIDocumentProxy.h>
#import <OmniUI/OUIErrors.h>
#import <OmniUI/OUIInspector.h>
#import <OmniUI/OUISingleDocumentAppController.h>
#import <OmniUI/OUIUndoIndicator.h>

RCS_ID("$Id$");

#if 0 && defined(DEBUG)
    #define DEBUG_UNDO(format, ...) NSLog(@"UNDO: " format, ## __VA_ARGS__)
#else
    #define DEBUG_UNDO(format, ...)
#endif

@interface OUIDocument (/*Private*/)
- _initWithProxy:(OUIDocumentProxy *)proxy url:(NSURL *)url error:(NSError **)outError;
- (BOOL)_saveToURL:(NSURL *)url isAutosave:(BOOL)isAutosave error:(NSError **)outError;
- (void)_autosave;
- (void)_autosaveTimerFired:(NSTimer *)timer;
- (void)_startAutosaveAndUpdateUndoButton;
- (void)_undoManagerDidUndoOrRedo:(NSNotification *)note;
- (void)_undoManagerDidOpenGroup:(NSNotification *)note;
- (void)_undoManagerWillCloseGroup:(NSNotification *)note;
@end

@implementation OUIDocument

+ (CFTimeInterval)autosaveTimeInterval;
{
    CFTimeInterval ti = [[NSUserDefaults standardUserDefaults] doubleForKey:@"OUIDocumentAutosaveInterval"];
    if (ti < 1)
        return 15;
    return ti;
}

+ (BOOL)shouldShowAutosaveIndicator;
{
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"OUIDocumentShouldShowAutosaveIndicator"];
}

// existing document
- initWithExistingDocumentProxy:(OUIDocumentProxy *)proxy error:(NSError **)outError;
{
    OBPRECONDITION(proxy);
    OBPRECONDITION(proxy.url);
    
    return [self _initWithProxy:proxy url:proxy.url error:outError];
}

- initEmptyDocumentToBeSavedToURL:(NSURL *)url error:(NSError **)outError;
{
    OBPRECONDITION(url);
    
    return [self _initWithProxy:nil url:url error:outError];
}

- _initWithProxy:(OUIDocumentProxy *)proxy url:(NSURL *)url error:(NSError **)outError;
{
    OBPRECONDITION(proxy || url);
    OBPRECONDITION(!proxy || [proxy.url isEqual:url]);
    
    if (!(self = [super init]))
        return nil;
    
    _proxy = [proxy retain];
    _url = [url copy];
    
    _undoManager = [[NSUndoManager alloc] init];
    
    // When groups fall off the end of this limit and deallocate objects inside them, those objects come back and try to remove themselves from the undo manager.  This asplodes.
    // <bug://bugs/60414> (Crash in [NSUndoManager removeAllActionsWithTarget:])
#if 0
    NSInteger levelsOfUndo = [[NSUserDefaults standardUserDefaults] integerForKey:@"LevelsOfUndo"];
    if (levelsOfUndo <= 0)
        levelsOfUndo = 10;
    [_undoManager setLevelsOfUndo:levelsOfUndo];
#endif
    
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    
    [center addObserver:self selector:@selector(_undoManagerDidUndoOrRedo:) name:NSUndoManagerDidUndoChangeNotification object:_undoManager];
    [center addObserver:self selector:@selector(_undoManagerDidUndoOrRedo:) name:NSUndoManagerDidRedoChangeNotification object:_undoManager];
    
    [center addObserver:self selector:@selector(_undoManagerDidOpenGroup:) name:NSUndoManagerDidOpenUndoGroupNotification object:_undoManager];
    [center addObserver:self selector:@selector(_undoManagerWillCloseGroup:) name:NSUndoManagerWillCloseUndoGroupNotification object:_undoManager];
    
    [center addObserver:self selector:@selector(_inspectorDidEndChangingInspectedObjects:) name:OUIInspectorDidEndChangingInspectedObjectsNotification object:nil];
    
    if (![self loadDocumentContents:outError]) {
        [self release];
        return nil;
    }

    _viewController = [[self makeViewController] retain];
    
    // clear out any undo actions created during init
    [_undoManager removeAllActions];
    
    // this implicitly kills any groups; make sure our flag gets cleared too.
    OBASSERT([_undoManager groupingLevel] == 0);
    _hasUndoGroupOpen = NO;
    
    [[[OUIAppController controller] undoBarButtonItem] setEnabled:NO];
    
    // If we didn't have a preview
    if (proxy && !proxy.hasPDFPreview)
        _hasDoneAutosave = YES;
    
    return self;
}

- (void)dealloc;
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    [_viewController release];
    
    [_undoIndicator release];
    [_saveTimer invalidate];
    [_saveTimer release];
    _saveTimer = nil;
    
    [_undoManager release];
    [_proxy release];
    
    [super dealloc];
}

@synthesize url = _url;

- (NSUndoManager *)undoManager;
{
    OBPRECONDITION(_undoManager);
    return _undoManager;
}

@synthesize viewController = _viewController;

// Called when we've been renamed in the document editor.
@synthesize proxy = _proxy;
- (void)setProxy:(OUIDocumentProxy *)proxy;
{
    if (_proxy == proxy)
        return;
    [_proxy release];
    _proxy = [proxy retain];
    
    [_url release];
    _url = [_proxy.url copy];
}

- (BOOL)saveAsNewDocumentToURL:(NSURL *)url error:(NSError **)outError;
{
    OBPRECONDITION(_url == nil || [_url isEqual:url]);
    OBPRECONDITION(_proxy == nil);
    return [self _saveToURL:url isAutosave:NO error:outError];
}

- (void)finishUndoGroup;
{
    if (!_hasUndoGroupOpen)
        return; // Nothing to do!
    
    [self willFinishUndoGroup];
    
    DEBUG_UNDO(@"finishUndoGroup");
    
    // Our group might be the only one open, but the auto-created group might be open still too (for example, with a single-event action like -delete:)
    OBASSERT([_undoManager groupingLevel] >= 1);
    _hasUndoGroupOpen = NO;
    
    // This should drop the count to zero, allowing any pending autosave to happen.
    [_undoManager endUndoGrouping];
}

- (IBAction)undo:(id)sender;
{
    if (![self shouldUndo])
        return;
    
    // Make sure any edits get finished and saved in the current undo group
    [_viewController.view.window endEditing:YES/*force*/];
    [self finishUndoGroup]; // close any nested group we created
    
    [_undoManager undo];
    
    [self didUndo];
}

- (IBAction)redo:(id)sender;
{
    if (![self shouldRedo])
        return;
    
    // Make sure any edits get finished and saved in the current undo group
    [_viewController.view.window endEditing:YES/*force*/];
    [self finishUndoGroup]; // close any nested group we created
    
    [_undoManager redo];
    
    [self didRedo];
}

- (BOOL)hasUnsavedChanges;
{
    return _saveTimer != nil;
}

- (BOOL)saveForClosing:(NSError **)outError;
{
    OBPRECONDITION(_url);
    
    // Make sure any label editing is finished.
    [_viewController.view endEditing:YES/*force*/];
    
    // If we have previously done an autosave, we need to save to restore our preview. Otherwise, we only need to save if there is a pending autosave.
    if (!_hasDoneAutosave && !_saveTimer && !_hasUndoGroupOpen)
        return YES;
    
    if (_hasUndoGroupOpen) {
        OBASSERT([_undoManager groupingLevel] == 1);
        [_undoManager endUndoGrouping];
    }
    
    [_undoIndicator hide];
    [_saveTimer invalidate];
    [_saveTimer release];
    _saveTimer = nil;
    
    if (![self _saveToURL:_url isAutosave:NO error:outError])
        return NO;
    
    // We have a new preview now and the document picker is about to care.
    OBASSERT(_proxy);
    [_proxy refreshDateAndPreview];
    
    return YES;
}


#pragma mark -
#pragma mark Subclass responsibility

- (BOOL)loadDocumentContents:(NSError **)outError;
{
    OBRequestConcreteImplementation(self, _cmd);
}

- (UIViewController *)makeViewController;
{
    OBRequestConcreteImplementation(self, _cmd);
}

- (BOOL)saveToURL:(NSURL *)url isAutosave:(BOOL)isAutosave error:(NSError **)outError;
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

- (void)willClose;
{
}

#pragma mark -
#pragma mark Private

- (BOOL)_saveToURL:(NSURL *)url isAutosave:(BOOL)isAutosave error:(NSError **)outError;
{
    OBPRECONDITION(!_url || [_url isEqual:url]); // New documents can gain a URL, but we don't intend to have "save as".
    
    if (!url) {
        OBASSERT_NOT_REACHED("should get set on init or via -saveAsNewDocument:");
        OUIError(outError, OUIDocumentHasNoURLError, @"Cannot save.", @"Document has no URL");
        return NO;
    }
    
    if (outError)
        *outError = nil;
    
    if (![self saveToURL:url isAutosave:isAutosave error:outError]) {
        OUIDocumentProxy *currentProxy = [self proxy];
        NSString *fileType = [[OUIAppController controller] documentTypeForURL:currentProxy.url];
        NSURL *newProxyURL = [[[OUIAppController controller] documentPicker] renameProxy:currentProxy toName:[currentProxy name] type:fileType];
        OUIDocumentProxy *newProxy = [[[OUIAppController controller] documentPicker] proxyWithURL:newProxyURL];
        OBASSERT(newProxy != nil);
        [self setProxy:newProxy];
        url = [self url];
        
        // If this fails too, eat this error and return the original one rather than stacking them up.
        NSError *retryError = nil;
        if (![self saveToURL:url isAutosave:isAutosave error:&retryError])
            return NO;
    }
    
    if (isAutosave) {
        // Remember that we've done an autosave, thus blowing away our last preview. When we close the document, this forces a save with the preview.
        _hasDoneAutosave = YES;
    }
    
    if (OFNOTEQUAL(_url, url)) {
        [_url release]; // might be set if we loaded from a template
        _url = [url copy];
    }
    
    return YES;
}

- (void)_scheduleAutosave;
{
    if (!_saveTimer) {
        DEBUG_UNDO(@"Scheduling autosave timer");
        _saveTimer = [[NSTimer scheduledTimerWithTimeInterval:[[self class] autosaveTimeInterval] target:self selector:@selector(_autosaveTimerFired:) userInfo:nil repeats:NO] retain];
    }
}

- (void)_autosave;
{
    DEBUG_UNDO(@"Autosaving now");
    [_undoIndicator hide];
    
    NSError *error = nil;
    if (![self _saveToURL:_url isAutosave:YES error:&error])
        OUI_PRESENT_ERROR(error);
}

- (void)_autosaveTimerFired:(NSTimer *)timer;
{
    OBPRECONDITION(_saveTimer);
    OBPRECONDITION(_saveTimer == timer);
    OBPRECONDITION(![_undoManager isUndoing]);
    OBPRECONDITION(![_undoManager isRedoing]);
    
    DEBUG_UNDO(@"Save timer fired");
    
    [_saveTimer release];
    _saveTimer = nil;
    
    if (_hasUndoGroupOpen) {
        // We are in the middle of some multi-event operation (making fill, for example) that will be ended by -finishUndoGroup. Try again later.
        [self _scheduleAutosave];
    } else {
        // can save now if there is no group in progress
        [self _autosave];
    }
}

- (void)_startAutosaveAndUpdateUndoButton;
{
    [self _scheduleAutosave];
    
    if (!_undoIndicator && [[self class] shouldShowAutosaveIndicator])
        _undoIndicator = [[OUIUndoIndicator alloc] initWithParentView:_viewController.view];
    
    [_undoIndicator show];
    
    [[[OUIAppController controller] undoBarButtonItem] setEnabled:[_undoManager canUndo] || [_undoManager canRedo]];
}

- (void)_undoManagerDidUndoOrRedo:(NSNotification *)note;
{
    DEBUG_UNDO(@"%@ level:%d", [note name], [_undoManager groupingLevel]);
    
    [self _startAutosaveAndUpdateUndoButton];
}

- (void)_undoManagerDidOpenGroup:(NSNotification *)note;
{
    DEBUG_UNDO(@"%@ level:%d", [note name], [_undoManager groupingLevel]);
    
    // Immediately open a nested group. This will allows NSUndoManager to automatically open groups for us on the first undo operation, but prevents it from closing the whole group.
    if ([_undoManager groupingLevel] == 1) {
        DEBUG_UNDO(@"  .. nesting");
        _hasUndoGroupOpen = YES;
        [_undoManager beginUndoGrouping];
    }
}

- (void)_undoManagerWillCloseGroup:(NSNotification *)note;
{
    DEBUG_UNDO(@"%@ level:%d", [note name], [_undoManager groupingLevel]);
    
    // Start a timer if one isn't going already
    [self _startAutosaveAndUpdateUndoButton];
}

- (void)_inspectorDidEndChangingInspectedObjects:(NSNotification *)note;
{
    [self finishUndoGroup];
}

@end
