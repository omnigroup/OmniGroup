// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUIDocument/OUIDocumentPreviewGenerator.h>

#import <OmniDocumentStore/ODSFileItem.h>
#import <OmniUI/OUIInteractionLock.h>
#import <OmniUIDocument/OUIDocument.h>
#import <OmniUIDocument/OUIDocumentPreview.h>
#import <OmniFoundation/NSDate-OFExtensions.h>
#import <OmniFoundation/OFBackgroundActivity.h>
#import <OmniFoundation/OFFileEdit.h>
#import <OmniFoundation/OFPreference.h>

#import "OUIDocument-Internal.h"

RCS_ID("$Id$");

@implementation OUIDocumentPreviewGenerator
{
    OUIInteractionLock *_interactionLock;
    NSMutableSet *_fileItemsNeedingUpdatedPreviews;
    ODSFileItem *_currentPreviewUpdatingFileItem;
    ODSFileItem *_fileItemToOpenAfterCurrentPreviewUpdateFinishes; // We block user interaction while this is set.
    OFBackgroundActivity *_previewUpdatingBackgroundActivity;
}

OFDeclareDebugLogLevel(OUIDocumentPreviewGeneratorDebug)

static NSUInteger disableCount = 0;
static NSMutableArray *blocksWhileDisabled = nil;

+ (void)disablePreviewsForAnimation;
{
    disableCount++;
}

+ (void)enablePreviewsForAnimation;
{
   disableCount--;
    
    while (!disableCount && blocksWhileDisabled.count) {
        void (^block)(void) = [blocksWhileDisabled objectAtIndex:0];
        [blocksWhileDisabled removeObjectAtIndex:0];
        block();
    }
}

+ (void)_performOrQueueBlock:(void (^)(void))block;
{
    if (disableCount) {
        if (!blocksWhileDisabled)
            blocksWhileDisabled = [[NSMutableArray alloc] init];
        [blocksWhileDisabled addObject:block];
    } else {
        OBASSERT([NSThread isMainThread]);
        block();
    }
}

@synthesize delegate = _weak_delegate;
@synthesize fileItemToOpenAfterCurrentPreviewUpdateFinishes = _fileItemToOpenAfterCurrentPreviewUpdateFinishes;

- (void)dealloc;
{
    OBPRECONDITION(_weak_delegate == nil); // It should be retaining us otherwise
    
    if (_fileItemToOpenAfterCurrentPreviewUpdateFinishes)
        [_interactionLock unlock];
}

- (void)enqueuePreviewUpdateForFileItemsMissingPreviews:(id <NSFastEnumeration>)fileItems;
{
    id <OUIDocumentPreviewGeneratorDelegate> delegate = _weak_delegate;
    OBASSERT(delegate);
    
    for (ODSFileItem *fileItem in fileItems) {
        if ([_fileItemsNeedingUpdatedPreviews member:fileItem])
            continue; // Already queued up.
        
        if ([delegate previewGenerator:self isFileItemCurrentlyOpen:fileItem])
            continue; // Ignore this one. The process of closing a document will update its preview and once we become visible we'll check for other previews that need to be updated.
        
        OFFileEdit *fileEdit = fileItem.fileEdit;
        if (fileEdit == nil)
            continue; // Not downloaded
        
        if (![OUIDocumentPreview hasPreviewsForFileEdit:fileEdit]) {
            if (!_fileItemsNeedingUpdatedPreviews)
                _fileItemsNeedingUpdatedPreviews = [[NSMutableSet alloc] init];
            [_fileItemsNeedingUpdatedPreviews addObject:fileItem];
            continue;
        }
    }
    
    if (![delegate previewGeneratorHasOpenDocument:self]) // Start updating previews immediately if there is no open document. Otherwise, queue them until the document is closed
        [self _continueUpdatingPreviewsOrOpenDocument];
}

- (void)applicationDidEnterBackground;
{
    if (_currentPreviewUpdatingFileItem) {
        // We'll call -_previewUpdateBackgroundTaskFinished when we finish up.
        OBASSERT(_previewUpdatingBackgroundActivity);
    } else {
        [self _previewUpdateBackgroundTaskFinished];
    }
}

