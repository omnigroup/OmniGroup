// Copyright 2010-2012 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFileStore/OFSDocumentStoreFileItem.h>

#import <OmniFileStore/OFSFeatures.h>

#if OFS_DOCUMENT_STORE_SUPPORTED

#import <OmniFoundation/NSString-OFPathExtensions.h>
#import <OmniFoundation/OFUTI.h>

#import <OmniFileStore/OFSDocumentStore.h>
#import "OFSShared_Prefix.h"
#import "OFSDocumentStoreItem-Internal.h"
#import "OFSDocumentStoreFileItem-Internal.h"
#import "OFSDocumentStore-Internal.h"

#import <Foundation/NSOperation.h>
#import <Foundation/NSFileCoordinator.h>
#import <Foundation/NSMetadata.h>

RCS_ID("$Id$");

// OFSDocumentStoreFileItem
OBDEPRECATED_METHOD(-hasPDFPreview);
OBDEPRECATED_METHOD(-previewTargetSize);
OBDEPRECATED_METHOD(-makePreviewOfSize:error:); // -makePreviewWithLandscape:error:
OBDEPRECATED_METHOD(-getPDFPreviewData:modificationDate:error:);
OBDEPRECATED_METHOD(+placeholderPreviewImageForProxy:landscape:); // +placeholderPreviewImageForFileItem:landscape:

// Stuff moved out to OUIDocument with various renaming to take a file item as a parameter if needed
OBDEPRECATED_METHOD(-fileURLForPreviewWithLandscape:);
OBDEPRECATED_METHOD(-previewsValid);
OBDEPRECATED_METHOD(-previewSizeForTargetSize:aspectRatio:);
OBDEPRECATED_METHOD(-makePreviewWithLandscape:error:);
OBDEPRECATED_METHOD(-placeholderPreviewImageForFileItem:landscape:);
OBDEPRECATED_METHOD(-writePreviewsForDocument:error:);
OBDEPRECATED_METHOD(-cameraRollImage);


NSString * const OFSDocumentStoreFileItemFilePresenterURLBinding = @"filePresenterURL";
NSString * const OFSDocumentStoreFileItemSelectedBinding = @"selected";

static NSString * const OFSDocumentStoreFileItemDisplayedFileURLBinding = @"displayedFileURL";

@interface OFSDocumentStoreFileItem ()
@property(copy,nonatomic) NSString *fileType;
- (void)_queueContentsChanged;
#if DEBUG_VERSIONS_ENABLED
- (void)_logVersions;
#endif
@end

#define kOFSDocumentStoreFileItemDefault_HasUnresolvedConflicts (NO)
#define kOFSDocumentStoreFileItemDefault_IsDownloaded (YES)
#define kOFSDocumentStoreFileItemDefault_IsDownloading (NO)
#define kOFSDocumentStoreFileItemDefault_IsUploaded (YES)
#define kOFSDocumentStoreFileItemDefault_IsUploading (NO)
#define kOFSDocumentStoreFileItemDefault_PercentDownloaded (100)
#define kOFSDocumentStoreFileItemDefault_PercentUploaded (100)

NSString * const OFSDocumentStoreFileItemContentsChangedNotification = @"OFSDocumentStoreFileItemContentsChanged";
NSString * const OFSDocumentStoreFileItemFinishedDownloadingNotification = @"OFSDocumentStoreFileItemFinishedDownloading";
NSString * const OFSDocumentStoreFileItemInfoKey = @"fileItem";

@implementation OFSDocumentStoreFileItem
{
    NSURL *_filePresenterURL; // NSFilePresenter needs to get/set this on multiple threads
    NSURL *_displayedFileURL; // A mirrored copy of _fileURL that is only changed on the main thread to fire KVO for the name key.
    
    NSDate *_date;
    NSString *_fileType;
    
    BOOL _hasUnresolvedConflicts;
    BOOL _isDownloaded;
    BOOL _isDownloading;
    BOOL _isUploaded;
    BOOL _isUploading;
    double _percentDownloaded;
    double _percentUploaded;
    
    BOOL _hasRegisteredAsFilePresenter;
    NSOperationQueue *_presentedItemOperationQueue;

    BOOL _selected;
    BOOL _draggingSource;
    BOOL _isBeingDeleted;
}

