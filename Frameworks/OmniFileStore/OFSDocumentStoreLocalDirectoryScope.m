// Copyright 2010-2012 The Omni Group. All rights reserved.
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

@interface OFSDocumentStoreLocalDirectoryScope () <OFSDocumentStoreConcreteScope, NSFilePresenter>
@end

@implementation OFSDocumentStoreLocalDirectoryScope
{
    BOOL _hasRegisteredAsFilePresenter;
    BOOL _hasFinishedInitialScan;
    NSOperationQueue *_filePresenterQueue;
}

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE

#if 0
+ (OFSDocumentStoreLocalDirectoryScope *)defaultLocalScope;
{
    static OFSDocumentStoreLocalDirectoryScope *localScope = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        localScope = [[self alloc] initWithDirectoryURL:[self userDocumentsDirectoryURL]];
    });
    
    return localScope;
}
#endif

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
    
    [self _scanItems];
    
    return self;
}

#pragma mark - OFSDocumentStoreScope subclass

- (void)setDocumentStore:(OFSDocumentStore *)documentStore;
{
    [super setDocumentStore:documentStore];
    
    // Only be registered as a file presenter while a document store has us as a scope. NSFileCoordinator will retain us while we are a presenter, so we can't de-register in -dealloc.
    if (documentStore && !_hasRegisteredAsFilePresenter) {
        _hasRegisteredAsFilePresenter = YES;
        [NSFileCoordinator addFilePresenter:self];
    } else if (!documentStore && _hasRegisteredAsFilePresenter) {
        _hasRegisteredAsFilePresenter = NO;
        [NSFileCoordinator removeFilePresenter:self];
    }
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
        
        OBFinishPortingLater("Not scanning local directory");
#if 0
        if ([self parentViewController] == nil)
            return; // We'll rescan when the currently open document closes
        
        if (_ignoreDocumentsDirectoryUpdates > 0)
            return; // Some other operation is going on that is provoking this change and that wants to do the rescan manually.
        
        // We can get called a ton when moving a whole bunch of documents into iCloud. Don't start another scan until our first has finished.
        if (_rescanForPresentedItemDidChangeRunning) {
            // Note that there was a rescan request while the first was running. We don't want to queue up an arbitrary number of rescans, but if some operations happened while the first scan was running, we could miss them. So, we need to remember and do one more scan.
            _presentedItemDidChangeCalledWhileRescanning = YES;
            return;
        }
        
        _rescanForPresentedItemDidChangeRunning = YES;
        
        // Note: this will get called when the app is returned to the foreground, if coordinated writes were made while it was backgrounded.
        [self rescanDocumentsScrollingToURL:nil animated:YES completionHandler:^{
            _rescanForPresentedItemDidChangeRunning = NO;
            
            // If there were more scans requested while the first was running, do *one* more now to catch any remaining changes (no matter how many requests there were).
            if (_presentedItemDidChangeCalledWhileRescanning) {
                _presentedItemDidChangeCalledWhileRescanning = NO;
                [self _requestScanDueToPresentedItemDidChange];
            }
        }];
#endif
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

- (void)updateFileItem:(OFSDocumentStoreFileItem *)fileItem withMetadata:(id)metadata modificationDate:(NSDate *)modificationDate;
{
    OBPRECONDITION(metadata == nil);
    OBPRECONDITION([NSThread isMainThread]); // Fire KVO from the main thread
    OBPRECONDITION(fileItem.isDownloaded); // Local files should always be downloaded and never post a OFSDocumentStoreFileItemFinishedDownloadingNotification notification
    
    fileItem.date = modificationDate;
        
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

- (void)_scanItems;
{
    [self performAsynchronousFileAccessUsingBlock:^{
        
        // Build a map of document URLs to modification dates for all the found URLs. We don't deal with file items in the scan since we need to update the fileItems property on the foreground once the scan is finished and since we'd need to snapshot the existing file items for reuse on the foreground. The gap between these could let other operations in that might add/remove file items. When we are merging this scanned dictionary into the results, we'll need to be careful of that (in particular, other creators of files items like the -addDocumentFromURL:... method
        NSMutableDictionary *urlToModificationDate = [[NSMutableDictionary alloc] init];
        
        void (^itemBlock)(NSFileManager *fileManager, NSURL *fileURL) = ^(NSFileManager *fileManager, NSURL *fileURL){
            NSDate *modificationDate = OFSDocumentStoreScopeModificationDateForFileURL(fileManager, fileURL);
            [urlToModificationDate setObject:modificationDate forKey:fileURL];
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
            [urlToModificationDate enumerateKeysAndObjectsUsingBlock:^(NSURL *fileURL, NSDate *modificationDate, BOOL *stop) {
                NSString *cacheKey = OFSDocumentStoreScopeCacheKeyForURL(fileURL);
                OFSDocumentStoreFileItem *fileItem = existingFileItemByCacheKey[cacheKey];
                
                if (!fileItem) {
                    fileItem = [self makeFileItemForURL:fileURL date:modificationDate];
                    if (!fileItem) {
                        OBASSERT_NOT_REACHED("Failed to make a file item!");
                        return;
                    }
                } else
                    [existingFileItemByCacheKey removeObjectForKey:cacheKey];

                [updatedFileItems addObject:fileItem];

                DEBUG_METADATA(@"Updating metadata properties on file item %@", [fileItem shortDescription]);
                [self updateFileItem:fileItem withMetadata:nil modificationDate:modificationDate];
            }];
            
            self.fileItems = updatedFileItems;

            [self invalidateUnusedFileItems:existingFileItemByCacheKey];
            
            if (!_hasFinishedInitialScan) {
                [self willChangeValueForKey:OFValidateKeyPath(self, hasFinishedInitialScan)];
                _hasFinishedInitialScan = YES;
                [self didChangeValueForKey:OFValidateKeyPath(self, hasFinishedInitialScan)];
            }
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
