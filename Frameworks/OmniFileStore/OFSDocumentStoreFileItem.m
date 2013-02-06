// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFileStore/OFSDocumentStoreFileItem.h>

#import <Foundation/NSFileCoordinator.h>
#import <Foundation/NSOperation.h>
#import <OmniFileStore/OFSDocumentStore.h>
#import <OmniFileStore/OFSDocumentStoreScope-Subclass.h>
#import <OmniFoundation/NSString-OFPathExtensions.h>
#import <OmniFoundation/OFFilePresenterEdits.h>
#import <OmniFoundation/OFUTI.h>

#import "OFSDocumentStoreFileItem-Internal.h"
#import "OFSDocumentStoreItem-Internal.h"
#import "OFSDocumentStoreScope-Internal.h"


RCS_ID("$Id$");

#if 0 && defined(DEBUG)
    #define DEBUG_FILE_ITEM_ENABLED 1
    #define DEBUG_FILE_ITEM(format, ...) NSLog(@"FILE ITEM %@: " format, [self shortDescription], ## __VA_ARGS__)
#else
    #define DEBUG_FILE_ITEM(format, ...)
#endif

NSString * const OFSDocumentStoreFileItemFileURLBinding = @"fileURL";
NSString * const OFSDocumentStoreFileItemSelectedBinding = @"selected";
NSString * const OFSDocumentStoreFileItemDownloadRequestedBinding = @"downloadRequested";

static NSString * const OFSDocumentStoreFileItemDisplayedFileURLBinding = @"displayedFileURL";

@interface OFSDocumentStoreFileItem ()
@property(copy,nonatomic) NSString *fileType;
@property(nonatomic) BOOL downloadRequested;
- (void)_queueContentsChanged;
@end

NSString * const OFSDocumentStoreFileItemContentsChangedNotification = @"OFSDocumentStoreFileItemContentsChanged";
NSString * const OFSDocumentStoreFileItemFinishedDownloadingNotification = @"OFSDocumentStoreFileItemFinishedDownloading";
NSString * const OFSDocumentStoreFileItemInfoKey = @"fileItem";

@implementation OFSDocumentStoreFileItem
{
    // ivars for properties in the OFSDocumentStoreItem protocol
    BOOL _hasUnresolvedConflicts;
    BOOL _isDownloaded;
    BOOL _isDownloading;
    BOOL _isUploaded;
    BOOL _isUploading;
    double _percentDownloaded;
    double _percentUploaded;
    
    // File presenter support
    NSURL *_filePresenterURL; // NSFilePresenter needs to get/set this on multiple threads
    NSURL *_displayedFileURL; // A mirrored copy of _fileURL that is only changed on the main thread to fire KVO for the name key.
    
    BOOL _hasRegisteredAsFilePresenter;
    NSOperationQueue *_presentedItemOperationQueue;
    
    OFFilePresenterEdits *_edits; // Keep track of edits that have happened while we have relinquished for a writer.
}

+ (void)initialize;
{
    OBINITIALIZE;
    
    OBASSERT(OBClassImplementingMethod(self, @selector(name)) == [OFSDocumentStoreFileItem class]); // Subclass +displayNameForFileURL:fileType: instead.
    OBASSERT(OBClassImplementingMethod(self, @selector(editingName)) == [OFSDocumentStoreFileItem class]); // Subclass +editingNameForFileURL:fileType: instead.
}

+ (NSString *)displayNameForFileURL:(NSURL *)fileURL fileType:(NSString *)fileType;
{
    return [self editingNameForFileURL:fileURL fileType:fileType];
}

+ (NSString *)editingNameForFileURL:(NSURL *)fileURL fileType:(NSString *)fileType;
{
    return [[[fileURL path] lastPathComponent] stringByDeletingPathExtension];
}

+ (NSString *)exportingNameForFileURL:(NSURL *)fileURL fileType:(NSString *)fileType;
{
    return [self displayNameForFileURL:fileURL fileType:fileType];
}