+ (void)initialize;
{
    OBINITIALIZE;
    
    OBASSERT_NOT_IMPLEMENTED(self, initWithURL:); // -initWithFileURL:
    OBASSERT_NOT_IMPLEMENTED(self, displayNameForURL:); // Moved to -name and -editingName
    OBASSERT_NOT_IMPLEMENTED(self, editNameForURL:);
}

- initWithDocumentStore:(OFSDocumentStore *)documentStore fileURL:(NSURL *)fileURL date:(NSDate *)date;
{
    OBPRECONDITION(fileURL);
    OBPRECONDITION([fileURL isFileURL]);
    OBPRECONDITION(date);

    if (!fileURL) {
        OBASSERT_NOT_REACHED("Bad caller");
        [self release];
        return nil;
    }
    
    if (!(self = [super initWithDocumentStore:documentStore]))
        return nil;
        
    _filePresenterURL = [fileURL copy];
    _displayedFileURL = [_filePresenterURL retain];
    
    _date = [date copy];
    
    NSNumber *isDirectory = nil;
    NSError *resourceError = nil;
    if (![_filePresenterURL getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:&resourceError]) {
        NSLog(@"Error getting directory key for %@: %@", _filePresenterURL, [resourceError toPropertyList]);
    }
    _fileType = [OFUTIForFileExtensionPreferringNative([_filePresenterURL pathExtension], [isDirectory boolValue]) copy];
    OBASSERT(_fileType);

    _presentedItemOperationQueue = [[NSOperationQueue alloc] init];
    [_presentedItemOperationQueue setName:[NSString stringWithFormat:@"OFSDocumentStoreFileItem presenter queue -- %@", OBShortObjectDescription(self)]];
    [_presentedItemOperationQueue setMaxConcurrentOperationCount:1];
    
    // NOTE: This retains us, so we cannot wait until -dealloc to do -removeFilePresenter:!
    _hasRegisteredAsFilePresenter = YES;
    [NSFileCoordinator addFilePresenter:self];
    
    // Reasonable values for local documents that will never get sent -_updateWithMetadataItem: 
    _hasUnresolvedConflicts = kOFSDocumentStoreFileItemDefault_HasUnresolvedConflicts;
    _isDownloaded = kOFSDocumentStoreFileItemDefault_IsDownloaded;
    _isDownloading = kOFSDocumentStoreFileItemDefault_IsDownloading;
    _isUploaded = kOFSDocumentStoreFileItemDefault_IsUploaded;
    _isUploading = kOFSDocumentStoreFileItemDefault_IsUploading;
    _percentDownloaded = kOFSDocumentStoreFileItemDefault_PercentDownloaded;
    _percentUploaded = kOFSDocumentStoreFileItemDefault_PercentUploaded;

#if DEBUG_VERSIONS_ENABLED
    DEBUG_VERSIONS(@"Set fileURL for %@", [self shortDescription]);
    [self _logVersions];
#endif

    return self;
}

- (void)dealloc;
{
    // NOTE: We cannot wait until here to -removeFilePresenter: since -addFilePresenter: retains us. We remove in -_invalidate
    OBASSERT([_presentedItemOperationQueue operationCount] == 0);
    [_presentedItemOperationQueue release];

    [_filePresenterURL release];
    [_displayedFileURL release];
    [_date release];
    [_fileType release];
    
    [super dealloc];
}

