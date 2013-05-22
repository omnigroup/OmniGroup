// Copyright 2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFileExchange/OFXDocumentStoreScope.h>

#import <OmniFileExchange/OFXAgent.h>
#import <OmniFileExchange/OFXErrors.h>
#import <OmniFileExchange/OFXFileMetadata.h>
#import <OmniFileExchange/OFXRegistrationTable.h>
#import <OmniFileExchange/OFXServerAccount.h>
#import <OmniFileStore/OFSDocumentStore.h>
#import <OmniFileStore/OFSDocumentStoreFileItem.h>
#import <OmniFileStore/OFSURL.h>
#import <OmniFoundation/NSSet-OFExtensions.h>
#import <OmniFoundation/OFNetReachability.h>
#import <OmniBase/NSError-OBExtensions.h>

#import <OmniFileStore/OFSDocumentStoreScope-Subclass.h>

#import "OFXAgent-Internal.h"

RCS_ID("$Id$");

@interface OFXDocumentStoreScope () <OFSDocumentStoreConcreteScope>
@end

@implementation OFXDocumentStoreScope
{
    BOOL _hasFinishedInitialScan;
    
    NSString *_identifier;
    NSURL *_documentsURL;
    OFXRegistrationTable *_metadataItemRegistrationTable;

    NSMutableSet *_fileItemsToAutomaticallyDownload;
    
    // In the local directory scope, we can scan the filesystem to check the current state, here we get notified of file items in background. We could assume file stubs exist and scan, but instead we maintain a set of used URLs here.
    NSArray *_usedFileURLs;
}

static unsigned MetadataRegistrationContext;

- initWithSyncAgent:(OFXAgent *)syncAgent account:(OFXServerAccount *)account documentStore:(OFSDocumentStore *)documentStore;
{
    OBPRECONDITION(syncAgent);
    OBPRECONDITION(account);
    
    if (!(self = [super initWithDocumentStore:documentStore]))
        return nil;
    
    _syncAgent = syncAgent;
    _account = account;
    _identifier = [_account.uuid copy];
    
    [_syncAgent afterAsynchronousOperationsFinish:^{
        // TODO: Possibily racing if the agent starts and stops quickly before we get set up. We'll maybe get nil values back in that case?
        _metadataItemRegistrationTable = [syncAgent metadataItemRegistrationTableForAccount:account];
        OBASSERT(_metadataItemRegistrationTable);
        
        [_metadataItemRegistrationTable addObserver:self forKeyPath:OFValidateKeyPath(_metadataItemRegistrationTable, values) options:0 context:&MetadataRegistrationContext];
        
        OBFinishPortingLater("Get rid of this extra ivar if we make the account's local documents URL set-once/read-only");
        _documentsURL = [_account.localDocumentsURL copy];
        OBASSERT(_documentsURL);
        
        OBFinishPortingLater("Might not have really finished the first scan? Add a flag on the registration table that says whether it has been filled or not, or just ensure it has been scanned by now...?");
        [self _updateFileItems];
        
        [self willChangeValueForKey:OFValidateKeyPath(self, hasFinishedInitialScan)];
        _hasFinishedInitialScan = YES;
        [self didChangeValueForKey:OFValidateKeyPath(self, hasFinishedInitialScan)];
    }];

    return self;
}

- (void)dealloc;
{
    [_metadataItemRegistrationTable removeObserver:self forKeyPath:OFValidateKeyPath(_metadataItemRegistrationTable, values) context:&MetadataRegistrationContext];
}

#pragma mark - OFSDocumentStoreConcreteScope

- (NSString *)identifier;
{
    return _identifier;
}

- (NSString *)displayName;
{
    return _account.displayName;
}

- (NSString *)moveToActionLabelWhenInList:(BOOL)inList;
{
    if (inList)
        return self.displayName;
    else
        return [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Move to \"%@\"", @"OmniFileExchange", OMNI_BUNDLE, @"Menu item label for moving a document to cloud storage"), self.displayName];
}

- (BOOL)hasFinishedInitialScan;
{
    return _hasFinishedInitialScan;
}