- (BOOL)shouldOpenDocumentWithFileItem:(ODSFileItem *)fileItem;
{
    OBPRECONDITION(_fileItemToOpenAfterCurrentPreviewUpdateFinishes == nil);
    OBPRECONDITION(fileItem);
    
    if (_currentPreviewUpdatingFileItem == nil) {
        OBASSERT(_previewUpdatingBackgroundActivity == nil);
        return YES;
    }
    
    DEBUG_PREVIEW_GENERATION(1, @"Delaying opening document at %@ until preview refresh finishes for %@", fileItem.fileURL, _currentPreviewUpdatingFileItem.fileURL);
    
    // Delay the open until after we've finished updating this preview
    _fileItemToOpenAfterCurrentPreviewUpdateFinishes = fileItem;
    
    // Hacky, but if we defer the action (which would have paused user interaction while opening a document), we shouldn't let another action creep in (like tapping the + button to add a new document) and then fire off our delayed open.
    if (_fileItemToOpenAfterCurrentPreviewUpdateFinishes) {
        _interactionLock = [OUIInteractionLock applicationLock];
    }

    return NO;
}

- (void)fileItemNeedsPreviewUpdate:(ODSFileItem *)fileItem;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    // The process of closing a document will update its preview and once we become visible we'll check for other previews that need to be updated.
    id <OUIDocumentPreviewGeneratorDelegate> delegate = _weak_delegate;
    if ([delegate previewGenerator:self isFileItemCurrentlyOpen:fileItem]) {
        DEBUG_PREVIEW_GENERATION(2, @"Document is open, ignoring change of %@.", fileItem.fileURL);
        return;
    }
    
    if ([_fileItemsNeedingUpdatedPreviews member:fileItem] == nil) {
        DEBUG_PREVIEW_GENERATION(2, @"Queueing preview update of %@", fileItem.fileURL);
        if (!_fileItemsNeedingUpdatedPreviews)
            _fileItemsNeedingUpdatedPreviews = [[NSMutableSet alloc] init];
        [_fileItemsNeedingUpdatedPreviews addObject:fileItem];
        
        if (![delegate previewGeneratorHasOpenDocument:self]) { // Start updating previews immediately if there is no open document. Otherwise, queue them until the document is closed
            [self _continueUpdatingPreviewsOrOpenDocument];
        } else {
            DEBUG_PREVIEW_GENERATION(2, @"Some document is open, not generating previews");
        }
    }
}

- (void)documentClosed;
{
    // Start updating the previews for any other documents that were edited and have had incoming iCloud changes invalidate their previews.
    [self _continueUpdatingPreviewsOrOpenDocument];
}

#pragma mark - Private

static void _writePreviewsForFileItem(OUIDocumentPreviewGenerator *self, OFFileEdit *originalFileEdit)
{
    NSURL *fileURL = originalFileEdit.originalFileURL;
    
    if (![self->_currentPreviewUpdatingFileItem isValid]) {
        [self _finishedUpdatingPreview];
        return;
    }
    
    id <OUIDocumentPreviewGeneratorDelegate> delegate = self->_weak_delegate;
    if (![delegate previewGenerator:self shouldGeneratePreviewForURL:fileURL]) {
        [OUIDocumentPreview writeEmptyPreviewsForFileEdit:originalFileEdit];
        [self _finishedUpdatingPreview];
        return;
    }

    Class documentClass = [delegate previewGenerator:self documentClassForFileURL:fileURL];
    if (documentClass == nil) {
        [OUIDocumentPreview writeEmptyPreviewsForFileEdit:originalFileEdit];
        [self _finishedUpdatingPreview];
        return;
    }

    OBASSERT(OBClassIsSubclassOfClass(documentClass, [OUIDocument class]));

    __autoreleasing NSError *error = nil;
    OUIDocument *document = [[documentClass alloc] initWithExistingFileItem:self->_currentPreviewUpdatingFileItem error:&error];
    if (!document) {
        NSLog(@"Error opening document at %@ to rebuild its preview: %@", fileURL, [error toPropertyList]);
    }
    
    DEBUG_PREVIEW_GENERATION(1, @"Starting preview update of %@ / %@", [fileURL lastPathComponent], [originalFileEdit.fileModificationDate xmlString]);

    // Let the document know that it is only going to be used to generate previews.
    document.forPreviewGeneration = YES;
    
    // Write blank previews before we start the opening process in case it crashes. Without this we could get into a state where launching the app would crash over and over. Now we should only crash once per bad document (still bad, but recoverable for the user). In addition to caching placeholder previews, this will write the empty marker preview files too.
    [OUIDocumentPreview cachePreviewImages:^(OUIDocumentPreviewCacheImage cacheImage) {
        cacheImage(originalFileEdit, NULL);
    }];
    
    [document openWithCompletionHandler:^(BOOL openSuccess){
        OBASSERT([NSThread isMainThread]);
        
        if (openSuccess) {
            OFFileEdit *fileEdit = document.fileItem.fileEdit;
            OBASSERT(fileEdit);
            
            [OUIDocumentPreviewGenerator _performOrQueueBlock:^{
                [document _writePreviewsIfNeeded:NO /* have to pass NO since we just wrote bogus previews */ fileEdit:fileEdit withCompletionHandler:^{
                    [OUIDocumentPreviewGenerator _performOrQueueBlock:^{
                        [document closeWithCompletionHandler:^(BOOL success){
                            [document didClose];
                            
                            DEBUG_PREVIEW_GENERATION(1, @"Finished preview update of %@", fileURL);
                            
                            // Wait until the close is done to end our background task (in case we are being backgrounded, we don't want an open document alive that might point at a document the user might delete externally).
                            [self _finishedUpdatingPreview];
                        }];
                    }];
                }];
            }];
        } else {
            if (document.isDocumentEncrypted) {
                [OUIDocumentPreviewGenerator _performOrQueueBlock:^{
                    OUIDocumentHandleDocumentOpenFailure(document, ^(BOOL success){
                        OFFileEdit *fileEdit = document.fileItem.fileEdit;
                        [OUIDocumentPreview writeEncryptedEmptyPreviewsForFileEdit:fileEdit fileURL:document.fileURL];
                        [self _finishedUpdatingPreview];
                    });
                }];
            } else {
                OUIDocumentHandleDocumentOpenFailure(document, ^(BOOL success){
                    [self _finishedUpdatingPreview];
                });
            }
        }
    }];
}