- initWithScope:(OFSDocumentStoreScope *)scope fileURL:(NSURL *)fileURL date:(NSDate *)date;
{
    OBPRECONDITION(scope);
    OBPRECONDITION(fileURL);
    OBPRECONDITION([fileURL isFileURL]);
    OBPRECONDITION(date);
    OBPRECONDITION(scope.documentStore);
    OBPRECONDITION([scope isFileInContainer:fileURL]);

    if (!fileURL) {
        OBASSERT_NOT_REACHED("Bad caller");
        return nil;
    }
    
    // NOTE: OFSDocumentStoreFileItem CANNOT keep a pointer to an OFXFileItem (since when generating conflict versions the URL of the file item doesn't change). See -[OFXFileItem _generateConflictDocumentAndRevertToTemporaryDocumentContentsAtURL:coordinator:error:].

    if (!(self = [super initWithScope:scope]))
        return nil;
    
    _filePresenterURL = [fileURL copy];
    _displayedFileURL = _filePresenterURL;
    _date = [date copy];
    _edits = [[OFFilePresenterEdits alloc] initWithFileURL:_filePresenterURL];

    NSNumber *isDirectory = nil;
    NSError *resourceError = nil;
    if (![_filePresenterURL getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:&resourceError]) {
        NSLog(@"Error getting directory key for %@: %@", _filePresenterURL, [resourceError toPropertyList]);
        OBASSERT_NOT_REACHED("Possibly messed up accommodatePresentedItemDeletionWithCompletionHandler:");
    }
    _fileType = [OFUTIForFileExtensionPreferringNative([_filePresenterURL pathExtension], isDirectory) copy];
    OBASSERT(_fileType);

    _presentedItemOperationQueue = [[NSOperationQueue alloc] init];
    [_presentedItemOperationQueue setName:[NSString stringWithFormat:@"OFSDocumentStoreFileItem presenter queue -- %@", OBShortObjectDescription(self)]];
    [_presentedItemOperationQueue setMaxConcurrentOperationCount:1];
    
    // NOTE: This retains us, so we cannot wait until -dealloc to do -removeFilePresenter:!
    _hasRegisteredAsFilePresenter = YES;
    [NSFileCoordinator addFilePresenter:self];
    DEBUG_FILE_ITEM(@"Added as file presenter");
    
    // Reasonable values for local documents that will never get updated by a sync container agent.
    _hasUnresolvedConflicts = kOFSDocumentStoreFileItemDefault_HasUnresolvedConflicts;
    _isDownloaded = kOFSDocumentStoreFileItemDefault_IsDownloaded;
    _isDownloading = kOFSDocumentStoreFileItemDefault_IsDownloading;
    _isUploaded = kOFSDocumentStoreFileItemDefault_IsUploaded;
    _isUploading = kOFSDocumentStoreFileItemDefault_IsUploading;
    _percentDownloaded = kOFSDocumentStoreFileItemDefault_PercentDownloaded;
    _percentUploaded = kOFSDocumentStoreFileItemDefault_PercentUploaded;

    return self;
}

- (void)dealloc;
{
    // NOTE: We cannot wait until here to -removeFilePresenter: since -addFilePresenter: retains us. We remove in -_invalidate
    OBASSERT([_presentedItemOperationQueue operationCount] == 0);
}

// This isn't declared as atomic, but we make it so so that -presentedItemDidMoveToURL: and -presentedItemURL (which can get called on various threads) can use it. Other uses of our file URL may have other serialization issues w.r.t. incoming sync edits and the edits we do on the document store action queue (since we don't have -performAsynchronousFileAccessUsingBlock: here... yet).
- (NSURL *)fileURL;
{
    NSURL *URL;
    
    // This and -presentedItemDidMoveToURL: can get called on varying threads, so make sure we can deal with that as best we can.
    @synchronized(self) {
        URL = _filePresenterURL;
    }
    
    return URL;
}

// See notes on -fileURL regarding atomicity.
@synthesize fileType = _fileType; // Just makes the ivar since we implement both accessors.
- (NSString *)fileType;
{
    NSString *fileType;
    
    // This and -presentedItemDidMoveToURL: can get called on varying threads, so make sure we can deal with that as best we can.
    @synchronized(self) {
        fileType = _fileType;
    }
    
    OBPOSTCONDITION(fileType);
    return fileType;
}

- (void)setFileType:(NSString *)fileType;
{
    OBPRECONDITION(fileType);
    
    @synchronized(self) {
        if (OFNOTEQUAL(_fileType, fileType)) {
            _fileType = [fileType copy];
        }
    }
}

- (NSData *)emailData;
{
    return [NSData dataWithContentsOfURL:self.fileURL];
}

- (NSString *)emailFilename;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    return [[_displayedFileURL path] lastPathComponent];
}

