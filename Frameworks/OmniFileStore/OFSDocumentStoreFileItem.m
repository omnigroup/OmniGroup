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

#if 0 && defined(DEBUG)
    #define DEBUG_FILE_ITEM_ENABLED 1
    #define DEBUG_FILE_ITEM(format, ...) NSLog(@"FILE ITEM %@: " format, [self shortDescription], ## __VA_ARGS__)
#else
    #define DEBUG_FILE_ITEM(format, ...)
#endif

NSString * const OFSDocumentStoreFileItemFilePresenterURLBinding = @"filePresenterURL";
NSString * const OFSDocumentStoreFileItemSelectedBinding = @"selected";
NSString * const OFSDocumentStoreFileItemIsUbiquitousBinding = @"isUbiquitous";
NSString * const OFSDocumentStoreFileItemDownloadRequestedBinding = @"downloadRequested";

static NSString * const OFSDocumentStoreFileItemDisplayedFileURLBinding = @"displayedFileURL";

@interface OFSDocumentStoreFileItem ()
@property(copy,nonatomic) NSString *fileType;
@property(nonatomic) BOOL downloadRequested;
- (void)_queueContentsChanged;
@end

#define kOFSDocumentStoreFileItemDefault_IsUbiquitous (NO)
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
    
    BOOL _isUbiquitous;
    BOOL _hasUnresolvedConflicts;
    BOOL _isDownloaded;
    BOOL _isDownloading;
    BOOL _isUploaded;
    BOOL _isUploading;
    double _percentDownloaded;
    double _percentUploaded;
    
    BOOL _downloadRequested;
    
    BOOL _hasRegisteredAsFilePresenter;
    NSOperationQueue *_presentedItemOperationQueue;

    BOOL _selected;
    BOOL _draggingSource;
    
    // Keep track of edits that have happened while we have relinquished for a writer. These can be randomly ordered in bad ways (for example, we can be told of a 'did change' right before a 'delete'). Radar 10879451.
    struct {
        unsigned relinquishToWriter:1;
        unsigned deleted:1;
        unsigned changed:1;
        
        unsigned moved:1;
        NSURL *originalURL; // nil or the old fileURL if we are being moved
        NSDate *originalDate; // likewise, for the date.
    } _edits;
}

+ (void)initialize;
{
    OBINITIALIZE;
    
    OBASSERT_NOT_IMPLEMENTED(self, initWithURL:); // -initWithFileURL:
    OBASSERT_NOT_IMPLEMENTED(self, displayNameForURL:); // Moved to -name and -editingName
    OBASSERT_NOT_IMPLEMENTED(self, editNameForURL:);

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
    
    // Reasonable values for local documents that will never get sent -_updateUbiquitousItemWithMetadataItem: 
    _isUbiquitous = kOFSDocumentStoreFileItemDefault_IsUbiquitous;
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

    return [[self class] editingNameForFileURL:_displayedFileURL fileType:self.fileType];
}

+ (NSSet *)keyPathsForValuesAffectingName;
{
    return [NSSet setWithObjects:OFSDocumentStoreFileItemDisplayedFileURLBinding, nil];
}

- (BOOL)isBeingDeleted;
{
    return _edits.deleted;
}

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
        DEBUG_FILE_ITEM(@"Removed as file presenter");
        
        _hasRegisteredAsFilePresenter = NO;
        [NSFileCoordinator removeFilePresenter:self];
    }
    
    [super _invalidate];
}

#pragma mark -
#pragma mark OFSDocumentStoreItem protocol

