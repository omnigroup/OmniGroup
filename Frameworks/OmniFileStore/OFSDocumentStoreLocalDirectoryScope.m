// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFileStore/OFSDocumentStoreLocalDirectoryScope.h>

#import <OmniFileStore/OFSURL.h>
#import <OmniFileStore/OFSDocumentStoreScope-Subclass.h>
#import <OmniFileStore/OFSDocumentStoreFileItem.h>

//#import "OFSDocumentStoreFileItem-Internal.h"
//#import "OFSDocumentStoreItem-Internal.h"
#import "OFSDocumentStoreScope-Internal.h"

RCS_ID("$Id$");

@interface OFSDocumentStoreLocalDirectoryScopeFileInfo : NSObject
@property(nonatomic,copy) NSURL *fileURL;
@property(nonatomic,copy) NSDate *fileModificationDate;
@end
@implementation OFSDocumentStoreLocalDirectoryScopeFileInfo
@end

@interface OFSDocumentStoreLocalDirectoryScope () <OFSDocumentStoreConcreteScope, NSFilePresenter>
@end

@implementation OFSDocumentStoreLocalDirectoryScope
{
    BOOL _hasRegisteredAsFilePresenter;
    BOOL _hasFinishedInitialScan;
    NSOperationQueue *_filePresenterQueue;

    BOOL _rescanForPresentedItemDidChangeRunning;
    BOOL _presentedItemDidChangeCalledWhileRescanning;
}

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE

+ (NSURL *)userDocumentsDirectoryURL;
{
    static NSURL *documentDirectoryURL = nil; // Avoid trying the creation on each call.
    
    if (!documentDirectoryURL) {
        NSError *error = nil;
        documentDirectoryURL = [[[NSFileManager defaultManager] URLForDirectory:NSDocumentDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:YES error:&error] copy];
        if (!documentDirectoryURL) {
            NSLog(@"Error creating user documents directory: %@", [error toPropertyList]);
        }
        
        documentDirectoryURL = [[documentDirectoryURL URLByStandardizingPath] copy];
    }
    
    return documentDirectoryURL;
}

#endif

- (id)initWithDirectoryURL:(NSURL *)directoryURL documentStore:(OFSDocumentStore *)documentStore;
{
    OBPRECONDITION(directoryURL);
    OBPRECONDITION([[directoryURL absoluteString] hasSuffix:@"/"]);
    
    if (!(self = [super initWithDocumentStore:documentStore]))
        return nil;
    
    _directoryURL = [directoryURL copy];
    
    _filePresenterQueue = [[NSOperationQueue alloc] init];
    _filePresenterQueue.name = @"OFSDocumentStoreLocalDirectoryScope NSFilePresenter notifications";
    _filePresenterQueue.maxConcurrentOperationCount = 1;
    
#if 0 && defined(DEBUG)
    if (_directoryURL)
        [[NSFileManager defaultManager] logPropertiesOfTreeAtURL:_directoryURL];
#endif
    
    [self _scanItemsWithCompletionHandler:nil];
    
    return self;
}

- (void)dealloc;
{
    // NOTE: We cannot wait until here to -removeFilePresenter: since -addFilePresenter: retains us. We remove in -_invalidate
    OBASSERT([_filePresenterQueue operationCount] == 0);
}

#pragma mark - OFSDocumentStoreConcreteScope

- (NSURL *)documentsURL:(NSError **)outError;
{
    return _directoryURL;
}

- (BOOL)hasFinishedInitialScan;
{
    return _hasFinishedInitialScan;
}

- (BOOL)requestDownloadOfFileItem:(OFSDocumentStoreFileItem *)fileItem error:(NSError **)outError;
{
    OBASSERT_NOT_REACHED("Local documents are always downloaded -- this should only be called if the fileItem.isDownloaded == NO");
    return YES;
}