- (NSURL *)documentsURL;
{
    OBPRECONDITION(_documentsURL); // OBFinishPorting: May need to synchronously wait for this... Yuck.
    return _documentsURL;
}

- (BOOL)requestDownloadOfFileItem:(OFSDocumentStoreFileItem *)fileItem error:(NSError **)outError;
{
    NSURL *fileURL = fileItem.fileURL;
    [_syncAgent requestDownloadOfItemAtURL:fileURL completionHandler:^(NSError *errorOrNil){
        [errorOrNil log:@"Error starting download of %@", fileURL];
    }];
    
    // Change the protocol to take a completion handler here?
    return YES;
}

- (void)deleteItem:(OFSDocumentStoreFileItem *)fileItem completionHandler:(void (^)(NSError *errorOrNil))completionHandler;
{
    OBPRECONDITION(fileItem.scope == self);
    OBPRECONDITION([NSThread isMainThread]); // Synchronize with updating of fileItems, and this is the queue we'll invoke the completion handler on.
    
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    OFSDocumentStoreScope *trashScope = self.documentStore.trashScope;
    if (trashScope != nil) {
        [trashScope moveFileItems:[NSSet setWithObject:fileItem] completionHandler:^(OFSDocumentStoreFileItem *failingFileItem, NSError *errorOrNil) {
            completionHandler(errorOrNil);
        }];
        return;
    }
#endif

    // This will do file coordination if the document is downloaded (so other presenters will notice), otherwise just a metadata-based deletion.
    [_syncAgent deleteItemAtURL:fileItem.fileURL completionHandler:completionHandler];
}

- (void)performMoveFromURL:(NSURL *)sourceURL toURL:(NSURL *)destinationURL filePresenter:(id <NSFilePresenter>)filePresenter completionHandler:(void (^)(NSURL *destinationURL, NSError *errorOrNil))completionHandler;
{
    // We are running on our operation queue here, which is the account agent's queue.
    
    completionHandler = [completionHandler copy];
    
    OBFinishPortingLater("Figure out why OFS passes the destinationURL back at the completion handler -- maybe due to races and uniquification?");
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        [_syncAgent moveItemAtURL:sourceURL toURL:destinationURL completionHandler:^(NSError *errorOrNil){
            if (completionHandler) {
                [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                    if (errorOrNil)
                        completionHandler(nil, errorOrNil);
                    else
                        completionHandler(destinationURL, errorOrNil);
                }];
            }
        }];
    }];
}

#pragma mark - OFSDocumentStoreScope subclass

- (void)setFileItems:(NSSet *)fileItems;
{
    // Doing this here so that we'll catch added/removed file items handled by the superclass.
    [super setFileItems:fileItems];
    [self _updateUsedFileURLs];
}

- (BOOL)prepareToMoveFileItem:(OFSDocumentStoreFileItem *)fileItem toScope:(OFSDocumentStoreScope *)otherScope error:(NSError **)outError;
{
    // Skip any files that aren't fully downloaded. There is obviously a race condition here, but the actual file transfer code will also check and will produce a conflict copy if we were about to start downloading a new version of the file.
    
    if (!fileItem.isDownloaded) {
        NSString *description = NSLocalizedStringFromTableInBundle(@"Cannot move document.", @"OmniFileExchange", OMNI_BUNDLE, @"Error description");
        NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"The document \"%@\" is not fully downloaded.", @"OmniFileExchange", OMNI_BUNDLE, @"Error description"), fileItem.name];
        OFXError(outError, OFXFileItemNotDownloaded, description, reason);
        return NO;
    }
    OBASSERT(fileItem.percentDownloaded == 1);
    
    return [super prepareToMoveFileItem:fileItem toScope:otherScope error:outError];
}

static void _updateObjectValue(OFSDocumentStoreFileItem *fileItem, NSString *bindingKey, id newValue)
{
    OBPRECONDITION([NSThread isMainThread]); // Only fire KVO on the main thread
    
    id oldValue = [fileItem valueForKey:bindingKey];
    if (OFNOTEQUAL(oldValue, newValue)) {
        //DEBUG_METADATA(2, "  Setting %@ to %@", bindingKey, newValue);
        [fileItem setValue:newValue forKey:bindingKey];
    }
}

