// Copyright 2010-2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIDocumentPreviewGenerator.h"

#import <OmniFileStore/OFSDocumentStoreFileItem.h>
#import <OmniUIDocument/OUIDocument.h>
#import <OmniUIDocument/OUIDocumentPreview.h>
#import <OmniFoundation/NSDate-OFExtensions.h>

#import "OUIDocument-Internal.h"

RCS_ID("$Id$");

@interface OUIDocumentPreviewGenerator ()
- (void)_continueUpdatingPreviewsOrOpenDocument;
- (void)_finishedUpdatingPreview;
- (void)_previewUpdateBackgroundTaskFinished;
@end

@implementation OUIDocumentPreviewGenerator
{
    NSMutableSet *_fileItemsNeedingUpdatedPreviews;
    OFSDocumentStoreFileItem *_currentPreviewUpdatingFileItem;
    OFSDocumentStoreFileItem *_fileItemToOpenAfterCurrentPreviewUpdateFinishes; // We block user interaction while this is set.
    UIBackgroundTaskIdentifier _previewUpdatingBackgroundTaskIdentifier;
}

@synthesize delegate = _weak_delegate;
@synthesize fileItemToOpenAfterCurrentPreviewUpdateFinishes = _fileItemToOpenAfterCurrentPreviewUpdateFinishes;

- (void)dealloc;
{
    OBPRECONDITION(_weak_delegate == nil); // It should be retaining us otherwise
    
    if (_fileItemToOpenAfterCurrentPreviewUpdateFinishes) {
        [[UIApplication sharedApplication] endIgnoringInteractionEvents];
    }

    if (_previewUpdatingBackgroundTaskIdentifier != UIBackgroundTaskInvalid) {
        [[UIApplication sharedApplication] endBackgroundTask:_previewUpdatingBackgroundTaskIdentifier];
        _previewUpdatingBackgroundTaskIdentifier = UIBackgroundTaskInvalid;
    }
}

static BOOL _addFileItemIfPreviewMissing(OUIDocumentPreviewGenerator *self, OFSDocumentStoreFileItem *fileItem, NSURL *fileURL, NSDate *date)
{
    if (![OUIDocumentPreview hasPreviewForFileURL:fileURL date:date withLandscape:YES] ||
        ![OUIDocumentPreview hasPreviewForFileURL:fileURL date:date withLandscape:NO]) {
        
        if (!self->_fileItemsNeedingUpdatedPreviews)
            self->_fileItemsNeedingUpdatedPreviews = [[NSMutableSet alloc] init];
        [self->_fileItemsNeedingUpdatedPreviews addObject:fileItem];
        return YES;
    }
    return NO;
}

- (void)enqueuePreviewUpdateForFileItemsMissingPreviews:(id <NSFastEnumeration>)fileItems;
{
    id <OUIDocumentPreviewGeneratorDelegate> delegate = _weak_delegate;
    OBASSERT(delegate);
    
    for (OFSDocumentStoreFileItem *fileItem in fileItems) {
        if ([_fileItemsNeedingUpdatedPreviews member:fileItem])
            continue; // Already queued up.
        
        if ([delegate previewGenerator:self isFileItemCurrentlyOpen:fileItem])
            continue; // Ignore this one. The process of closing a document will update its preview and once we become visible we'll check for other previews that need to be updated.
        
        if (_addFileItemIfPreviewMissing(self, fileItem, fileItem.fileURL, fileItem.fileModificationDate))
            continue;
    }
    
    if (![delegate previewGeneratorHasOpenDocument:self]) // Start updating previews immediately if there is no open document. Otherwise, queue them until the document is closed
        [self _continueUpdatingPreviewsOrOpenDocument];
}

- (void)applicationDidEnterBackground;
{
    if (_currentPreviewUpdatingFileItem) {
        // We'll call -_previewUpdateBackgroundTaskFinished when we finish up.
        OBASSERT(_previewUpdatingBackgroundTaskIdentifier != UIBackgroundTaskInvalid);
    } else {
        [self _previewUpdateBackgroundTaskFinished];
    }
}