- (void)deleteItem:(OFSDocumentStoreFileItem *)fileItem completionHandler:(void (^)(NSError *errorOrNil))completionHandler;
{
    OBPRECONDITION(fileItem.scope == self);
    OBPRECONDITION([NSThread isMainThread]); // Synchronize with updating of fileItems, and this is the queue we'll invoke the completion handler on.
    
    // capture scope (might not be necessary since we aren't currently asynchronous here).
    completionHandler = [completionHandler copy];
    
    [self performAsynchronousFileAccessUsingBlock:^{
        // Passing nil for the presenter so that the file item gets its normal deletion accommodation request (it should then send us -_fileItemHasAccommodatedDeletion:).
        NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
        
        NSError *error = nil;
        __block BOOL success = NO;
        __block NSError *innerError = nil;
        
        [coordinator coordinateWritingItemAtURL:fileItem.fileURL options:NSFileCoordinatorWritingForDeleting error:&error byAccessor:^(NSURL *newURL){
            DEBUG_STORE(@"  coordinator issued URL to delete %@", newURL);
            
            NSError *deleteError = nil;
            if (![[NSFileManager defaultManager] removeItemAtURL:newURL error:&deleteError]) {
                NSLog(@"Error deleting %@: %@", [newURL absoluteString], [deleteError toPropertyList]);
                innerError = deleteError;
                return;
            }
            
            // Recommended calling convention for this API (since it returns void) is to set a __block variable to success...
            success = YES;
        }];
        
        
        if (!success) {
            OBASSERT(error || innerError);
            if (innerError)
                error = innerError;
        } else
            error = nil;
        
        if (completionHandler) {
            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                if (error)
                    completionHandler(error);
                else
                    completionHandler(innerError);
            }];
        }
    }];
}

- (void)wasAddedToDocumentStore;
{
    // Only be registered as a file presenter while a document store has us as a scope. NSFileCoordinator will retain us while we are a presenter, so we can't de-register in -dealloc.
    if (!_hasRegisteredAsFilePresenter) {
        _hasRegisteredAsFilePresenter = YES;
        [NSFileCoordinator addFilePresenter:self];
    }
}

- (void)willBeRemovedFromDocumentStore;
{
    if (_hasRegisteredAsFilePresenter) {
        _hasRegisteredAsFilePresenter = NO;
        [NSFileCoordinator removeFilePresenter:self];
    }
}

#pragma mark - NSFilePresenter

// We become the file presentor for our document store's directory (which we assume won't change...)
// Under iOS 5, when iTunes fiddles with your files, your app no longer gets deactivated and reactivated. Instead, the operations seem to happen via NSFileCoordinator.
// Sadly, we don't get subitem changes just -presentedItemDidChange, no matter what set of NSFilePresenter methods we implement (at least as of beta 7).
// Under the WWDC iOS 6 beta, we've started getting sub-item notifications, but not necessarily the right ones (typically "did change" instead of "did appear" or "accommodate deletion"). We'll watch both for the expected callbacks and the ones we actually get now.

- (NSURL *)presentedItemURL;
{
    OBPRECONDITION(_directoryURL);
    return _directoryURL;
}

- (NSOperationQueue *)presentedItemOperationQueue;
{
    OBPRECONDITION(_filePresenterQueue);
    return _filePresenterQueue;
}

- (void)presentedItemDidChange;
{
    [self _requestScanDueToPresentedItemDidChange];
}

- (void)presentedSubitemAtURL:(NSURL *)oldURL didMoveToURL:(NSURL *)newURL;
{
    OBASSERT_NOT_REACHED("Never seen this called, but it would sure be nice");
}

- (void)accommodatePresentedSubitemDeletionAtURL:(NSURL *)url completionHandler:(void (^)(NSError *errorOrNil))completionHandler;
{
    DEBUG_STORE(@"Accomodate sub item deletion at %@", url);
    
    completionHandler(nil);
    [self _requestScanDueToPresentedItemDidChange];
}

- (void)presentedSubitemDidAppearAtURL:(NSURL *)url;
{
    DEBUG_STORE(@"Sub item did appear at %@", url);
    [self _requestScanDueToPresentedItemDidChange];
}