static void _updateFlagFromAttributes(OFSDocumentStoreFileItem *fileItem, NSString *bindingKey, OFXFileMetadata *metadata, NSString *attributeKey, BOOL defaultValue)
{
    BOOL value;
    NSNumber *attributeValue = [metadata valueForKey:attributeKey];
    if (!attributeValue) {
        OBASSERT(metadata == nil); // OK if we don't have a metadata item at all
        value = defaultValue;
    } else {
        value = [attributeValue boolValue];
    }
    
    id objectValue = value ? (id)kCFBooleanTrue : (id)kCFBooleanFalse;
    _updateObjectValue(fileItem, bindingKey, objectValue);
}

static void _updatePercentFromAttributes(OFSDocumentStoreFileItem *fileItem, NSString *bindingKey, OFXFileMetadata *metadata, NSString *attributeKey, double defaultValue)
{
    double value;
    NSNumber *attributeValue = [metadata valueForKey:attributeKey];
    if (!attributeValue) {
        OBASSERT_NOT_REACHED("Missing attribute value");
        value = defaultValue;
    } else {
        value = [attributeValue doubleValue];
    }
    
    _updateObjectValue(fileItem, bindingKey, @(value));
}

#define UPDATE_METADATA_FLAG(keySuffix) _updateFlagFromAttributes(fileItem, OFSDocumentStoreItem ## keySuffix ## Binding, metadata, OFXFileMetadata ## keySuffix ## Key, kOFSDocumentStoreFileItemDefault_ ## keySuffix)
#define UPDATE_METADATA_PERCENT(keySuffix) _updatePercentFromAttributes(fileItem, OFSDocumentStoreItem ## keySuffix ## Binding, metadata, OFXFileMetadata ## keySuffix ## Key, kOFSDocumentStoreFileItemDefault_ ## keySuffix)

- (void)updateFileItem:(OFSDocumentStoreFileItem *)fileItem withMetadata:(id)metadata fileModificationDate:(NSDate *)fileModificationDate;
{
    OBPRECONDITION([NSThread isMainThread]); // Fire KVO from the main thread
    
    OFXFileMetadata *metadataItem = metadata;
    OBASSERT(!metadataItem || [metadataItem isKindOfClass:[OFXFileMetadata class]]);
    
    DEBUG_METADATA(2, "Update file item %@ with metadata: %@", [fileItem shortDescription], [metadataItem debugDictionary]);

    // Use the metadata item's date if we have it. Otherwise, this might be a newly created/duplicated item that we know is in a sync container, but that we haven't received a metadata item for yet (so we'll use the date from the file system).
    NSDate *userModificationDate;
    if (metadataItem) {
        userModificationDate = metadataItem.modificationDate;
        OBASSERT(userModificationDate);
    } else {
        OBASSERT(fileModificationDate);
        userModificationDate = fileModificationDate;
    }
    if (!userModificationDate)
        userModificationDate = [NSDate date];
    
    fileItem.fileModificationDate = fileModificationDate;
    fileItem.userModificationDate = userModificationDate;
    
    UPDATE_METADATA_FLAG(HasDownloadQueued);
    UPDATE_METADATA_FLAG(IsUploaded);
    UPDATE_METADATA_FLAG(IsUploading);
    
    BOOL wasDownloaded = fileItem.isDownloaded;
    
    UPDATE_METADATA_FLAG(IsDownloading);
    UPDATE_METADATA_FLAG(IsDownloaded);
    
    if (fileItem.isUploading) // percent might not be in the attributes otherwise
        UPDATE_METADATA_PERCENT(PercentUploaded);
    else
        _updateObjectValue(fileItem, OFValidateKeyPath(fileItem, percentUploaded), @(kOFSDocumentStoreFileItemDefault_PercentUploaded)); // Set the default value
    
    if (fileItem.isDownloading) // percent might not be in the attributes otherwise
        UPDATE_METADATA_PERCENT(PercentDownloaded);
    else
        _updateObjectValue(fileItem, OFValidateKeyPath(fileItem, percentDownloaded), @(kOFSDocumentStoreFileItemDefault_PercentDownloaded)); // Set the default value
    
    if (!wasDownloaded && fileItem.isDownloaded) {
        [_fileItemsToAutomaticallyDownload removeObject:fileItem];
        fileItem.hasDownloadQueued = NO;
        [self _requestDownloadOfFileItem];
        
        OFSDocumentStore *documentStore = self.documentStore;
        if (!documentStore)
            return; // Weak pointer cleared
                
        // The file type and modification date stored in this file item may not have changed (since undownloaded file items know those). So, -_queueContentsChanged may end up posting no notification. Rather than forcing it to do so in this case, we have a specific notification for a download finishing.
        NSDictionary *userInfo = [NSDictionary dictionaryWithObject:fileItem forKey:OFSDocumentStoreFileItemInfoKey];
        [[NSNotificationCenter defaultCenter] postNotificationName:OFSDocumentStoreFileItemFinishedDownloadingNotification object:documentStore userInfo:userInfo];
    }
}