- (void)_continueUpdatingPreviewsOrOpenDocument;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    if (_currentPreviewUpdatingFileItem) {
        OBASSERT(_previewUpdatingBackgroundActivity != nil);
        return; // Already updating one. When this finishes, this method will be called again
    } else {
        OBASSERT(_previewUpdatingBackgroundActivity == nil);
    }
    
    // If someone else happens to call after we've completed our background task, ignore it.
    if ([[UIApplication sharedApplication] applicationState] != UIApplicationStateActive) {
        DEBUG_PREVIEW_GENERATION(2, @"Ignoring preview generation while in the background.");
        return;
    }
    
    // If the user tapped on a document while a preview was happening, we'll have delayed that action until the current preview update finishes (to avoid having two documents open at once and possibliy running out of memory).
    id <OUIDocumentPreviewGeneratorDelegate> delegate = _weak_delegate;
    if (_fileItemToOpenAfterCurrentPreviewUpdateFinishes) {
        DEBUG_PREVIEW_GENERATION(2, @"Performing delayed open of document at %@", _fileItemToOpenAfterCurrentPreviewUpdateFinishes.fileURL);
        
        ODSFileItem *fileItem = _fileItemToOpenAfterCurrentPreviewUpdateFinishes;
        _fileItemToOpenAfterCurrentPreviewUpdateFinishes = nil;
        
        [_interactionLock unlock];
        _interactionLock = nil;
        
        [delegate previewGenerator:self performDelayedOpenOfFileItem:fileItem];
        return;
    }
    
    if ([delegate previewGeneratorHasOpenDocument:self]) {
        // We got started up, but then a document opened -- pause
        return;
    }
    
    while (_currentPreviewUpdatingFileItem == nil) {
        _currentPreviewUpdatingFileItem = [delegate previewGenerator:self preferredFileItemForNextPreviewUpdate:_fileItemsNeedingUpdatedPreviews];
        if (!_currentPreviewUpdatingFileItem)
            _currentPreviewUpdatingFileItem = [_fileItemsNeedingUpdatedPreviews anyObject];
        
        if (!_currentPreviewUpdatingFileItem)
            return; // No more to do!
        
        BOOL shouldForget = !_currentPreviewUpdatingFileItem.isValid; // If this file item has been deleted since it was queued, skip it.
        shouldForget = shouldForget || ([_currentPreviewUpdatingFileItem isDownloaded] == NO); // We don't want to open the document and provoke download. If the user taps it to provoke download, or iCloud auto-downloads it, we'll get notified via the document store's metadata query and will update the preview again.

        if (shouldForget) {
            OBASSERT([_fileItemsNeedingUpdatedPreviews member:_currentPreviewUpdatingFileItem] == _currentPreviewUpdatingFileItem);
            [_fileItemsNeedingUpdatedPreviews removeObject:_currentPreviewUpdatingFileItem];
            _currentPreviewUpdatingFileItem = nil;
        }
    }
    
    // Make a background task for this so that we don't get stuck with an open document in the background (which might be deleted via iTunes or iCloud).
    if (_previewUpdatingBackgroundActivity) {
        OBASSERT_NOT_REACHED("Background task left running somehow");
        [_previewUpdatingBackgroundActivity finished];
        _previewUpdatingBackgroundActivity = nil;
    }
    DEBUG_PREVIEW_GENERATION(2, @"beginning background task to generate preview");
    _previewUpdatingBackgroundActivity = [OFBackgroundActivity backgroundActivityWithIdentifier:@"com.omnigroup.OmniUI.OUIDocumentPreviewGenerator.finish_preview"];
    
    DEBUG_PREVIEW_GENERATION(1, @"Starting preview update for %@ at %@", _currentPreviewUpdatingFileItem.fileURL, [_currentPreviewUpdatingFileItem.fileModificationDate xmlString]);
    
    // If there is user-interaction blocking work going on (moving items in the document picker, for example), try to stay out of the way of completion handlers that would resume user interaction.
    NSBlockOperation *previewOperation = [NSBlockOperation blockOperationWithBlock:^{
        OFFileEdit *fileEdit = _currentPreviewUpdatingFileItem.fileEdit;
        if (fileEdit != nil) {
            // It might be nil because it's the first time we've opened this external file item.
            _writePreviewsForFileItem(self, fileEdit);
        }
    }];
    previewOperation.queuePriority = NSOperationQueuePriorityLow;
    [[NSOperationQueue mainQueue] addOperation:previewOperation];
}