- (void)presentedSubitemDidChangeAtURL:(NSURL *)url;
{
    DEBUG_STORE(@"Sub item did change at %@", url);
    [self _requestScanDueToPresentedItemDidChange];
}

- (void)_requestScanDueToPresentedItemDidChange;
{
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        OBPRECONDITION([NSThread isMainThread]);
        
        OBFinishPortingLater("Still need ability to ignore updates? Only do this in the UI?");
//        if (_ignoreDocumentsDirectoryUpdates > 0)
//            return; // Some other operation is going on that is provoking this change and that wants to do the rescan manually.
        
        // We can get called a ton when moving a whole bunch of documents into iCloud. Don't start another scan until our first has finished.
        if (_rescanForPresentedItemDidChangeRunning) {
            // Note that there was a rescan request while the first was running. We don't want to queue up an arbitrary number of rescans, but if some operations happened while the first scan was running, we could miss them. So, we need to remember and do one more scan.
            _presentedItemDidChangeCalledWhileRescanning = YES;
            return;
        }
        
        _rescanForPresentedItemDidChangeRunning = YES;
        
        // Note: this will get called when the app is returned to the foreground, if coordinated writes were made while it was backgrounded.
        [self _scanItemsWithCompletionHandler:^{
//        [self rescanDocumentsScrollingToURL:nil animated:YES completionHandler:^{
            _rescanForPresentedItemDidChangeRunning = NO;
            
            // If there were more scans requested while the first was running, do *one* more now to catch any remaining changes (no matter how many requests there were).
            if (_presentedItemDidChangeCalledWhileRescanning) {
                _presentedItemDidChangeCalledWhileRescanning = NO;
                [self _requestScanDueToPresentedItemDidChange];
            }
        }];
    }];
}

#pragma mark - OFSDocumentStoreScope subclass

- (NSString *)identifier;
{
    return @"local";
}

- (NSString *)displayName;
{
    return NSLocalizedStringFromTableInBundle(@"Local Documents", @"OmniFileStore", OMNI_BUNDLE, @"Document store scope display name");
}

