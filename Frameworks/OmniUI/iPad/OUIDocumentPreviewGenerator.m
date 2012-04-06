// Copyright 2010-2012 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIDocumentPreviewGenerator.h"

#import <OmniFileStore/OFSDocumentStoreFileItem.h>
#import <OmniUI/OUIDocument.h>
#import <OmniUI/OUIDocumentPreview.h>
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
    OFSDocumentStoreFileItem *_fileItemToOpenAfterCurrentPreviewUpdateFinishes;
    UIBackgroundTaskIdentifier _previewUpdatingBackgroundTaskIdentifier;
}

@synthesize delegate = _nonretained_delegate;
@synthesize fileItemToOpenAfterCurrentPreviewUpdateFinishes = _fileItemToOpenAfterCurrentPreviewUpdateFinishes;

- (void)dealloc;
{
    OBPRECONDITION(_nonretained_delegate == nil); // It should be retaining us otherwise

    [_fileItemsNeedingUpdatedPreviews release];
    [_currentPreviewUpdatingFileItem release];
    [_fileItemToOpenAfterCurrentPreviewUpdateFinishes release];

    if (_previewUpdatingBackgroundTaskIdentifier != UIBackgroundTaskInvalid) {
        [[UIApplication sharedApplication] endBackgroundTask:_previewUpdatingBackgroundTaskIdentifier];
        _previewUpdatingBackgroundTaskIdentifier = UIBackgroundTaskInvalid;
    }

    [super dealloc];
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
    OBPRECONDITION(_nonretained_delegate);
    
    for (OFSDocumentStoreFileItem *fileItem in fileItems) {
        if ([_fileItemsNeedingUpdatedPreviews member:fileItem])
            continue; // Already queued up.
        
        if ([_nonretained_delegate previewGenerator:self isFileItemCurrentlyOpen:fileItem])
            continue; // Ignore this one. The process of closing a document will update its preview and once we become visible we'll check for other previews that need to be updated.
        
        if (_addFileItemIfPreviewMissing(self, fileItem, fileItem.fileURL, fileItem.date))
            continue;
        
        OBFinishPortingLater("If a file item gains conflict versions we'll need to get called again");
        if (fileItem.hasUnresolvedConflicts) {
            // Request preview generation for the conflict versions. The conflict resolution UI might not be run, but it probably will, and it'll be nice to have them generated and ready to go.
            OBFinishPortingLater("Also need to mark these as used when looking for unused preview files");
            for (NSFileVersion *fileVersion in [NSFileVersion unresolvedConflictVersionsOfItemAtURL:fileItem.fileURL]) {
                if (_addFileItemIfPreviewMissing(self, fileItem, fileVersion.URL, fileVersion.modificationDate))
                    break;
            }
        }
    }
    
    if (![_nonretained_delegate previewGeneratorHasOpenDocument:self]) // Start updating previews immediately if there is no open document. Otherwise, queue them until the document is closed
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
    
    if (_currentPreviewUpdatingFileItem == nil) {
        OBASSERT(_previewUpdatingBackgroundTaskIdentifier == UIBackgroundTaskInvalid);
        return YES;
    }
    
    DEBUG_PREVIEW_GENERATION(@"Delaying opening document at %@ until preview refresh finishes for %@", fileItem.fileURL, _currentPreviewUpdatingFileItem.fileURL);
    
    // Delay the open until after we've finished updating this preview
    [_fileItemToOpenAfterCurrentPreviewUpdateFinishes release];
    _fileItemToOpenAfterCurrentPreviewUpdateFinishes = [fileItem retain];
    
    OBFinishPortingLater("Turn off user interaction while this is going on");
    return NO;
}