- (void)fileWithURL:(NSURL *)oldURL andDate:(NSDate *)date didMoveToURL:(NSURL *)newURL;
{
    [super fileWithURL:oldURL andDate:date didMoveToURL:newURL];
    
    [self _updateUsedFileURLs];
}

- (NSMutableSet *)copyCurrentlyUsedFileNamesInFolderAtURL:(NSURL *)folderURL ignoringFileURL:(NSURL *)fileURLToIgnore;
{    
    OBPRECONDITION([self isRunningOnActionQueue]);
    
    if (!folderURL)
        folderURL = _documentsURL;
    
    NSMutableSet *usedFileNames = [NSMutableSet new];
    
    for (NSURL *fileURL in _usedFileURLs) {
        if (OFURLEqualsURL(fileURL, fileURLToIgnore))
            continue;

        if (!OFURLEqualsURL(folderURL, [fileURL URLByDeletingLastPathComponent]))
            continue;
        [usedFileNames addObject:[fileURL lastPathComponent]];
    }
    
    return usedFileNames;
}

#pragma mark - NSKeyValueObserving

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context;
{
    if (context == &MetadataRegistrationContext) {
        OBASSERT(object == _metadataItemRegistrationTable);
        [self _updateFileItems];
        return;
    }

    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

#pragma mark - Debugging

- (NSString *)shortDescription;
{
    return [NSString stringWithFormat:@"<%@:%p %@>", NSStringFromClass([self class]), self, _account.displayName];
}

#pragma mark - Private

- (void)_updateUsedFileURLs;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    NSMutableArray *fileURLs = [NSMutableArray new];
    for (OFSDocumentStoreFileItem *fileItem in self.fileItems)
        [fileURLs addObject:fileItem.fileURL];

    [self performAsynchronousFileAccessUsingBlock:^{
        _usedFileURLs = [fileURLs copy];
    }];
}