- (NSString *)editingName;
{
    OBPRECONDITION([NSThread isMainThread]);

    return [[self class] editingNameForFileURL:_displayedFileURL fileType:self.fileType];
}

- (NSString *)exportingName;
{
    OBPRECONDITION([NSThread isMainThread]);

    return [[self class] exportingNameForFileURL:_displayedFileURL fileType:self.fileType];
}

+ (NSSet *)keyPathsForValuesAffectingName;
{
    return [NSSet setWithObjects:OFSDocumentStoreFileItemDisplayedFileURLBinding, nil];
}

- (BOOL)isBeingDeleted;
{
    return _edits.hasAccommodatedDeletion;
}

- (NSComparisonResult)compare:(OFSDocumentStoreFileItem *)otherItem;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    // First, compare dates
    NSComparisonResult dateComparison = [self.date compare:otherItem.date];
    switch (dateComparison) {
        default: case NSOrderedSame:
            break;
        case NSOrderedAscending:
            return NSOrderedDescending; // Newer documents come first
        case NSOrderedDescending:
            return NSOrderedAscending; // Newer documents come first
    }

    // Then compare name and if the names are equal, duplication counters.
    NSString *name1, *name2;
    NSUInteger counter1, counter2;
    
    [self.name splitName:&name1 andCounter:&counter1];
    [otherItem.name splitName:&name2 andCounter:&counter2];
    
    

    NSComparisonResult caseInsensitiveCompare = [name1 localizedCaseInsensitiveCompare:name2];
    if (caseInsensitiveCompare != NSOrderedSame)
        return caseInsensitiveCompare; // Sort names into alphabetical order

    // Use the duplication counters, in reverse order ("Foo 2" should be to the left of "Foo").
    if (counter1 < counter2)
        return NSOrderedDescending;
    else if (counter1 > counter2)
        return NSOrderedAscending;
    
    // If all else is equal, compare URLs (maybe different extensions?).  (If those are equal, so are the items!)
    return [[_displayedFileURL absoluteString] compare:[otherItem->_displayedFileURL absoluteString]];
}

#pragma mark - OFSDocumentStoreItem subclass

- (void)_invalidate;
{
    if (_hasRegisteredAsFilePresenter) {
        DEBUG_FILE_ITEM(@"Removed as file presenter");
        
        _hasRegisteredAsFilePresenter = NO;
        [NSFileCoordinator removeFilePresenter:self];
    }
    
    [super _invalidate];
}

#pragma mark - OFSDocumentStoreItem protocol

- (NSString *)name;
{
    return [[self class] displayNameForFileURL:self.fileURL fileType:self.fileType];
}

- (void)setDate:(NSDate *)date;
{
    OBPRECONDITION([NSThread isMainThread]); // Ensure we are only firing KVO on the main thread
    OBPRECONDITION(date);
    
    if (OFISEQUAL(_date, date))
        return;
    
    _date = [date copy];
}

- (BOOL)isReady;
{
    return YES;
}

@synthesize hasUnresolvedConflicts = _hasUnresolvedConflicts;
@synthesize isDownloaded = _isDownloaded;
@synthesize isDownloading = _isDownloading;
@synthesize isUploaded = _isUploaded;
@synthesize isUploading = _isUploading;
@synthesize percentDownloaded = _percentDownloaded;
@synthesize percentUploaded = _percentUploaded;

- (void)setIsDownloaded:(BOOL)isDownloaded;
{
    OBPRECONDITION([NSThread isMainThread]);

    if (_isDownloaded == isDownloaded)
        return;
    
    BOOL finishedDownloading = (!_isDownloaded && isDownloaded);
    _isDownloaded = isDownloaded;
    
    if (finishedDownloading) {
        self.downloadRequested = NO;
        
        // The downloading process sends -presentedItemDidChange a couple times during downloading, but not right at the end, sadly.
        [self _queueContentsChanged];
        
        [self.scope fileItemFinishedDownloading:self];
    }
}

- (BOOL)requestDownload:(NSError **)outError;
{
    OBPRECONDITION([NSThread isMainThread]); // Only want to fire KVO on the main thread
    
    self.downloadRequested = YES;

    return [self.scope requestDownloadOfFileItem:self error:outError];
}

#pragma mark - NSFilePresenter protocol