- (NSString *)name;
{
    return [[self class] displayNameForFileURL:self.fileURL fileType:self.fileType];
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

@synthesize isUbiquitous = _isUbiquitous;
@synthesize hasUnresolvedConflicts = _hasUnresolvedConflicts;
@synthesize isDownloaded = _isDownloaded;
@synthesize isDownloading = _isDownloading;
@synthesize isUploaded = _isUploaded;
@synthesize isUploading = _isUploading;
@synthesize percentDownloaded = _percentDownloaded;
@synthesize percentUploaded = _percentUploaded;

- (BOOL)requestDownload:(NSError **)outError;
{
    OBPRECONDITION([NSThread isMainThread]); // Only want to fire KVO on the main thread
    
    self.downloadRequested = YES;

    return [[NSFileManager defaultManager] startDownloadingUbiquitousItemAtURL:self.fileURL error:outError];
}

@synthesize downloadRequested = _downloadRequested;

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

// Writer notifications can come in random/bad order (for example a 'did change' when the file has really already been deleted and we are about to get an 'accomodate').
- (void)relinquishPresentedItemToWriter:(void (^)(void (^reacquirer)(void)))writer;
{
    OBPRECONDITION(_edits.relinquishToWriter == NO);
    
    DEBUG_FILE_ITEM(@"-relinquishPresentedItemToWriter:");
    _edits.relinquishToWriter = YES;
    
    writer(^{
        DEBUG_FILE_ITEM(@"Reacquiring after writer: deleted:%d changed:%d moved:%d", _edits.deleted, _edits.changed, _edits.moved);
        _edits.relinquishToWriter = NO;
        
        if (_edits.changed || _edits.moved) {
            if (_edits.deleted) {
                // Ignore these edits -- our file has sailed into the west.
                _edits.changed = NO;
                _edits.moved = NO;
            } else {                
                if (_edits.moved) {
                    _edits.moved = NO;
                    @synchronized(self) {
                        OBASSERT(_edits.originalURL != nil);
                        OBASSERT(_edits.originalDate != nil);
                        NSURL *oldURL = [_edits.originalURL autorelease];
                        _edits.originalURL = nil;
                        NSDate *oldDate = [_edits.originalDate autorelease];
                        _edits.originalDate = nil;
                        
                        [self _synchronized_processItemDidMoveFromURL:oldURL date:oldDate];
                    }
                }
                
                if (_edits.changed) {
                    _edits.changed = NO;
                    [self _queueContentsChanged];
                }
            }
        }
    });
}

- (void)accommodatePresentedItemDeletionWithCompletionHandler:(void (^)(NSError *errorOrNil))completionHandler;
{
    OBPRECONDITION(_edits.relinquishToWriter == YES);
    OBPRECONDITION(_edits.deleted == NO);

    DEBUG_FILE_ITEM(@"accommodatePresentedItemDeletionWithCompletionHandler:");
    
    _edits.deleted = YES;
    
    if (completionHandler)
        completionHandler(nil);
}

- (void)presentedItemDidMoveToURL:(NSURL *)newURL;
{
    OBPRECONDITION([NSOperationQueue currentQueue] == _presentedItemOperationQueue);
    OBPRECONDITION(newURL);
    OBPRECONDITION([newURL isFileURL]);

    DEBUG_FILE_ITEM(@"presentedItemDidMoveToURL: %@", newURL);

    // See -presentedItemURL's documentation about it being called from various threads. This method should only be called from our presenter queue.
    @synchronized(self) {
        if (OFISEQUAL(_filePresenterURL, newURL))
            return;
        NSURL *oldURL = [[_filePresenterURL copy] autorelease];
        NSDate *oldDate = [[_date copy] autorelease];
        
        // This can get called from various threads
        [_filePresenterURL release];
        _filePresenterURL = [newURL copy];
        
        OBASSERT(_edits.originalURL == nil);
        OBASSERT(_edits.originalDate == nil);

        if (_edits.relinquishToWriter) {
            DEBUG_FILE_ITEM(@"  Inside writer; delay handling move");

            // Defer the rest of the update until we reacquire
            _edits.moved = YES;
            _edits.originalURL = [oldURL copy];
            _edits.originalDate = [oldDate copy];
        } else {
            [self _synchronized_processItemDidMoveFromURL:oldURL date:oldDate];
        }
    }
}

// This gets called for local coordinated writes and for unsolicited incoming edits from iCloud. From the header, "Your NSFileProvider may be sent this message without being sent -relinquishPresentedItemToWriter: first. Make your application do the best it can in that case."
- (void)presentedItemDidChange;
{
    OBPRECONDITION([NSOperationQueue currentQueue] == _presentedItemOperationQueue);

    DEBUG_FILE_ITEM(@"presentedItemDidChange");

    if (_edits.relinquishToWriter) {
        DEBUG_FILE_ITEM(@"  Inside writer; delay handling change");
        _edits.changed = YES; // Defer until we reacquire
    } else
        [self _queueContentsChanged];
}

- (void)presentedItemDidGainVersion:(NSFileVersion *)version;
{
    OBPRECONDITION([NSOperationQueue currentQueue] == _presentedItemOperationQueue);

    DEBUG_VERSIONS(@"%@ gained version %@", [self.fileURL absoluteString], version);
    
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        [self.documentStore _fileItem:self didGainVersion:version];
    }];
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
    return [NSString stringWithFormat:@"<%@:%p '%@' date:%@>", NSStringFromClass([self class]), self, self.presentedItemURL, [self.date xmlString]];
}