// This isn't declared as atomic, but we make it so so that -presentedItemDidMoveToURL: and -presentedItemURL (which can get called on various threads) can use it. Other uses of our file URL may have other serialization issues w.r.t. incoming iCloud edits and the edits we do on the document store action queue (since we don't have -performAsynchronousFileAccessUsingBlock: here... yet).
- (NSURL *)fileURL;
{
    NSURL *URL;
    
    // This and -presentedItemDidMoveToURL: can get called on varying threads, so make sure we can deal with that as best we can.
    @synchronized(self) {
        URL = [_filePresenterURL retain];
    }
    
    return [URL autorelease];
}

// See notes on -fileURL regarding atomicity.
- (NSString *)fileType;
{
    NSString *fileType;
    
    // This and -presentedItemDidMoveToURL: can get called on varying threads, so make sure we can deal with that as best we can.
    @synchronized(self) {
        fileType = [_fileType retain];
    }
    
    OBPOSTCONDITION(fileType);
    return [fileType autorelease];
}

- (void)setFileType:(NSString *)fileType;
{
    OBPRECONDITION(fileType);
    
    @synchronized(self) {
        if (OFNOTEQUAL(_fileType, fileType)) {
            [_fileType release];
            _fileType = [fileType copy];
        }
    }
}

- (OFSDocumentStoreScope *)scope;
{
    // This is derived from fileURL so that when a coordinated move happens and we get a new fileURL, our scope automatically changes.
    return [self.documentStore scopeForFileURL:self.fileURL];
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

    return [[[_displayedFileURL path] lastPathComponent] stringByDeletingPathExtension];
}

+ (NSSet *)keyPathsForValuesAffectingName;
{
    return [NSSet setWithObjects:OFSDocumentStoreFileItemDisplayedFileURLBinding, nil];
}

@synthesize beingDeleted = _isBeingDeleted;

@synthesize selected = _selected;
@synthesize draggingSource = _draggingSource;

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

#pragma mark -
#pragma mark OFSDocumentStoreItem subclass

- (void)_invalidate;
{
    if (_hasRegisteredAsFilePresenter) {
        _hasRegisteredAsFilePresenter = NO;
        [NSFileCoordinator removeFilePresenter:self];
    }
    
    [super _invalidate];
}

#pragma mark -
#pragma mark OFSDocumentStoreItem protocol

- (NSString *)name;
{
    return self.editingName;
}

@synthesize date = _date;
- (void)setDate:(NSDate *)date;
{
    OBPRECONDITION([NSThread isMainThread]); // Ensure we are only firing KVO on the main thread
    OBPRECONDITION(date);
    
    if (OFISEQUAL(_date, date))
        return;
    
    [_date release];
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

#pragma mark -
#pragma mark NSFilePresenter protocol

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

- (void)accommodatePresentedItemDeletionWithCompletionHandler:(void (^)(NSError *errorOrNil))completionHandler;
{
    OBPRECONDITION(_isBeingDeleted == NO);
    _isBeingDeleted = YES;
    
    if (completionHandler)
        completionHandler(nil);
}

- (void)presentedItemDidMoveToURL:(NSURL *)newURL;
{
    OBPRECONDITION([NSOperationQueue currentQueue] == _presentedItemOperationQueue);
    OBPRECONDITION(newURL);
    OBPRECONDITION([newURL isFileURL]);

    // See -presentedItemURL's documentation about it being called from various threads. This method should only be called from our presenter queue.
    @synchronized(self) {
        if (OFISEQUAL(_filePresenterURL, newURL))
            return;
        NSURL *oldURL = [[_filePresenterURL copy] autorelease];
        NSDate *oldDate = [[_date copy] autorelease];
        
        // This can get called from various threads
        [_filePresenterURL release];
        _filePresenterURL = [newURL copy];
        
        NSNumber *isDirectory = nil;
        NSError *resourceError = nil;
        if (![_filePresenterURL getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:&resourceError]) {
            NSLog(@"Error getting directory key for %@: %@", _filePresenterURL, [resourceError toPropertyList]);
        }
        [_fileType release];
        _fileType = [OFUTIForFileExtensionPreferringNative([_filePresenterURL pathExtension], [isDirectory boolValue]) copy];
        OBASSERT(_fileType);
        
        // When we get deleted via iCloud, our on-disk representation will get moved into dead zone. Don't present that to the user briefly.
        if (_isBeingDeleted) {
            // Try to make sure we actually are getting moved to the ubd dead zone
            OBASSERT([[newURL absoluteString] containsString:@"/.ubd/"]);
            OBASSERT([[newURL absoluteString] containsString:@"/dead-"]);
        } else {
            // Update KVO on the main thread.
            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                // On iOS, this lets the document preview be moved.
                [self.documentStore _fileWithURL:oldURL andDate:oldDate didMoveToURL:newURL];
                
                [self willChangeValueForKey:OFSDocumentStoreFileItemDisplayedFileURLBinding];
                [_displayedFileURL release];
                _displayedFileURL = [newURL copy];
                [self didChangeValueForKey:OFSDocumentStoreFileItemDisplayedFileURLBinding];
            }];
        }
    }
}