- (NSURL *)presentedItemURL;
{
    NSURL *url = self.fileURL;
    OBASSERT(url);
    return url;
}

- (NSOperationQueue *)presentedItemOperationQueue;
{
    OBPRECONDITION(_presentedItemOperationQueue); // Otherwise NSFileCoordinator may try to enqueue blocks and they'll never get started, yielding mysterious deadlocks.
    return _presentedItemOperationQueue;
}

// Writer notifications can come in random/bad order (for example a 'did change' when the file has really already been deleted and we are about to get an 'accomodate').
- (void)relinquishPresentedItemToWriter:(void (^)(void (^reacquirer)(void)))writer;
{
    OBPRECONDITION(_hasRegisteredAsFilePresenter); // Make sure we don't de-register when we might have queued up file presenter messages
    OBPRECONDITION(_edits);

    [_edits presenter:self relinquishToWriter:writer];
}

- (void)accommodatePresentedItemDeletionWithCompletionHandler:(void (^)(NSError *errorOrNil))completionHandler;
{
    OBPRECONDITION(_hasRegisteredAsFilePresenter); // Make sure we don't de-register when we might have queued up file presenter messages
    OBPRECONDITION(_edits); // Since we should always get -relinquishPresentedItemToWriter: for deletion
    
    [_edits presenter:self accommodateDeletion:^(OFSDocumentStoreFileItem *_self){
        [_self.scope _fileItemHasAccommodatedDeletion:self];
    }];
    
    if (completionHandler)
        completionHandler(nil);
}

- (void)presentedItemDidMoveToURL:(NSURL *)newURL;
{
    OBPRECONDITION(_hasRegisteredAsFilePresenter); // Make sure we don't de-register when we might have queued up file presenter messages
    OBPRECONDITION([NSOperationQueue currentQueue] == _presentedItemOperationQueue);
    OBPRECONDITION(newURL);
    OBPRECONDITION([newURL isFileURL]);
    OBPRECONDITION(_edits);

    DEBUG_FILE_ITEM(@"presentedItemDidMoveToURL: %@", newURL);
    
    // See -presentedItemURL's documentation about it being called from various threads. This method should only be called from our presenter queue.
    @synchronized(self) {
        if (OFISEQUAL(_filePresenterURL, newURL))
            return;
        NSURL *oldURL = [_filePresenterURL copy];
        NSDate *oldDate = [_date copy];
        
        // This can get called from various threads
        _filePresenterURL = [newURL copy];

        // NOTE: OFFilePresenterEditsDidMove will call this directly if not in a writer block, otherwise when we reacquire
        [_edits presenter:self didMoveFromURL:oldURL date:oldDate toURL:newURL handler:^(OFSDocumentStoreFileItem *_self, NSURL *originalURL, NSDate *originalDate){
            // Might be called delayed, out of the enclosing @synchronized if we are in a writer block.
            @synchronized(self) {
                [_self _synchronized_processItemDidMoveFromURL:oldURL date:oldDate];
            }
        }];
    }
}

// This gets called for local coordinated writes and for unsolicited incoming edits from sync. From the header, "Your NSFileProvider may be sent this message without being sent -relinquishPresentedItemToWriter: first. Make your application do the best it can in that case."
- (void)presentedItemDidChange;
{
    OBPRECONDITION(_hasRegisteredAsFilePresenter); // Make sure we don't de-register when we might have queued up file presenter messages
    OBPRECONDITION([NSOperationQueue currentQueue] == _presentedItemOperationQueue);
    OBPRECONDITION(_edits);

    DEBUG_FILE_ITEM(@"presentedItemDidChange");

    [_edits presenter:self changed:^(OFSDocumentStoreFileItem *_self){
        [_self _queueContentsChanged];
    }];
}

- (void)presentedItemDidGainVersion:(NSFileVersion *)version;
{
    OBPRECONDITION(_hasRegisteredAsFilePresenter); // Make sure we don't de-register when we might have queued up file presenter messages
    OBPRECONDITION([NSOperationQueue currentQueue] == _presentedItemOperationQueue);

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    // Only conflict versions happen on iOS; so we shouldn't hit this at all
    OBASSERT_NOT_REACHED("We no longer use iCloud and have no way of creating our own NSFileVersions, so this should never happen");
#else
    // On the Mac, cmd-S makes a non-conflict version... that's OK.
    OBASSERT(version.conflict == NO, "We no longer use iCloud and have no way of creating our own NSFileVersions, so this should never happen");
#endif
}