#pragma mark -
#pragma mark Internal

static void _updateFlag(OFSDocumentStoreFileItem *self, BOOL *ioValue, NSString *bindingKey, BOOL value)
{
    OBPRECONDITION([NSThread isMainThread]); // Only fire KVO on the main thread

    if (*ioValue == value)
        return;
    
    DEBUG_FILE_ITEM("  Setting %@ to %d", bindingKey, value);
    [self willChangeValueForKey:bindingKey];
    *ioValue = value;
    [self didChangeValueForKey:bindingKey];
}

static void _updateFlagFromAttributes(OFSDocumentStoreFileItem *self, BOOL *ioValue, NSString *bindingKey, NSDictionary *attributeValues, NSString *attributeKey, BOOL defaultValue)
{
    OBPRECONDITION([NSThread isMainThread]); // Only fire KVO on the main thread
    
    BOOL value;
    NSNumber *attributeValue = [attributeValues objectForKey:attributeKey];
    if (!attributeValue) {
        OBASSERT(attributeValues == nil); // OK if we don't have a metadata item at all
        value = defaultValue;
    } else {
        value = [attributeValue boolValue];
    }
    
    _updateFlag(self, ioValue, bindingKey, value);
}

static void _updatePercent(OFSDocumentStoreFileItem *self, double *ioValue, NSString *bindingKey, double value)
{
    OBPRECONDITION([NSThread isMainThread]); // Only fire KVO on the main thread
    
    if (*ioValue == value)
        return;
    
    DEBUG_FILE_ITEM("  Setting %@ to %f", bindingKey, value);
    [self willChangeValueForKey:bindingKey];
    *ioValue = value;
    [self didChangeValueForKey:bindingKey];
}

static void _updatePercentFromAttributes(OFSDocumentStoreFileItem *self, double *ioValue, NSString *bindingKey, NSDictionary *attributeValues, NSString *attributeKey, double defaultValue)
{
    double value;
    NSNumber *attributeValue = [attributeValues objectForKey:attributeKey];
    if (!attributeValue) {
        OBASSERT_NOT_REACHED("Missing attribute value");
        value = defaultValue;
    } else {
        value = [attributeValue doubleValue];
    }
    
    _updatePercent(self, ioValue, bindingKey, value);
}

#define UPDATE_METADATA_FLAG(ivar, keySuffix) _updateFlagFromAttributes(self, &ivar, OFSDocumentStoreItem ## keySuffix ## Binding, attributeValues, NSMetadataUbiquitousItem ## keySuffix ## Key, kOFSDocumentStoreFileItemDefault_ ## keySuffix)
#define UPDATE_METADATA_PERCENT(ivar, keySuffix) _updatePercentFromAttributes(self, &ivar, OFSDocumentStoreItem ## keySuffix ## Binding, attributeValues, NSMetadataUbiquitousItem ## keySuffix ## Key, kOFSDocumentStoreFileItemDefault_ ## keySuffix)