// This gets called for local coordinated writes and for unsolicited incoming edits from iCloud. From the header, "Your NSFileProvider may be sent this message without being sent -relinquishPresentedItemToWriter: first. Make your application do the best it can in that case."
- (void)presentedItemDidChange;
{
    OBPRECONDITION([NSOperationQueue currentQueue] == _presentedItemOperationQueue);
    [self _queueContentsChanged];
}

- (void)presentedItemDidGainVersion:(NSFileVersion *)version;
{
    OBPRECONDITION([NSOperationQueue currentQueue] == _presentedItemOperationQueue);

    DEBUG_VERSIONS(@"%@ gained version %@", [self.fileURL absoluteString], version);
}

- (void)presentedItemDidLoseVersion:(NSFileVersion *)version;
{
    OBPRECONDITION([NSOperationQueue currentQueue] == _presentedItemOperationQueue);

    DEBUG_VERSIONS(@"%@ lost version %@", [self.fileURL absoluteString], version);
}

- (void)presentedItemDidResolveConflictVersion:(NSFileVersion *)version;
{
    OBPRECONDITION([NSOperationQueue currentQueue] == _presentedItemOperationQueue);

    DEBUG_VERSIONS(@"%@ did resolve conflict version %@", [self.fileURL absoluteString], version);
}

#pragma mark -
#pragma mark NSCopying

// So we can be a dictionary key
- (id)copyWithZone:(NSZone *)zone;
{
    return [self retain];
}

#pragma mark -
#pragma mark Debugging

- (NSString *)shortDescription;
{
    return [NSString stringWithFormat:@"<%@:%p '%@' date:%f>", NSStringFromClass([self class]), self, self.presentedItemURL, [self.date timeIntervalSinceReferenceDate]];
}

#pragma mark -
#pragma mark Internal

static void _updateFlag(OFSDocumentStoreFileItem *self, BOOL *ioValue, NSString *bindingKey,
                        NSMetadataItem *metadataItem, NSString *metadataAttribute, BOOL defaultValue)
{
    OBPRECONDITION([NSThread isMainThread]); // Only fire KVO on the main thread
    
    NSNumber *metadataValue = [metadataItem valueForAttribute:metadataAttribute];
    BOOL metadataFlag = metadataValue ? [metadataValue boolValue] : defaultValue;
    if (*ioValue == metadataFlag)
        return;
    
    [self willChangeValueForKey:bindingKey];
    *ioValue = metadataFlag;
    [self didChangeValueForKey:bindingKey];
}
#define UPDATE_FLAG(ivar, keySuffix) _updateFlag(self, &ivar, OFSDocumentStoreItem ## keySuffix ## Binding, metdataItem, NSMetadataUbiquitousItem ## keySuffix ## Key, kOFSDocumentStoreFileItemDefault_ ## keySuffix)