- (BOOL)shouldOpenDocumentWithFileItem:(OFSDocumentStoreFileItem *)fileItem;
{
    OBPRECONDITION(_fileItemToOpenAfterCurrentPreviewUpdateFinishes == nil);
    OBPRECONDITION(fileItem);
    
    if (_currentPreviewUpdatingFileItem == nil) {
        OBASSERT(_previewUpdatingBackgroundTaskIdentifier == UIBackgroundTaskInvalid);
        return YES;
    }
    
    DEBUG_PREVIEW_GENERATION(@"Delaying opening document at %@ until preview refresh finishes for %@", fileItem.fileURL, _currentPreviewUpdatingFileItem.fileURL);
    
    // Delay the open until after we've finished updating this preview
    _fileItemToOpenAfterCurrentPreviewUpdateFinishes = fileItem;
    
    // Hacky, but if we defer the action (which would have paused user interaction while opening a document), we shouldn't let another action creep in (like tapping the + button to add a new document) and then fire off our delayed open.
    if (_fileItemToOpenAfterCurrentPreviewUpdateFinishes)
        [[UIApplication sharedApplication] beginIgnoringInteractionEvents];

    return NO;
}

- (void)fileItemNeedsPreviewUpdate:(OFSDocumentStoreFileItem *)fileItem;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    // The process of closing a document will update its preview and once we become visible we'll check for other previews that need to be updated.
    id <OUIDocumentPreviewGeneratorDelegate> delegate = _weak_delegate;
    if ([delegate previewGenerator:self isFileItemCurrentlyOpen:fileItem]) {
        DEBUG_PREVIEW_GENERATION(@"Document is open, ignoring change of %@.", fileItem.fileURL);
        return;
    }
    
    if ([_fileItemsNeedingUpdatedPreviews member:fileItem] == nil) {
        DEBUG_PREVIEW_GENERATION(@"Queueing preview update of %@", fileItem.fileURL);
        if (!_fileItemsNeedingUpdatedPreviews)
            _fileItemsNeedingUpdatedPreviews = [[NSMutableSet alloc] init];
        [_fileItemsNeedingUpdatedPreviews addObject:fileItem];
        
        if (![delegate previewGeneratorHasOpenDocument:self]) { // Start updating previews immediately if there is no open document. Otherwise, queue them until the document is closed
            [self _continueUpdatingPreviewsOrOpenDocument];
        } else {
            DEBUG_PREVIEW_GENERATION(@"Some document is open, not generating previews");
        }
    }
}

- (void)documentClosed;
{
    // Start updating the previews for any other documents that were edited and have had incoming iCloud changes invalidate their previews.
    [self _continueUpdatingPreviewsOrOpenDocument];
}

#pragma mark - Private

