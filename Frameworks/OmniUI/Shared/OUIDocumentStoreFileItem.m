// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIDocumentStoreFileItem.h>

#import <OmniFileStore/OFSFileManager.h>

#import "OUIDocumentStoreItem-Internal.h"
#import "OUIDocumentStoreFileItem-Internal.h"
#import "OUIDocumentStore-Internal.h"

RCS_ID("$Id$");

// OUIDocumentStoreFileItem
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


NSString * const OUIDocumentStoreFileItemFilePresenterURLBinding = @"filePresenterURL";
NSString * const OUIDocumentStoreFileItemSelectedBinding = @"selected";

static NSString * const OUIDocumentStoreFileItemDisplayedFileURLBinding = @"displayedFileURL";

@interface OUIDocumentStoreFileItem ()
- (void)_queueContentsChanged;
#if DEBUG_VERSIONS_ENABLED
- (void)_logVersions;
#endif
@end

#define kOUIDocumentStoreFileItemDefault_HasUnresolvedConflicts (NO)
#define kOUIDocumentStoreFileItemDefault_IsDownloaded (YES)
#define kOUIDocumentStoreFileItemDefault_IsDownloading (NO)
#define kOUIDocumentStoreFileItemDefault_IsUploaded (YES)
#define kOUIDocumentStoreFileItemDefault_IsUploading (NO)
#define kOUIDocumentStoreFileItemDefault_PercentDownloaded (100)
#define kOUIDocumentStoreFileItemDefault_PercentUploaded (100)

@implementation OUIDocumentStoreFileItem
{
    NSURL *_filePresenterURL; // NSFilePresenter needs to get/set this on multiple threads
    NSURL *_displayedFileURL; // A mirrored copy of _fileURL that is only changed on the main thread to fire KVO for the name key.
    
    NSDate *_date;
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
}

+ (void)initialize;
{
    OBINITIALIZE;
    
    OBASSERT_NOT_IMPLEMENTED(self, initWithURL:); // -initWithFileURL:
    OBASSERT_NOT_IMPLEMENTED(self, displayNameForURL:); // Moved to -name and -editingName
    OBASSERT_NOT_IMPLEMENTED(self, editNameForURL:);
}

- initWithDocumentStore:(OUIDocumentStore *)documentStore fileURL:(NSURL *)fileURL date:(NSDate *)date;
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
    
    _presentedItemOperationQueue = [[NSOperationQueue alloc] init];
    [_presentedItemOperationQueue setName:[NSString stringWithFormat:@"OUIDocumentStoreFileItem presenter queue -- %@", OBShortObjectDescription(self)]];
    [_presentedItemOperationQueue setMaxConcurrentOperationCount:1];
    
    // NOTE: This retains us, so we cannot wait until -dealloc to do -removeFilePresenter:!
    _hasRegisteredAsFilePresenter = YES;
    [NSFileCoordinator addFilePresenter:self];
    
    // Reasonable values for local documents that will never get sent -_updateWithMetadataItem: 
    _hasUnresolvedConflicts = kOUIDocumentStoreFileItemDefault_HasUnresolvedConflicts;
    _isDownloaded = kOUIDocumentStoreFileItemDefault_IsDownloaded;
    _isDownloading = kOUIDocumentStoreFileItemDefault_IsDownloading;
    _isUploaded = kOUIDocumentStoreFileItemDefault_IsUploaded;
    _isUploading = kOUIDocumentStoreFileItemDefault_IsUploading;
    _percentDownloaded = kOUIDocumentStoreFileItemDefault_PercentDownloaded;
    _percentUploaded = kOUIDocumentStoreFileItemDefault_PercentUploaded;

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

- (OUIDocumentStoreScope)scope;
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
    return [NSSet setWithObjects:OUIDocumentStoreFileItemDisplayedFileURLBinding, nil];
}

@synthesize selected = _selected;
@synthesize draggingSource = _draggingSource;

- (NSComparisonResult)compare:(OUIDocumentStoreFileItem *)otherItem;
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
    
    OFSFileManagerSplitNameAndCounter(self.name, &name1, &counter1);
    OFSFileManagerSplitNameAndCounter(otherItem.name, &name2, &counter2);
    
    

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
#pragma mark OUIDocumentStoreItem subclass

- (void)_invalidate;
{
    OBPRECONDITION(_hasRegisteredAsFilePresenter);
    
    if (_hasRegisteredAsFilePresenter) {
        _hasRegisteredAsFilePresenter = NO;
        [NSFileCoordinator removeFilePresenter:self];
    }
    
    [super _invalidate];
}

#pragma mark -
#pragma mark OUIDocumentStoreItem protocol

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
    return self.fileURL;
}

- (NSOperationQueue *)presentedItemOperationQueue;
{
    OBPRECONDITION(_presentedItemOperationQueue); // Otherwise NSFileCoordinator may try to enqueue blocks and they'll never get started, yielding mysterious deadlocks.
    return _presentedItemOperationQueue;
}