static void _updatePercent(OFSDocumentStoreFileItem *self, double *ioValue, NSString *bindingKey,
                        NSMetadataItem *metadataItem, NSString *metadataAttribute, double defaultValue)
{
    OBPRECONDITION([NSThread isMainThread]); // Only fire KVO on the main thread

    NSNumber *metadataValue = [metadataItem valueForAttribute:metadataAttribute];
    double metadataPercent = metadataValue ? [metadataValue doubleValue] : defaultValue;
    if (*ioValue == metadataPercent)
        return;
    
    [self willChangeValueForKey:bindingKey];
    *ioValue = metadataPercent;
    [self didChangeValueForKey:bindingKey];
}
#define UPDATE_PERCENT(ivar, keySuffix) _updatePercent(self, &ivar, OFSDocumentStoreItem ## keySuffix ## Binding, metdataItem, NSMetadataUbiquitousItem ## keySuffix ## Key, kOFSDocumentStoreFileItemDefault_ ## keySuffix)


- (void)_updateWithMetadataItem:(NSMetadataItem *)metdataItem;
{
    OBPRECONDITION([NSThread isMainThread]); // Fire KVO from the main thread
//  OBPRECONDITION([self.scope isUbiquitous]); // this is an expensive call and the only place this is called from - [OFSDocumentStore scanItemsWithCompletionHandler:] - already checks the scope's isUbiquitous, so commenting out
    
    NSDate *date = [metdataItem valueForAttribute:NSMetadataItemFSContentChangeDateKey];
    if (!date) {
        OBASSERT_NOT_REACHED("No date on metadata item");
        date = [NSDate date];
    }
    self.date = date;
    
    BOOL wasDownloaded = _isDownloaded;

    UPDATE_FLAG(_hasUnresolvedConflicts, HasUnresolvedConflicts);
    UPDATE_FLAG(_isDownloaded, IsDownloaded);
    UPDATE_FLAG(_isDownloading, IsDownloading);
    UPDATE_FLAG(_isUploaded, IsUploaded);
    UPDATE_FLAG(_isUploading, IsUploading);

    UPDATE_PERCENT(_percentUploaded, PercentUploaded);
    UPDATE_PERCENT(_percentDownloaded, PercentDownloaded);

    BOOL nowDownloaded = _isDownloaded;
    
    if (!wasDownloaded && nowDownloaded) {
        // The downloading process sends -presentedItemDidChange a couple times during downloading, but not right at the end, sadly.
        [self _queueContentsChanged];

        // The file type and modification date stored in this file item may not have changed (since undownloaded file items know those). So, -_queueContentsChanged may end up posting no notification. Rather than forcing it to do so in this case, we have a specific notification for a download finishing.
        NSDictionary *userInfo = [NSDictionary dictionaryWithObject:self forKey:OFSDocumentStoreFileItemInfoKey];
        [[NSNotificationCenter defaultCenter] postNotificationName:OFSDocumentStoreFileItemFinishedDownloadingNotification object:self.documentStore userInfo:userInfo];
    }
}

- (void)_suspendFilePresenter;
{
    OBPRECONDITION(_hasRegisteredAsFilePresenter == YES);
    
    if (_hasRegisteredAsFilePresenter) {
        [NSFileCoordinator removeFilePresenter:self];
        _hasRegisteredAsFilePresenter = NO;
    }
}

- (void)_resumeFilePresenter;
{
    // Can't assert this since we might have a mix of re-activated items and new items.
    //OBPRECONDITION(_hasRegisteredAsFilePresenter == NO);
    
    if (!_hasRegisteredAsFilePresenter) {
        [NSFileCoordinator addFilePresenter:self];
        _hasRegisteredAsFilePresenter = YES;

        // The document store should only call this after a scan has finished that would have updated our date, so we don't call -_queueContentsChanged here.
    }
}