static void _writePreviewsForFileItem(OUIDocumentPreviewGenerator *self, OFSDocumentStoreFileItem *fileItem)
{
    // Be careful to use the modification date we'd get otherwise for the current version. They should be the same, but...
    NSURL *fileURL = fileItem.fileURL;
    NSDate *date = fileItem.fileModificationDate;
    
    id <OUIDocumentPreviewGeneratorDelegate> delegate = self->_weak_delegate;
    Class cls = [delegate previewGenerator:self documentClassForFileURL:fileURL];
    OBASSERT(OBClassIsSubclassOfClass(cls, [OUIDocument class]));
    if (!cls)
        return;
    
    __autoreleasing NSError *error = nil;
    OUIDocument *document = [[cls alloc] initWithExistingFileItem:self->_currentPreviewUpdatingFileItem error:&error];
    if (!document) {
        NSLog(@"Error opening document at %@ to rebuild its preview: %@", fileURL, [error toPropertyList]);
    }
    
    DEBUG_PREVIEW_GENERATION(@"Starting preview update of %@ / %@", [fileURL lastPathComponent], [date xmlString]);

    // Let the document know that it is only going to be used to generate previews.
    document.forPreviewGeneration = YES;
    
    // Write blank previews before we start the opening process in case it crashes. Without this we could get into a state where launching the app would crash over and over. Now we should only crash once per bad document (still bad, but recoverable for the user). In addition to caching placeholder previews, this will write the empty marker preview files too.
    [OUIDocumentPreview cachePreviewImages:^(OUIDocumentPreviewCacheImage cacheImage) {
        cacheImage(fileURL, date, YES/*landscape*/, NULL);
        cacheImage(fileURL, date, NO/*landscape*/, NULL);
    }];
    
    [document openWithCompletionHandler:^(BOOL success){
        OBASSERT([NSThread isMainThread]);
        
        if (success) {
            [document _writePreviewsIfNeeded:NO /* have to pass NO since we just write bogus previews */ withCompletionHandler:^{
                OBASSERT([NSThread isMainThread]);
                
                [document closeWithCompletionHandler:^(BOOL success){
                    OBASSERT([NSThread isMainThread]);
                    
                    [document willClose];
                    
                    DEBUG_PREVIEW_GENERATION(@"Finished preview update of %@", fileURL);
                    
                    // Wait until the close is done to end our background task (in case we are being backgrounded, we don't want an open document alive that might point at a document the user might delete externally).
                    [self _finishedUpdatingPreview];
                }];
            }];
        } else {
            OUIDocumentHandleDocumentOpenFailure(document, ^(BOOL success){
                [self _finishedUpdatingPreview];
            });
        }
    }];
}

- (void)_continueUpdatingPreviewsOrOpenDocument;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    if (_currentPreviewUpdatingFileItem) {
        OBASSERT(_previewUpdatingBackgroundTaskIdentifier != UIBackgroundTaskInvalid);
        return; // Already updating one. When this finishes, this method will be called again
    } else {
        OBASSERT(_previewUpdatingBackgroundTaskIdentifier == UIBackgroundTaskInvalid);
    }
    
    // If someone else happens to call after we've completed our background task, ignore it.
    if ([[UIApplication sharedApplication] applicationState] != UIApplicationStateActive) {
        DEBUG_PREVIEW_GENERATION(@"Ignoring preview generation while in the background.");
        return;
    }
    
    // If the user tapped on a document while a preview was happening, we'll have delayed that action until the current preview update finishes (to avoid having two documents open at once and possibliy running out of memory).
    id <OUIDocumentPreviewGeneratorDelegate> delegate = _weak_delegate;
    if (_fileItemToOpenAfterCurrentPreviewUpdateFinishes) {
        DEBUG_PREVIEW_GENERATION(@"Performing delayed open of document at %@", _fileItemToOpenAfterCurrentPreviewUpdateFinishes.fileURL);
        
        OFSDocumentStoreFileItem *fileItem = _fileItemToOpenAfterCurrentPreviewUpdateFinishes;
        _fileItemToOpenAfterCurrentPreviewUpdateFinishes = nil;
        [[UIApplication sharedApplication] endIgnoringInteractionEvents];
        
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
        
        // We don't want to open the document and provoke download. If the user taps it to provoke download, or iCloud auto-downloads it, we'll get notified via the document store's metadata query and will update the preview again.
        if ([_currentPreviewUpdatingFileItem isDownloaded] == NO) {
            OBASSERT([_fileItemsNeedingUpdatedPreviews member:_currentPreviewUpdatingFileItem] == _currentPreviewUpdatingFileItem);
            [_fileItemsNeedingUpdatedPreviews removeObject:_currentPreviewUpdatingFileItem];
            _currentPreviewUpdatingFileItem = nil;
        }
    }
    
    // Make a background task for this so that we don't get stuck with an open document in the background (which might be deleted via iTunes or iCloud).
    if (_previewUpdatingBackgroundTaskIdentifier != UIBackgroundTaskInvalid) {
        OBASSERT_NOT_REACHED("Background task left running somehow");
        [[UIApplication sharedApplication] endBackgroundTask:_previewUpdatingBackgroundTaskIdentifier];
        _previewUpdatingBackgroundTaskIdentifier = UIBackgroundTaskInvalid;
    }
    DEBUG_PREVIEW_GENERATION(@"beginning background task to generate preview");
    _previewUpdatingBackgroundTaskIdentifier = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
        DEBUG_PREVIEW_GENERATION(@"Preview update task expired!");
    }];
    OBASSERT(_previewUpdatingBackgroundTaskIdentifier != UIBackgroundTaskInvalid);
    
    DEBUG_PREVIEW_GENERATION(@"Starting preview update for %@ at %@", _currentPreviewUpdatingFileItem.fileURL, [_currentPreviewUpdatingFileItem.fileModificationDate xmlString]);
    
    _writePreviewsForFileItem(self, _currentPreviewUpdatingFileItem);
}