- (void)presentedItemDidMoveToURL:(NSURL *)newURL;
{
    // See -presentedItemURL's documentation about it being called from various threads. This method should only be called from our presenter queue.
    @synchronized(self) {
        if (OFNOTEQUAL(_filePresenterURL, newURL)) {
            OBPRECONDITION(newURL);
            OBPRECONDITION([newURL isFileURL]);

            // This can get called from various threads
            [_filePresenterURL release];
            _filePresenterURL = [newURL copy];
            
            // Update KVO on the main thread.
            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                [self willChangeValueForKey:OUIDocumentStoreFileItemDisplayedFileURLBinding];
                [_displayedFileURL release];
                _displayedFileURL = [newURL copy];
                [self didChangeValueForKey:OUIDocumentStoreFileItemDisplayedFileURLBinding];
            }];
        }
    }
}

// This gets called for local coordinated writes and for unsolicited incoming edits from iCloud. From the header, "Your NSFileProvider may be sent this message without being sent -relinquishPresentedItemToWriter: first. Make your application do the best it can in that case."
- (void)presentedItemDidChange;
{
    [self _queueContentsChanged];
}

- (void)presentedItemDidGainVersion:(NSFileVersion *)version;
{
    DEBUG_VERSIONS(@"%@ gained version %@", [self.fileURL absoluteString], version);
}

- (void)presentedItemDidLoseVersion:(NSFileVersion *)version;
{
    DEBUG_VERSIONS(@"%@ lost version %@", [self.fileURL absoluteString], version);
}

- (void)presentedItemDidResolveConflictVersion:(NSFileVersion *)version;
{
    DEBUG_VERSIONS(@"%@ did resolve conflict version %@", [self.fileURL absoluteString], version);
}

#pragma mark -
#pragma mark Debugging

- (NSString *)shortDescription;
{
    return [NSString stringWithFormat:@"<%@:%p '%@' date:%f>", NSStringFromClass([self class]), self, self.presentedItemURL, [self.date timeIntervalSinceReferenceDate]];
}

#pragma mark -
#pragma mark Internal

static void _updateFlag(OUIDocumentStoreFileItem *self, BOOL *ioValue, NSString *bindingKey,
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
#define UPDATE_FLAG(ivar, keySuffix) _updateFlag(self, &ivar, OUIDocumentStoreItem ## keySuffix ## Binding, metdataItem, NSMetadataUbiquitousItem ## keySuffix ## Key, kOUIDocumentStoreFileItemDefault_ ## keySuffix)

static void _updatePercent(OUIDocumentStoreFileItem *self, double *ioValue, NSString *bindingKey,
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
#define UPDATE_PERCENT(ivar, keySuffix) _updatePercent(self, &ivar, OUIDocumentStoreItem ## keySuffix ## Binding, metdataItem, NSMetadataUbiquitousItem ## keySuffix ## Key, kOUIDocumentStoreFileItemDefault_ ## keySuffix)


- (void)_updateWithMetadataItem:(NSMetadataItem *)metdataItem;
{
    OBPRECONDITION([NSThread isMainThread]); // Fire KVO from the main thread
    OBPRECONDITION(self.scope == OUIDocumentStoreScopeUbiquitous);
    
    NSDate *date = [metdataItem valueForAttribute:NSMetadataItemFSContentChangeDateKey];
    if (!date) {
        OBASSERT_NOT_REACHED("No date on metadata item");
        date = [NSDate date];
    }
    self.date = date;
    
    UPDATE_FLAG(_hasUnresolvedConflicts, HasUnresolvedConflicts);
    UPDATE_FLAG(_isDownloaded, IsDownloaded);
    UPDATE_FLAG(_isDownloading, IsDownloading);
    UPDATE_FLAG(_isUploaded, IsUploaded);
    UPDATE_FLAG(_isUploading, IsUploading);

    UPDATE_PERCENT(_percentUploaded, PercentUploaded);
    UPDATE_PERCENT(_percentDownloaded, PercentDownloaded);
}

#pragma mark -
#pragma mark Private

// Asynchronously refreshes the date and sends a -_fileItemContentsChanged: notification
- (void)_queueContentsChanged;
{
    NSURL *fileURL = [[self.fileURL retain] autorelease];
    
    [self.documentStore performAsynchronousFileAccessUsingBlock:^{
        
#if DEBUG_VERSIONS_ENABLED
        DEBUG_VERSIONS(@"Refreshing date for %@", [self shortDescription]);
        [self _logVersions];
#endif                   
        
        NSFileCoordinator *coordinator = [[[NSFileCoordinator alloc] initWithFilePresenter:self] autorelease];
        
        __block NSDate *modificationDate = nil;
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
        }];
        
        if (!modificationDate) {
            NSLog(@"Error performing coordinated read of modification date of %@: %@", [fileURL absoluteString], [error toPropertyList]);
            modificationDate = [[NSDate date] retain]; // Default to now if we can't get the attributes or they are bogus for some reason.
        }
        
        OBASSERT(![NSThread isMainThread]);
        
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            self.date = [modificationDate autorelease];
            [self.documentStore _fileItemContentsChanged:self];
        }];
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