- (void)fileItemNeedsPreviewUpdate:(OFSDocumentStoreFileItem *)fileItem;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    // The process of closing a document will update its preview and once we become visible we'll check for other previews that need to be updated.
    if ([_nonretained_delegate previewGenerator:self isFileItemCurrentlyOpen:fileItem]) {
        DEBUG_PREVIEW_GENERATION(@"Document is open, ignoring change of %@.", fileItem.fileURL);
        return;
    }
    
    if ([_fileItemsNeedingUpdatedPreviews member:fileItem] == nil) {
        DEBUG_PREVIEW_GENERATION(@"Queueing preview update of %@", fileItem.fileURL);
        if (!_fileItemsNeedingUpdatedPreviews)
            _fileItemsNeedingUpdatedPreviews = [[NSMutableSet alloc] init];
        [_fileItemsNeedingUpdatedPreviews addObject:fileItem];
        
        if (![_nonretained_delegate previewGeneratorHasOpenDocument:self]) { // Start updating previews immediately if there is no open document. Otherwise, queue them until the document is closed
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

static void _writePreviewsForFileVersions(OUIDocumentPreviewGenerator *self, NSMutableArray *fileVersions)
{
    if ([fileVersions count] == 0) {
        // All done with the versions for this file item
        [self _finishedUpdatingPreview];
        return;
    }
    
    NSFileVersion *fileVersion = [[[fileVersions lastObject] retain] autorelease];
    [fileVersions removeLastObject];
    
    // Be careful to use the modification date we'd get otherwise for the current version. They should be the same, but...
    NSURL *fileURL;
    NSDate *date;
    if (fileVersion.conflict) {
        fileURL = fileVersion.URL;
        date = fileVersion.modificationDate;
    } else {
        fileURL = self->_currentPreviewUpdatingFileItem.fileURL;
        date = self->_currentPreviewUpdatingFileItem.date;
        OBASSERT([date isEqual:fileVersion.modificationDate]);
        fileVersion = nil; // pass nil for the conflict version below
    }
    
    Class cls = [self->_nonretained_delegate previewGenerator:self documentClassForFileURL:fileURL];
    OBASSERT(OBClassIsSubclassOfClass(cls, [OUIDocument class]));
    if (!cls) {
        _writePreviewsForFileVersions(self, fileVersions); // continue or finish up
        return;
    }
    
    NSError *error = nil;
    OUIDocument *document = [[cls alloc] initWithExistingFileItem:self->_currentPreviewUpdatingFileItem conflictFileVersion:fileVersion error:&error];
    if (!document) {
        NSLog(@"Error opening document at %@ to rebuild its preview: %@", fileURL, [error toPropertyList]);
    }
    
    // We have to figure out the the URL to figure out the class to make a document. Make sure we calculated the URL/date to preview the same way it did.
    OBASSERT([document.fileVersionURL isEqual:fileURL]);
    OBASSERT([document.fileVersionModificationDate isEqual:date]);
    DEBUG_PREVIEW_GENERATION(@"Starting preview update of %@ / %@ fileVersion:%@", [fileURL lastPathComponent], [date xmlString], fileVersion);

    // Let the document know that it is only going to be used to generate previews.
    document.forPreviewGeneration = YES;
    
    // Write blank previews before we start the opening process in case it crashes. Without this we could get into a state where launching the app would crash over and over. Now we should only crash once per bad document (still bad, but recoverable for the user). In addition to caching placeholder previews, this will write the empty marker preview files too.
    [OUIDocumentPreview cachePreviewImages:^(OUIDocumentPreviewCacheImage cacheImage) {
        cacheImage(NULL, [OUIDocumentPreview fileURLForPreviewOfFileURL:fileURL date:date withLandscape:YES]);
        cacheImage(NULL, [OUIDocumentPreview fileURLForPreviewOfFileURL:fileURL date:date withLandscape:NO]);
    }];
    
    [document openWithCompletionHandler:^(BOOL success){
        OBASSERT([NSThread isMainThread]);
        
        if (success) {
            [document _writePreviewsIfNeeded:NO /* have to pass NO since we just write bogus previews */ withCompletionHandler:^{
                OBASSERT([NSThread isMainThread]);
                
                [document closeWithCompletionHandler:^(BOOL success){
                    OBASSERT([NSThread isMainThread]);
                    
                    [document willClose];
                    [document release];
                    
                    DEBUG_PREVIEW_GENERATION(@"Finished preview update of %@ (version %@)", fileURL, fileVersion);
                    
                    // Wait until the close is done to end our background task (in case we are being backgrounded, we don't want an open document alive that might point at a document the user might delete externally).
                    _writePreviewsForFileVersions(self, fileVersions); // continue or finish up
                }];
            }];
        } else {
            OUIDocumentHandleDocumentOpenFailure(document, ^(BOOL success){
                _writePreviewsForFileVersions(self, fileVersions); // continue or finish up
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
    if (_fileItemToOpenAfterCurrentPreviewUpdateFinishes) {
        DEBUG_PREVIEW_GENERATION(@"Performing delayed open of document at %@", _fileItemToOpenAfterCurrentPreviewUpdateFinishes.fileURL);
        
        OFSDocumentStoreFileItem *fileItem = [_fileItemToOpenAfterCurrentPreviewUpdateFinishes autorelease];
        _fileItemToOpenAfterCurrentPreviewUpdateFinishes = nil;
        
        [_nonretained_delegate previewGenerator:self performDelayedOpenOfFileItem:fileItem];
        return;
    }
    
    while (_currentPreviewUpdatingFileItem == nil) {
        _currentPreviewUpdatingFileItem = [[_nonretained_delegate previewGenerator:self preferredFileItemForNextPreviewUpdate:_fileItemsNeedingUpdatedPreviews] retain];
        if (!_currentPreviewUpdatingFileItem)
            _currentPreviewUpdatingFileItem = [[_fileItemsNeedingUpdatedPreviews anyObject] retain];
        
        if (!_currentPreviewUpdatingFileItem)
            return; // No more to do!
        
        // We don't want to open the document and provoke download. If the user taps it to provoke download, or iCloud auto-downloads it, we'll get notified via the document store's metadata query and will update the preview again.
        if ([_currentPreviewUpdatingFileItem isDownloaded] == NO) {
            OBASSERT([_fileItemsNeedingUpdatedPreviews member:_currentPreviewUpdatingFileItem] == _currentPreviewUpdatingFileItem);
            [_fileItemsNeedingUpdatedPreviews removeObject:_currentPreviewUpdatingFileItem];
            [_currentPreviewUpdatingFileItem autorelease];
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
    
    OBASSERT(_currentPreviewUpdatingFileItem.beingDeleted == NO);
    NSURL *fileURL = _currentPreviewUpdatingFileItem.fileURL;
    NSFileVersion *fileVersion = [NSFileVersion currentVersionOfItemAtURL:fileURL];
    
    if (!fileVersion) {
        // The file was deleted while it was queued up for preview generation.
#ifdef OMNI_ASSERTIONS_ON
        NSError *availableError = nil;
        OBASSERT(![fileURL checkResourceIsReachableAndReturnError:&availableError]);
        OBASSERT([availableError hasUnderlyingErrorDomain:NSPOSIXErrorDomain code:ENOENT]);
#endif
        [self _finishedUpdatingPreview];
        return;
    }
    
    OBASSERT([fileVersion.modificationDate isEqual:_currentPreviewUpdatingFileItem.date]); // since we use the date in the file name, we need to be consistent
              
    NSMutableArray *fileVersions = [NSMutableArray arrayWithObjects: fileVersion, nil];
    [fileVersions addObjectsFromArray:[NSFileVersion unresolvedConflictVersionsOfItemAtURL:fileURL]];
    
    DEBUG_PREVIEW_GENERATION(@"Starting preview update for %@ at %@ (%ld versions)", fileURL, [_currentPreviewUpdatingFileItem.date xmlString], [fileVersions count]);
    
    _writePreviewsForFileVersions(self, fileVersions);
}

- (void)_finishedUpdatingPreview;
{
    OBPRECONDITION(_currentPreviewUpdatingFileItem != nil);
    OBPRECONDITION(_previewUpdatingBackgroundTaskIdentifier != UIBackgroundTaskInvalid);
    
    OFSDocumentStoreFileItem *fileItem = [_currentPreviewUpdatingFileItem autorelease];
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
    [_fileItemToOpenAfterCurrentPreviewUpdateFinishes release];
    _fileItemToOpenAfterCurrentPreviewUpdateFinishes = nil;
    
    // On our next foregrounding, we'll restart our preview updating anyway. If we have a preview generation in progress, try to wait for that to complete, though. Otherwise if it happens to complete after we say we can get backgrounded, our read/writing of the image can fail with EINVAL (presumably they close up the sandbox).
    [_fileItemsNeedingUpdatedPreviews removeAllObjects];
}

@end