- (void)presentedItemDidLoseVersion:(NSFileVersion *)version;
{
    OBPRECONDITION(_hasRegisteredAsFilePresenter); // Make sure we don't de-register when we might have queued up file presenter messages
    OBPRECONDITION([NSOperationQueue currentQueue] == _presentedItemOperationQueue);

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    // Only conflict versions happen on iOS; so we shouldn't hit this at all
    OBASSERT_NOT_REACHED("We no longer use iCloud and have no way of creating our own NSFileVersions, so this should never happen");
#else
    // On the Mac, cmd-S makes a non-conflict version... that's OK.
    OBASSERT(version.conflict == NO, "We no longer use iCloud and have no way of creating our own NSFileVersions, so this should never happen");
#endif
}

- (void)presentedItemDidResolveConflictVersion:(NSFileVersion *)version;
{
    OBPRECONDITION(_hasRegisteredAsFilePresenter); // Make sure we don't de-register when we might have queued up file presenter messages
    OBPRECONDITION([NSOperationQueue currentQueue] == _presentedItemOperationQueue);

    OBASSERT_NOT_REACHED("We no longer use iCloud and have no way of creating our own NSFileVersions, so this should never happen");
}

#pragma mark - Debugging

- (NSString *)shortDescription;
{
    return [NSString stringWithFormat:@"<%@:%p '%@' date:%@>", NSStringFromClass([self class]), self, self.presentedItemURL, [self.date xmlString]];
}

#pragma mark - Internal

- (void)_invalidateAfterWriter;
{
    OBPRECONDITION(_edits);

    // The _edits.relinquishToWriter is maintained on this queue, so dispatch before we check it.
    [_presentedItemOperationQueue addOperationWithBlock:^{
        [_edits presenter:self invalidateAfterWriter:^(OFSDocumentStoreFileItem *_self){
            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                [_self _invalidate];
            }];
        }];
    }];
}

#pragma mark - Private

// Split out to make sure we only capture the variables we want and they are the non-__block versions so they get retained until the block executes
static void _notifyDateAndFileType(OFSDocumentStoreFileItem *self, NSDate *modificationDate, NSString *fileType)
{
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        // -presentedItemDidChange can get called at the end of a rename operation (after -presentedItemDidMoveToURL:). Only send our notification if we "really" changed.
        BOOL didChange = OFNOTEQUAL(self.date, modificationDate) || OFNOTEQUAL(self.fileType, fileType);
        if (!didChange)
            return;
        
        // Fire KVO on the main thread
        self.date = modificationDate;
        self.fileType = fileType;
        
        // We can't shunt the notification to the main thread immediately. There may be other file presenter methods incoming (and importantly, for a file rename there will be one that changes our URL). So, queue this on our presenter queue.
        [self->_presentedItemOperationQueue addOperationWithBlock:^{
            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                [self.scope _fileItemContentsChanged:self];
            }];
        }];
    }];
}