static void _postFinishedDownloadingIfNeeded(OFSDocumentStoreFileItem *self, BOOL wasDownloaded)
{
    OBPRECONDITION([NSThread isMainThread]);
    
    BOOL nowDownloaded = self->_isDownloaded;
    
    if (!wasDownloaded && nowDownloaded) {
        self.downloadRequested = NO;
        
        // The downloading process sends -presentedItemDidChange a couple times during downloading, but not right at the end, sadly.
        [self _queueContentsChanged];
        
        // The file type and modification date stored in this file item may not have changed (since undownloaded file items know those). So, -_queueContentsChanged may end up posting no notification. Rather than forcing it to do so in this case, we have a specific notification for a download finishing.
        NSDictionary *userInfo = [NSDictionary dictionaryWithObject:self forKey:OFSDocumentStoreFileItemInfoKey];
        [[NSNotificationCenter defaultCenter] postNotificationName:OFSDocumentStoreFileItemFinishedDownloadingNotification object:self.documentStore userInfo:userInfo];
    }
}

#define UPDATE_LOCAL_FLAG(ivar, keySuffix) _updateFlag(self, &ivar, OFSDocumentStoreItem ## keySuffix ## Binding, kOFSDocumentStoreFileItemDefault_ ## keySuffix)
#define UPDATE_LOCAL_PERCENT(ivar, keySuffix) _updatePercent(self, &ivar, OFSDocumentStoreItem ## keySuffix ## Binding, kOFSDocumentStoreFileItemDefault_ ## keySuffix)


- (void)_updateUbiquitousItemWithMetadataItem:(NSMetadataItem *)metadataItem modificationDate:(NSDate *)modificationDate;
{
    OBPRECONDITION([NSThread isMainThread]); // Fire KVO from the main thread
//  OBPRECONDITION([self.scope isUbiquitous]); // this is an expensive call and the only place this is called from - [OFSDocumentStore scanItemsWithCompletionHandler:] - already checks the scope's isUbiquitous, so commenting out
    
    DEBUG_FILE_ITEM("Updating metadata: %@", metadataItem);
    
    static NSArray *MetadataAttributeKeys = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        MetadataAttributeKeys = [[NSArray alloc] initWithObjects:NSMetadataItemFSContentChangeDateKey, NSMetadataUbiquitousItemHasUnresolvedConflictsKey, NSMetadataUbiquitousItemIsDownloadedKey, NSMetadataUbiquitousItemIsDownloadingKey, NSMetadataUbiquitousItemIsUploadedKey, NSMetadataUbiquitousItemIsUploadingKey, NSMetadataUbiquitousItemPercentUploadedKey, NSMetadataUbiquitousItemPercentDownloadedKey, nil];
    });
    
    // In the past, some NSMetadataItem attribute keys weren't reliable (updates might be missed that would be shown by the NSURL variants). But, getting the NSURL variants on an iCloud document does IPC to the ubiquity daemon and is very slow. Thankfully these work now, but if we are ever tempted to switch to the NSURL variants again, be wary of performance.
    NSDictionary *attributeValues = [metadataItem valuesForAttributes:MetadataAttributeKeys];

    // Use the metadata item's date if we have it. Otherwise, this might be a newly created/duplicated item that we know is in a ubiquitous container, but that we haven't received a metadata item for yet (so we'll use the date from the file system).
    if (metadataItem) {
        modificationDate = [attributeValues objectForKey:NSMetadataItemFSContentChangeDateKey];
        OBASSERT(modificationDate);
    } else {
        OBASSERT(modificationDate);
    }
    if (!modificationDate)
        modificationDate = [NSDate date];

    self.date = modificationDate;
    
    BOOL wasDownloaded = _isDownloaded;
    
    _updateFlag(self, &_isUbiquitous, OFSDocumentStoreFileItemIsUbiquitousBinding, YES);

    UPDATE_METADATA_FLAG(_hasUnresolvedConflicts, HasUnresolvedConflicts);
    UPDATE_METADATA_FLAG(_isDownloaded, IsDownloaded);
    UPDATE_METADATA_FLAG(_isDownloading, IsDownloading);
    UPDATE_METADATA_FLAG(_isUploaded, IsUploaded);
    UPDATE_METADATA_FLAG(_isUploading, IsUploading);

    if (_isUploading) // percent might not be in the attributes otherwise
        UPDATE_METADATA_PERCENT(_percentUploaded, PercentUploaded);
    else
        UPDATE_LOCAL_PERCENT(_percentUploaded, PercentUploaded); // Set the default value

    if (_isDownloading) // percent might not be in the attributes otherwise
        UPDATE_METADATA_PERCENT(_percentDownloaded, PercentDownloaded);
    else
        UPDATE_LOCAL_PERCENT(_percentDownloaded, PercentDownloaded); // Set the default value
        
    _postFinishedDownloadingIfNeeded(self, wasDownloaded);
}