#pragma mark -
#pragma mark Private

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
                NSDictionary *userInfo = [NSDictionary dictionaryWithObject:self forKey:OFSDocumentStoreFileItemInfoKey];
                [[NSNotificationCenter defaultCenter] postNotificationName:OFSDocumentStoreFileItemContentsChangedNotification object:self.documentStore userInfo:userInfo];
            }];
        }];
    }];
}

// Asynchronously refreshes the date and sends a OFSDocumentStoreFileItemContentsChangedNotification notification
- (void)_queueContentsChanged;
{
    // We get sent -presentedItemDidChange even after -accommodatePresentedItemDeletionWithCompletionHandler:.
    // We don't need to not any content changes and if we try to get our modification date, we'll be unable to read the attributes of our file in the dead zone anyway.
    if (_isBeingDeleted)
        return;
    
    NSURL *fileURL = [[self.fileURL retain] autorelease];
    
    [self.documentStore performAsynchronousFileAccessUsingBlock:^{
        
#if DEBUG_VERSIONS_ENABLED
        DEBUG_VERSIONS(@"Refreshing date for %@", [self shortDescription]);
        [self _logVersions];
#endif                   
        
        NSFileCoordinator *coordinator = [[[NSFileCoordinator alloc] initWithFilePresenter:self] autorelease];
        
        __block NSDate *modificationDate = nil;
        __block NSString *fileType = nil;
        
        NSError *error = nil;
        
        [coordinator coordinateReadingItemAtURL:fileURL options:0 error:&error byAccessor:^(NSURL *newURL){
            // We use the file modification date rather than a date embedded inside the file since the latter would cause duplicated documents to not sort to the front as a new document (until you modified them, at which point they'd go flying to the beginning).
            NSError *attributesError = nil;
            NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:[[newURL absoluteURL] path]  error:&attributesError];
            if (!attributes)
                NSLog(@"Error getting attributes for %@ -- %@", [newURL absoluteString], [attributesError toPropertyList]);
            else
                modificationDate = [[attributes fileModificationDate] retain];
            if (!modificationDate)
                modificationDate = [[NSDate date] retain]; // Default to now if we can't get the attributes or they are bogus for some reason.
            
            // Some file types may have the same extension but different UTIs based on whether they are a directory or not.
            BOOL isDirectory = [[attributes objectForKey:NSFileType] isEqual:NSFileTypeDirectory];
            
            fileType = [OFUTIForFileExtensionPreferringNative([newURL pathExtension], isDirectory) retain];
        }];
        
        if (!modificationDate) {
            NSLog(@"Error performing coordinated read of modification date of %@: %@", [fileURL absoluteString], [error toPropertyList]);
            modificationDate = [[NSDate date] retain]; // Default to now if we can't get the attributes or they are bogus for some reason.
        }
        
        OBASSERT(![NSThread isMainThread]);
        
        _notifyDateAndFileType(self, [modificationDate autorelease], [fileType autorelease]);
    }];
}

#if DEBUG_VERSIONS_ENABLED
- (void)_logVersions;
{
    DEBUG_VERSIONS(@"File item %@", [self.fileURL absoluteURL]);
    NSFileVersion *version = [NSFileVersion currentVersionOfItemAtURL:self.fileURL];
    DEBUG_VERSIONS(@"current %@ -- %@ on %@, conflict:%d resolved:%d ", version, version.localizedNameOfSavingComputer, version.modificationDate, version.conflict, version.resolved);
    for (NSFileVersion *version in [NSFileVersion otherVersionsOfItemAtURL:self.fileURL])
        DEBUG_VERSIONS(@"other %@ -- %@ on %@, conflict:%d resolved:%d ", version, version.localizedNameOfSavingComputer, version.modificationDate, version.conflict, version.resolved);
}
#endif

@end

#endif // OFS_DOCUMENT_STORE_SUPPORTED