- (void)_finishedUpdatingPreview;
{
    OBPRECONDITION(_currentPreviewUpdatingFileItem != nil);
    OBPRECONDITION(_previewUpdatingBackgroundActivity != nil);
    
    ODSFileItem *fileItem = _currentPreviewUpdatingFileItem;
    _currentPreviewUpdatingFileItem = nil;
    
    OBASSERT([_fileItemsNeedingUpdatedPreviews member:fileItem] == fileItem);
    [_fileItemsNeedingUpdatedPreviews removeObject:fileItem];

    // Do this after cleaning out our other ivars since we could get suspended
    if (_previewUpdatingBackgroundActivity != nil) {
        DEBUG_PREVIEW_GENERATION(2, @"Preview update task finished!");
        
        OFBackgroundActivity *activity = _previewUpdatingBackgroundActivity;
        _previewUpdatingBackgroundActivity = nil;

        // If we got backgrounded while finishing a preview update, we deferred this call.
        if ([[UIApplication sharedApplication] applicationState] != UIApplicationStateActive)
            [self _previewUpdateBackgroundTaskFinished];
        
        // Let the app run for just a bit longer to let queues clean up references to blocks. Also, route this through the preview generation queue to make sure it has flushed out any queued I/O on our behalf. The delay bit isn't really guaranteed to work, but by intrumenting -[OUIDocument dealloc], we can see that it seems to work. Waiting for the document to be deallocated isn't super important, but nice to make our memory usage lower while in the background.
        [OUIDocumentPreview afterAsynchronousPreviewOperation:^{
            [activity finished];
        }];
    }
    
    [self _continueUpdatingPreviewsOrOpenDocument];
}

- (void)_previewUpdateBackgroundTaskFinished;
{
    OBPRECONDITION(_currentPreviewUpdatingFileItem == nil);
    OBPRECONDITION(_previewUpdatingBackgroundActivity == nil);
    
    // Forget any request to open a file after a preview update
    if (_fileItemToOpenAfterCurrentPreviewUpdateFinishes) {
        _fileItemToOpenAfterCurrentPreviewUpdateFinishes = nil;
        
        [_interactionLock unlock];
        _interactionLock = nil;
    }
    
    // On our next foregrounding, we'll restart our preview updating anyway. If we have a preview generation in progress, try to wait for that to complete, though. Otherwise if it happens to complete after we say we can get backgrounded, our read/writing of the image can fail with EINVAL (presumably they close up the sandbox).
    [_fileItemsNeedingUpdatedPreviews removeAllObjects];
}

@end