- (void)_updateFileItems;
{
    OBPRECONDITION([NSThread isMainThread]);
    OBPRECONDITION(_documentsURL);
        
    // Index the existing file items, using the persistent file identifier (so that we can detect moves). But, newly created documents will go through the fast path, which calls -makeFileItemForURL:... and inserts it into our file items w/o a scan. To avoid creating yet another file item (and discarding the one from the fast path), we need to try to match up by fileURL too.
    NSMutableDictionary *existingFileItemByIdentifier = [NSMutableDictionary new];
    NSMutableDictionary *newFileItemsByCacheKey = nil;
    for (OFSDocumentStoreFileItem *fileItem in self.fileItems) {
        NSString *identifier = fileItem.scopeInfo;
        
        // Newly created documents will go through the fast path, which calls -makeFileItemForURL:... and inserts it into our file items w/o a scan. The down side of this fix is that on the next scan, we won't match up the existing file item and the URL and we'll end up creating a new file item.
        if (identifier) {
            OBASSERT([identifier isKindOfClass:[NSString class]]);
            OBASSERT(existingFileItemByIdentifier[identifier] == nil);
            existingFileItemByIdentifier[identifier] = fileItem;
        } else {
            if (!newFileItemsByCacheKey)
                newFileItemsByCacheKey = [NSMutableDictionary new];
            NSString *cacheKey = OFSDocumentStoreScopeCacheKeyForURL(fileItem.fileURL);
            OBASSERT(newFileItemsByCacheKey[cacheKey] == nil);
            newFileItemsByCacheKey[cacheKey] = fileItem;
        }
    }
        
    NSMutableSet *updatedFileItems = [[NSMutableSet alloc] init];
    for (OFXFileMetadata *metadataItem in _metadataItemRegistrationTable.values) {
        NSURL *fileURL = metadataItem.fileURL;
        
        if (!fileURL) {
            // This metadataItem is for a file which has been deleted locally and the delete is not yet done syncing to the remote side
            continue;
        }
        
        if (![[self class] isFile:fileURL inContainer:_documentsURL]) {
            OBASSERT_NOT_REACHED("We shouldn't be mixing items between scopes");
            continue;
        }
        
        DEBUG_METADATA(2, @"item %@ %@", metadataItem, [fileURL absoluteString]);
        DEBUG_METADATA(2, @"  %@", [metadataItem debugDictionary]);
        
        NSDate *userModificationDate = metadataItem.modificationDate;
        OBASSERT(userModificationDate);
        
        // We don't use file coordination here since we'll get notified via a metadata update if there is another change and since we are on the main queue and any coordinated read could deadlock.
        __autoreleasing NSError *attributesError;
        NSDate *fileModificationDate = [[NSFileManager defaultManager] attributesOfItemAtPath:[[fileURL absoluteURL] path] error:&attributesError].fileModificationDate;
        if (!fileModificationDate) {
            if ([attributesError causedByMissingFile]) {
                // The file might not yet be downloaded (and we no longer publish stubs), but it might also be disappearing due to a bulk delete operation being synced over from the Mac (deleting a whole folder of documents).
                // OBASSERT(metadataItem.isDownloaded == NO);
            } else
                NSLog(@"Error getting file modification date for %@: %@", fileURL, [attributesError toPropertyList]);
        }
        
        BOOL isNewItem = NO;
        
        NSString *fileIdentifier = metadataItem.fileIdentifier;
        OFSDocumentStoreFileItem *fileItem = existingFileItemByIdentifier[fileIdentifier];
        if (!fileItem) {
            // Might be a new item created by the new-document fast path. Try to associate the identifier with it instead of creating a new file item.
            fileItem = newFileItemsByCacheKey[OFSDocumentStoreScopeCacheKeyForURL(metadataItem.fileURL)];
            fileItem.scopeInfo = fileIdentifier;
        }
        
        if (!fileItem) {
            fileItem = [self makeFileItemForURL:fileURL isDirectory:metadataItem.isDirectory fileModificationDate:fileModificationDate userModificationDate:userModificationDate];
            if (!fileItem) {
                OBASSERT_NOT_REACHED("Failed to make a file item!");
                continue;
            }
            fileItem.scopeInfo = fileIdentifier;
            
            [updatedFileItems addObject:fileItem];
            isNewItem = YES;
        } else {
            [updatedFileItems addObject:fileItem];
            [existingFileItemByIdentifier removeObjectForKey:fileIdentifier];
            
            if (OFNOTEQUAL(fileItem.fileURL, metadataItem.fileURL))
                [fileItem didMoveToURL:metadataItem.fileURL];
        }
        
        DEBUG_METADATA(2, @"Updating metadata properties on file item %@", [fileItem shortDescription]);
        // If we have one already, use the date in the OFXFileMetadata (as well as other info) instead of the local filesystem modification date. Otherwise use the local filesystem date and defaults for the other metadata until we get one. But, we definitely know this item was in a sync container.
        [self updateFileItem:fileItem withMetadata:metadataItem fileModificationDate:fileModificationDate];
        
        if (isNewItem)
            [self _possiblyEnqueueDownloadRequestForNewlyAddedFileItem:fileItem metadataItem:metadataItem];
    }
    
    self.fileItems = updatedFileItems;
    
    [self invalidateUnusedFileItems:existingFileItemByIdentifier];
    
    OBFinishPortingLater("Maybe we should remove sync scopes from the document store when it is disabled, then we can use fileItems==nil");
    if (!_hasFinishedInitialScan) {
        [self willChangeValueForKey:OFValidateKeyPath(self, hasFinishedInitialScan)];
        _hasFinishedInitialScan = YES;
        [self didChangeValueForKey:OFValidateKeyPath(self, hasFinishedInitialScan)];
    }
    
    // We should maybe ask the document store if this is OK.
    if ([_fileItemsToAutomaticallyDownload count]) {
        [self _requestDownloadOfFileItem];
    }
}