- (NSString *)moveToActionLabelWhenInList:(BOOL)inList;
{
    if (inList)
        return self.displayName;
    else
        return [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Move to local documents", @"OmniFileStore", OMNI_BUNDLE, @"Menu item label for moving a document to local storage"), self.displayName];
}

static void _updateObjectValue(OFSDocumentStoreFileItem *fileItem, NSString *bindingKey, id newValue)
{
    OBPRECONDITION([NSThread isMainThread]); // Only fire KVO on the main thread
    
    id oldValue = [fileItem valueForKey:bindingKey];
    if (OFNOTEQUAL(oldValue, newValue)) {
        DEBUG_METADATA("  Setting %@ to %@", bindingKey, newValue);
        [fileItem setValue:newValue forKey:bindingKey];
    }
}

static void _updateFlag(OFSDocumentStoreFileItem *fileItem, NSString *bindingKey, BOOL value)
{
    id objectValue = value ? (id)kCFBooleanTrue : (id)kCFBooleanFalse;
    _updateObjectValue(fileItem, bindingKey, objectValue);
}

static void _updatePercent(OFSDocumentStoreFileItem *fileItem, NSString *bindingKey, double value)
{
    _updateObjectValue(fileItem, bindingKey, @(value));
}

#define UPDATE_LOCAL_FLAG(keySuffix) _updateFlag(fileItem, OFSDocumentStoreItem ## keySuffix ## Binding, kOFSDocumentStoreFileItemDefault_ ## keySuffix)
#define UPDATE_LOCAL_PERCENT(keySuffix) _updatePercent(fileItem, OFSDocumentStoreItem ## keySuffix ## Binding, kOFSDocumentStoreFileItemDefault_ ## keySuffix)

- (void)updateFileItem:(OFSDocumentStoreFileItem *)fileItem withMetadata:(id)metadata fileModificationDate:(NSDate *)fileModificationDate;
{
    OBPRECONDITION(metadata == nil);
    OBPRECONDITION([NSThread isMainThread]); // Fire KVO from the main thread
    OBPRECONDITION(fileItem.isDownloaded); // Local files should always be downloaded and never post a OFSDocumentStoreFileItemFinishedDownloadingNotification notification
    
    // Local filesystem items have the actual filesystem time as their user edit time.
    fileItem.fileModificationDate = fileModificationDate;
    fileItem.userModificationDate = fileModificationDate;
    
    UPDATE_LOCAL_FLAG(HasUnresolvedConflicts);
    UPDATE_LOCAL_FLAG(IsDownloaded);
    UPDATE_LOCAL_FLAG(IsDownloading);
    UPDATE_LOCAL_FLAG(IsUploaded);
    UPDATE_LOCAL_FLAG(IsUploading);
    
    UPDATE_LOCAL_PERCENT(PercentUploaded);
    UPDATE_LOCAL_PERCENT(PercentDownloaded);
    
    OBPOSTCONDITION(fileItem.isDownloaded); // should still be downloaded...
}

- (NSMutableSet *)copyCurrentlyUsedFileNamesInFolderNamed:(NSString *)folderName ignoringFileURL:(NSURL *)fileURLToIgnore;
{
    // Collecting the names asynchronously from filesystem edits will yield out of date results. We still have race conditions with cloud services adding/removing files since coordinated reads of whole Documents directories does nothing to block writers.
    OBPRECONDITION([self isRunningOnActionQueue]);
    
    NSURL *folderURL = _directoryURL;
    if (![NSString isEmptyString:folderName]) {
        OBFinishPorting;
#if 0
        folderURL = [folderURL URLByAppendingPathComponent:folderName];
        OBASSERT(OFSIsFolder(folderURL));
#endif
    }
    
    NSMutableSet *usedFileNames = [[NSMutableSet alloc] init];
    
    fileURLToIgnore = [fileURLToIgnore URLByStandardizingPath];
    
    OBFinishPortingLater("Use the set of known package extensions from the OFXAgent somehow");
    OFSScanPathExtensionIsPackage isPackage = OFSIsPackageWithKnownPackageExtensions(nil);

    OFSScanDirectory(folderURL, NO/*shouldRecurse*/, OFSScanDirectoryExcludeInboxItemsFilter(), isPackage, ^(NSFileManager *fileManager, NSURL *fileURL){
        if (fileURLToIgnore && [fileURLToIgnore isEqual:[fileURL URLByStandardizingPath]])
            return;
        [usedFileNames addObject:[fileURL lastPathComponent]];
    });
    
    return usedFileNames;
}

#pragma mark - Debugging

- (NSString *)shortDescription;
{
    return [NSString stringWithFormat:@"<%@:%p %@>", NSStringFromClass([self class]), self, [_directoryURL absoluteString]];
}

#pragma mark - Internal

- (void)_scanItemsWithCompletionHandler:(void (^)(void))completionHandler;
{
    completionHandler = [completionHandler copy];
    
    [self performAsynchronousFileAccessUsingBlock:^{
        
        // Build a map of cache key to file URL/modification dates for all the found URLs. We don't use the fileURL as a key since -hash/-isEqual: assert in DEBUG builds due to NSURL -isEqual: bugs.
        // We don't deal with file items in the scan since we need to update the fileItems property on the foreground once the scan is finished and since we'd need to snapshot the existing file items for reuse on the foreground. The gap between these could let other operations in that might add/remove file items. When we are merging this scanned dictionary into the results, we'll need to be careful of that (in particular, other creators of files items like the -addDocumentFromURL:... method
        NSMutableDictionary *cacheKeyToFileInfo = [[NSMutableDictionary alloc] init];
        
        void (^itemBlock)(NSFileManager *fileManager, NSURL *fileURL) = ^(NSFileManager *fileManager, NSURL *fileURL){
            NSString *cacheKey = OFSDocumentStoreScopeCacheKeyForURL(fileURL);
            NSDate *modificationDate = OFSDocumentStoreScopeModificationDateForFileURL(fileManager, fileURL);
            
            OFSDocumentStoreLocalDirectoryScopeFileInfo *fileInfo = [OFSDocumentStoreLocalDirectoryScopeFileInfo new];
            fileInfo.fileURL = fileURL;
            fileInfo.fileModificationDate = modificationDate;
            
            [cacheKeyToFileInfo setObject:fileInfo forKey:cacheKey];
        };
        
        void (^scanFinished)(void) = ^{
            OBASSERT([NSThread isMainThread]);
            
            // Index the existing file items
            NSMutableDictionary *existingFileItemByCacheKey = [[NSMutableDictionary alloc] init];
            for (OFSDocumentStoreFileItem *fileItem in self.fileItems) {
                NSString *cacheKey = OFSDocumentStoreScopeCacheKeyForURL(fileItem.fileURL);
                OBASSERT(existingFileItemByCacheKey[cacheKey] == nil);
                existingFileItemByCacheKey[cacheKey] = fileItem;
            }

            DEBUG_STORE(@"existingFileItemByCacheKey = %@", existingFileItemByCacheKey);
            
            NSMutableSet *updatedFileItems = [[NSMutableSet alloc] init];;
            
            // Update or create file items
            [cacheKeyToFileInfo enumerateKeysAndObjectsUsingBlock:^(NSString *cacheKey, OFSDocumentStoreLocalDirectoryScopeFileInfo *fileInfo, BOOL *stop) {
                OFSDocumentStoreFileItem *fileItem = existingFileItemByCacheKey[cacheKey];
                
                // Our filesystem and user modification date are the same for local directory documents
                NSDate *fileModificationDate = fileInfo.fileModificationDate;
                NSDate *userModificationDate = fileModificationDate;
                
                NSURL *fileURL = fileInfo.fileURL;
                
                if (!fileItem) {
                    NSNumber *isDirectory = nil;
                    NSError *resourceError = nil;
                    if (![fileURL getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:&resourceError]) {
                        NSLog(@"Error getting directory key for %@: %@", fileURL, [resourceError toPropertyList]);
                        isDirectory = @([[fileURL absoluteString] hasSuffix:@"/"]);
                    }

                    fileItem = [self makeFileItemForURL:fileURL isDirectory:[isDirectory boolValue] fileModificationDate:fileModificationDate userModificationDate:userModificationDate];
                    if (!fileItem) {
                        OBASSERT_NOT_REACHED("Failed to make a file item!");
                        return;
                    }
                } else
                    [existingFileItemByCacheKey removeObjectForKey:cacheKey];

                [updatedFileItems addObject:fileItem];

                DEBUG_METADATA(@"Updating metadata properties on file item %@", [fileItem shortDescription]);
                [self updateFileItem:fileItem withMetadata:nil fileModificationDate:fileModificationDate];
            }];
            
            self.fileItems = updatedFileItems;

            [self invalidateUnusedFileItems:existingFileItemByCacheKey];
            
            if (!_hasFinishedInitialScan) {
                [self willChangeValueForKey:OFValidateKeyPath(self, hasFinishedInitialScan)];
                _hasFinishedInitialScan = YES;
                [self didChangeValueForKey:OFValidateKeyPath(self, hasFinishedInitialScan)];
            }
            
            if (completionHandler)
                completionHandler();
        };
        
        
        OBASSERT(![NSThread isMainThread]);
        DEBUG_STORE(@"Scanning %@", _directoryURL);
#if 0 && defined(DEBUG)
        [[NSFileManager defaultManager] logPropertiesOfTreeAtURL:_directoryURL];
#endif
        
        OBFinishPortingLater("How do we get the flexible list of path extensions from the sync agent here?");
        OFSScanPathExtensionIsPackage isPackage = OFSIsPackageWithKnownPackageExtensions(nil);

        OFSScanDirectory(_directoryURL, YES/*shouldRecurse*/, OFSScanDirectoryExcludeInboxItemsFilter(), isPackage, itemBlock);
        
        if (scanFinished)
            [[NSOperationQueue mainQueue] addOperationWithBlock:scanFinished];
    }];
}

@end