- (void)_finishedUpdatingPreview;
{
    OBPRECONDITION(_currentPreviewUpdatingFileItem != nil);
    OBPRECONDITION(_previewUpdatingBackgroundTaskIdentifier != UIBackgroundTaskInvalid);
    
    OFSDocumentStoreFileItem *fileItem = _currentPreviewUpdatingFileItem;
    _currentPreviewUpdatingFileItem = nil;
    
    OBASSERT([_fileItemsNeedingUpdatedPreviews member:fileItem] == fileItem);
    [_fileItemsNeedingUpdatedPreviews removeObject:fileItem];

    // Do this after cleaning out our other ivars since we could get suspended
    if (_previewUpdatingBackgroundTaskIdentifier != UIBackgroundTaskInvalid) {
        DEBUG_PREVIEW_GENERATION(@"Preview update task finished!");
        UIBackgroundTaskIdentifier task = _previewUpdatingBackgroundTaskIdentifier;
        _previewUpdatingBackgroundTaskIdentifier = UIBackgroundTaskInvalid;

        // If we got backgrounded while finishing a preview update, we deferred this call.
        if ([[UIApplication sharedApplication] applicationState] != UIApplicationStateActive)
            [self _previewUpdateBackgroundTaskFinished];
        
        // Let the app run for just a bit longer to let queues clean up references to blocks. Also, route this through the preview generation queue to make sure it has flushed out any queued I/O on our behalf. The delay bit isn't really guaranteed to work, but by intrumenting -[OUIDocument dealloc], we can see that it seems to work. Waiting for the document to be deallocated isn't super important, but nice to make our memory usage lower while in the background.
        [OUIDocumentPreview afterAsynchronousPreviewOperation:^{
            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                [[UIApplication sharedApplication] endBackgroundTask:task];
            }];
        }];
    }
    
    [self _continueUpdatingPreviewsOrOpenDocument];
}

- (void)_previewUpdateBackgroundTaskFinished;
{
    OBPRECONDITION(_currentPreviewUpdatingFileItem == nil);
    OBPRECONDITION(_previewUpdatingBackgroundTaskIdentifier == UIBackgroundTaskInvalid);
    
    // Forget any request to open a file after a preview update
    if (_fileItemToOpenAfterCurrentPreviewUpdateFinishes) {
        _fileItemToOpenAfterCurrentPreviewUpdateFinishes = nil;
        
        [[UIApplication sharedApplication] endIgnoringInteractionEvents];
    }
    
    // On our next foregrounding, we'll restart our preview updating anyway. If we have a preview generation in progress, try to wait for that to complete, though. Otherwise if it happens to complete after we say we can get backgrounded, our read/writing of the image can fail with EINVAL (presumably they close up the sandbox).
    [_fileItemsNeedingUpdatedPreviews removeAllObjects];
}

@end