- (void)_possiblyEnqueueDownloadRequestForNewlyAddedFileItem:(OFSDocumentStoreFileItem *)fileItem metadataItem:(OFXFileMetadata *)metadataItem;
{
    OBPRECONDITION([NSThread isMainThread]); // _fileItems and _fileItemsToAutomaticallyDownload are main-thread only
    
    // The first time we see an item for a URL (newly created or once at app launch), automatically start downloading it if it is "small" and we are on wi-fi. iWork seems to automatically download files in some cases where normal iCloud apps don't. Unclear what rules they uses.
    
    if (fileItem.isDownloaded)
        return;
    OFNetReachability *netReachability = _syncAgent.netReachability;
    if (!netReachability.reachable || netReachability.usingCell)
        return;
    
    unsigned long long fileSize = metadataItem.fileSize;
    
    NSUInteger maximumAutomaticDownloadSize = [[OFPreference preferenceForKey:@"OFXMaximumAutomaticDownloadSize"] unsignedIntegerValue];
    
    if (fileSize <= (unsigned long long)maximumAutomaticDownloadSize) {
        if (!_fileItemsToAutomaticallyDownload)
            _fileItemsToAutomaticallyDownload = [[NSMutableSet alloc] init];
        [_fileItemsToAutomaticallyDownload addObject:fileItem];
        fileItem.hasDownloadQueued = YES;
    }
}

- (void)_requestDownloadOfFileItem;
{
    OBPRECONDITION([NSThread isMainThread]); // _fileItems and _fileItemsToAutomaticallyDownload are main-thread only
    
    NSSet *fileItems = self.fileItems;
    
    // Get rid of any since-invalidated items.
    [_fileItemsToAutomaticallyDownload intersectSet:fileItems];
    
    // Bail if any file item is already downloading or we've asked it to start (metadata query update that it is may be pending). Manual download requests will still proceed.
    if ([fileItems any:^BOOL(OFSDocumentStoreFileItem *fileItem) { return fileItem.isDownloading || fileItem.downloadRequested; }])
        return;
    
    // OBFinishPorting: iCloud supposedly eagerly downloads all files on the Mac. We don't have -preferredFileItemForNextAutomaticDownload: on the Mac (it up-calls to the UI to see what previews are on screen), and we are only downloading small files on the Mac.
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    OFSDocumentStoreFileItem *fileItem = [self.documentStore preferredFileItemForNextAutomaticDownload:_fileItemsToAutomaticallyDownload];
#else
    OFSDocumentStoreFileItem *fileItem = [_fileItemsToAutomaticallyDownload anyObject];
#endif
    if (!fileItem)
        fileItem = [_fileItemsToAutomaticallyDownload anyObject];
    
    if (!fileItem)
        return; // Nothing left to download!
    
    OBASSERT(fileItem.isDownloaded == NO); // Since -_fileItemFinishedDownloading: should clean these up before we are called again.
    //NSLog(@"Requesting download of %@", fileItem.fileURL);
    
    __autoreleasing NSError *downloadError = nil;
    if (![fileItem requestDownload:&downloadError]) {
        NSLog(@"automatic download request for %@ failed with %@", fileItem.fileURL, [downloadError toPropertyList]);
    }
}

@end