// Asynchronously refreshes the date and sends a OFSDocumentStoreFileItemContentsChangedNotification notification
- (void)_queueContentsChanged;
{
    // We get sent -presentedItemDidChange even after -accommodatePresentedItemDeletionWithCompletionHandler:.
    // We don't need to not any content changes and if we try to get our modification date, we'll be unable to read the attributes of our file in the dead zone anyway.
    if (_edits.hasAccommodatedDeletion) {
        DEBUG_FILE_ITEM(@"Deleted: ignoring change");
        return;
    }
    
    DEBUG_FILE_ITEM(@"Queuing contents changed update");

    [self.scope performAsynchronousFileAccessUsingBlock:^{
        
        /*
         NOTE: We do NOT use a coordinated read here anymore, though we would like to. If we are getting an incoming sync rename, we could end up deadlocking.
         
         First, there is Radar 10879451: Bad and random ordering of NSFilePresenter notifications. This means we can get a lone -presentedItemDidChange before the relinquish-to-writer wrapped presentedItemDidMoveToURL:. But, we have the old URL at this point. Doing a coordinated read on that URL blocks forever (see Radar 11076208: Coordinated reads started in response to -presentedItemDidChange can hang).
         */
                
        NSDate *modificationDate = nil;
        NSString *fileType = nil;
        
        NSError *error = nil;
        
        NSURL *fileURL = self.fileURL;
        
        // We use the file modification date rather than a date embedded inside the file since the latter would cause duplicated documents to not sort to the front as a new document (until you modified them, at which point they'd go flying to the beginning).
        NSError *attributesError = nil;
        NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:[[fileURL absoluteURL] path]  error:&attributesError];
        if (!attributes)
            NSLog(@"Error getting attributes for %@ -- %@", [fileURL absoluteString], [attributesError toPropertyList]);
        else
            modificationDate = [attributes fileModificationDate];
        if (!modificationDate)
            modificationDate = [NSDate date]; // Default to now if we can't get the attributes or they are bogus for some reason.
        
        // Some file types may have the same extension but different UTIs based on whether they are a directory or not.
        BOOL isDirectory = [[attributes objectForKey:NSFileType] isEqual:NSFileTypeDirectory];
        
        fileType = OFUTIForFileExtensionPreferringNative([fileURL pathExtension], [NSNumber numberWithBool:isDirectory]);
        
        if (!modificationDate) {
            NSLog(@"Error performing coordinated read of modification date of %@: %@", [fileURL absoluteString], [error toPropertyList]);
            modificationDate = [NSDate date]; // Default to now if we can't get the attributes or they are bogus for some reason.
        }
        
        OBASSERT(![NSThread isMainThread]);
        
        _notifyDateAndFileType(self, modificationDate, fileType);
    }];
}

- (void)_synchronized_processItemDidMoveFromURL:(NSURL *)oldURL date:(NSDate *)oldDate;
{
    // Called either from -presentedItemDidMoveToURL: if we aren't inside of a writer block, or from the reacquire block in our -relinquishPresentedItemToWriter:. The caller should @synchronized(self) {...} around this since it accesses the _filePresenterURL, which needs to be accessible from the our operation queue and the main queue.
    
    // When we get deleted via sync, our on-disk representation could get moved into a dead zone. Don't present that to the user briefly. Also, don't try to look at the time stamp on the dead file or poke it with a stick in any fashion.
    if (_edits.hasAccommodatedDeletion) {
        DEBUG_FILE_ITEM(@"Deleted; ignoring move");
        
        // Try to make sure we actually are getting moved to the ubd dead zone
        OBASSERT([[_filePresenterURL absoluteString] containsString:@"/.ubd/"]);
        OBASSERT([[_filePresenterURL absoluteString] containsString:@"/dead-"]);
    } else {
        DEBUG_FILE_ITEM(@"Handling move from %@ / %@ to %@", oldURL, oldDate, _filePresenterURL);
        
#ifdef OMNI_ASSERTIONS_ON
        BOOL probablyInvalid = NO;
#endif
        NSNumber *isDirectory = nil;
        NSError *resourceError = nil;
        if (![_filePresenterURL getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:&resourceError]) {
            // If we get EPERM, it is most likely because the iCloud Documents & Data was turned off while the app was backgrounded. In this case, when foregrounded, we get a -relinquishPresentedItemToWriter: with a -presentedItemDidMoveToURL: into something like <file://localhost/var/mobile/Library/Mobile%20Documents.1181216313/...> We do *not* get told, sadly, that we've been deleted and these messages come through before the finish of the new scan.
            if ([resourceError hasUnderlyingErrorDomain:NSPOSIXErrorDomain code:EPERM]) {
#ifdef OMNI_ASSERTIONS_ON
                probablyInvalid = YES;
#endif
            } else
                NSLog(@"Error getting directory key for %@: %@", _filePresenterURL, [resourceError toPropertyList]);
        }
        _fileType = [OFUTIForFileExtensionPreferringNative([_filePresenterURL pathExtension], isDirectory) copy];
        OBASSERT(_fileType);
        
        // Update KVO on the main thread.
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            // On iOS, this lets the document preview be moved.
            if (![self _hasBeenInvalidated]) {
                [self.scope fileWithURL:oldURL andDate:oldDate didMoveToURL:_filePresenterURL];
                // might not have been invalidated yet...
            } else {
                OBASSERT(probablyInvalid == YES);
            }
            
            [self willChangeValueForKey:OFSDocumentStoreFileItemDisplayedFileURLBinding];
            _displayedFileURL = [_filePresenterURL copy];
            [self didChangeValueForKey:OFSDocumentStoreFileItemDisplayedFileURLBinding];
        }];
    }
}

@end