- (void)_updateLocalItemWithModificationDate:(NSDate *)modificationDate;
{
    OBPRECONDITION([NSThread isMainThread]); // Fire KVO from the main thread
    
    self.date = modificationDate;
    
    BOOL wasDownloaded = _isDownloaded;

    _updateFlag(self, &_isUbiquitous, OFSDocumentStoreFileItemIsUbiquitousBinding, NO);

    UPDATE_LOCAL_FLAG(_hasUnresolvedConflicts, HasUnresolvedConflicts);
    UPDATE_LOCAL_FLAG(_isDownloaded, IsDownloaded);
    UPDATE_LOCAL_FLAG(_isDownloading, IsDownloading);
    UPDATE_LOCAL_FLAG(_isUploaded, IsUploaded);
    UPDATE_LOCAL_FLAG(_isUploading, IsUploading);
    
    UPDATE_LOCAL_PERCENT(_percentUploaded, PercentUploaded);
    UPDATE_LOCAL_PERCENT(_percentDownloaded, PercentDownloaded);
    
    _postFinishedDownloadingIfNeeded(self, wasDownloaded);
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
    if (_edits.deleted) {
        DEBUG_FILE_ITEM(@"Deleted: ignoring change");
        return;
    }
    
    DEBUG_FILE_ITEM(@"Queuing contents changed update");

    [self.documentStore performAsynchronousFileAccessUsingBlock:^{
        
#if DEBUG_VERSIONS_ENABLED
        DEBUG_VERSIONS(@"Refreshing date for %@", [self shortDescription]);
        [self _logVersions];
#endif                   
        
        /*
         NOTE: We do NOT use a coordinated read here anymore, though we would like to. If we are getting an incoming iCloud rename, we can end up deadlocking.
         
         First, there is Radar 10879451: Bad and random ordering of NSFilePresenter notifications. This means we can get a lone -presentedItemDidChange before the relinquish-to-writer wrapped presentedItemDidMoveToURL:. But, we have the old URL at this point. Doing a coordinated read on that URL blocks forever (see Radar 11076208: Coordinated reads started in response to -presentedItemDidChange can hang).
         */
                
        NSDate *modificationDate = nil;
        NSString *fileType = nil;
        
        NSError *error = nil;
        
        NSURL *fileURL = [[self.fileURL retain] autorelease];
        
        // We use the file modification date rather than a date embedded inside the file since the latter would cause duplicated documents to not sort to the front as a new document (until you modified them, at which point they'd go flying to the beginning).
        NSError *attributesError = nil;
        NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:[[fileURL absoluteURL] path]  error:&attributesError];
        if (!attributes)
            NSLog(@"Error getting attributes for %@ -- %@", [fileURL absoluteString], [attributesError toPropertyList]);
        else
            modificationDate = [[attributes fileModificationDate] retain];
        if (!modificationDate)
            modificationDate = [[NSDate date] retain]; // Default to now if we can't get the attributes or they are bogus for some reason.
        
        // Some file types may have the same extension but different UTIs based on whether they are a directory or not.
        BOOL isDirectory = [[attributes objectForKey:NSFileType] isEqual:NSFileTypeDirectory];
        
        fileType = [OFUTIForFileExtensionPreferringNative([fileURL pathExtension], [NSNumber numberWithBool:isDirectory]) retain];
        
        if (!modificationDate) {
            NSLog(@"Error performing coordinated read of modification date of %@: %@", [fileURL absoluteString], [error toPropertyList]);
            modificationDate = [[NSDate date] retain]; // Default to now if we can't get the attributes or they are bogus for some reason.
        }
        
        OBASSERT(![NSThread isMainThread]);
        
        _notifyDateAndFileType(self, [modificationDate autorelease], [fileType autorelease]);
    }];
}

- (void)_synchronized_processItemDidMoveFromURL:(NSURL *)oldURL date:(NSDate *)oldDate;
{
    // Called either from -presentedItemDidMoveToURL: if we aren't inside of a writer block, or from the reacquire block in our -relinquishPresentedItemToWriter:. The caller should @synchronized(self) {...} around this since it accesses the _filePresenterURL, which needs to be accessible from the our operation queue and the main queue.
    
    // When we get deleted via iCloud, our on-disk representation will get moved into dead zone. Don't present that to the user briefly. Also, don't try to look at the time stamp on the dead file or poke it with a stick in any fashion.
    if (_edits.deleted) {
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
        [_fileType release];
        _fileType = [OFUTIForFileExtensionPreferringNative([_filePresenterURL pathExtension], isDirectory) copy];
        OBASSERT(_fileType);
        
        // Update KVO on the main thread.
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            // On iOS, this lets the document preview be moved.
            if (![self _hasBeenInvalidated]) {
                [self.documentStore _fileWithURL:oldURL andDate:oldDate didMoveToURL:_filePresenterURL];
                // might not have been invalidated yet...
            } else {
                OBASSERT(probablyInvalid == YES);
            }
            
            [self willChangeValueForKey:OFSDocumentStoreFileItemDisplayedFileURLBinding];
            [_displayedFileURL release];
            _displayedFileURL = [_filePresenterURL copy];
            [self didChangeValueForKey:OFSDocumentStoreFileItemDisplayedFileURLBinding];
        }];
    }
}

#if DEBUG_FILE_ITEM_ENABLED
static void _logMetadataKeyFromURL(NSURL *fileURL, NSString *key)
{
    id value = nil;
    NSError *resourceError = nil;
    if (![fileURL getResourceValue:&value forKey:key error:&resourceError]) {
        NSLog(@"  Error getting key %@ for %@: %@", key, fileURL, [resourceError toPropertyList]);
        return;
    }
    NSLog(@"  %@ = %@", key, value);
}
- (void)_logMetadataFromURL;
{
    NSURL *fileURL = self.fileURL;
    
    NSLog(@"Metadata for %@:", fileURL);
    _logMetadataKeyFromURL(fileURL, NSURLIsUbiquitousItemKey);
    _logMetadataKeyFromURL(fileURL, NSURLUbiquitousItemHasUnresolvedConflictsKey);
    _logMetadataKeyFromURL(fileURL, NSURLUbiquitousItemIsDownloadedKey);
    _logMetadataKeyFromURL(fileURL, NSURLUbiquitousItemIsDownloadingKey);
    _logMetadataKeyFromURL(fileURL, NSURLUbiquitousItemIsUploadedKey);
    _logMetadataKeyFromURL(fileURL, NSURLUbiquitousItemIsUploadingKey);
    _logMetadataKeyFromURL(fileURL, NSURLUbiquitousItemPercentDownloadedKey);
    _logMetadataKeyFromURL(fileURL, NSURLUbiquitousItemPercentUploadedKey);
}
#endif

#if DEBUG_VERSIONS_ENABLED
- (void)_logVersions;
{
    DEBUG_VERSIONS(@"File item %@", [self.fileURL absoluteURL]);
    NSFileVersion *version = [NSFileVersion currentVersionOfItemAtURL:self.fileURL];
    DEBUG_VERSIONS(@"current %@ -- %@ on %@, conflict:%d resolved:%d ", version, version.localizedNameOfSavingComputer, [version.modificationDate xmlString], version.conflict, version.resolved);
    for (NSFileVersion *version in [NSFileVersion otherVersionsOfItemAtURL:self.fileURL])
        DEBUG_VERSIONS(@"other %@ -- %@ on %@, conflict:%d resolved:%d ", version, version.localizedNameOfSavingComputer, [version.modificationDate xmlString], version.conflict, version.resolved);
}
#endif

@end

#endif // OFS_DOCUMENT_STORE_SUPPORTED
