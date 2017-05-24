// Copyright 2010-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniDocumentStore/ODSLocalDirectoryScope.h>

#import <OmniDocumentStore/ODSStore.h>
#import <OmniDocumentStore/ODSScope-Subclass.h>
#import <OmniDocumentStore/ODSFileItem.h>
#import <OmniDocumentStore/ODSUtilities.h>
#import <OmniFoundation/NSArray-OFExtensions.h>
#import <OmniFoundation/NSFileCoordinator-OFExtensions.h>
#import <OmniFoundation/NSSet-OFExtensions.h>
#import <OmniFoundation/NSURL-OFExtensions.h>
#import <OmniFoundation/OFFileEdit.h>
#import <OmniFoundation/OFXMLIdentifier.h>

#import "ODSScope-Internal.h"
#import "ODSFileItem-Internal.h"
#import "ODSStore-Internal.h"

RCS_ID("$Id$");

@interface ODSLocalDirectoryScope () <ODSConcreteScope, NSFilePresenter>
@end

@implementation ODSLocalDirectoryScope
{
    BOOL _hasRegisteredAsFilePresenter;
    BOOL _hasFinishedInitialScan;
    NSOperationQueue *_filePresenterQueue;

    BOOL _rescanForPresentedItemDidChangeRunning;
    BOOL _presentedItemDidChangeCalledWhileRescanning;
}

+ (NSURL *)userDocumentsDirectoryURL;
{
    static NSURL *documentDirectoryURL = nil; // Avoid trying the creation on each call.
    
    if (!documentDirectoryURL) {
        __autoreleasing NSError *error = nil;
        documentDirectoryURL = [[[NSFileManager defaultManager] URLForDirectory:NSDocumentDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:YES error:&error] copy];
        if (!documentDirectoryURL) {
            NSLog(@"Error creating user documents directory: %@", [error toPropertyList]);
        }
        
        documentDirectoryURL = [[documentDirectoryURL URLByStandardizingPath] copy];
    }
    
    return documentDirectoryURL;
}

+ (NSURL *)trashDirectoryURL;
{
    static NSURL *trashDirectoryURL = nil; // Avoid trying the creation on each call.
    
    if (!trashDirectoryURL) {
        __autoreleasing NSError *error = nil;
        NSURL *appSupportURL = [[[NSFileManager defaultManager] URLForDirectory:NSApplicationSupportDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:YES error:&error] copy];
        if (!appSupportURL) {
            NSLog(@"Error creating application support directory: %@", [error toPropertyList]);
        } else {
            trashDirectoryURL = [[appSupportURL URLByAppendingPathComponent:@"Trash" isDirectory:YES] URLByAppendingPathComponent:@"Documents" isDirectory:YES];

            error = nil;
            if (![[NSFileManager defaultManager] createDirectoryAtURL:trashDirectoryURL withIntermediateDirectories:YES attributes:nil error:&error]) {
                NSLog(@"Error creating trash directory: %@", [error toPropertyList]);
            }
        }
    }
    
    return trashDirectoryURL;
}

+ (NSURL *)templateDirectoryURL;
{
    // The local scope wants 'Documents' in the scope path.
    return [[NSBundle mainBundle] URLForResource:@"Documents" withExtension:@""];
}

- (id)initWithDirectoryURL:(NSURL *)directoryURL scopeType:(ODSLocalDirectoryScopeType)scopeType documentStore:(ODSStore *)documentStore;
{
    OBPRECONDITION(directoryURL);
    OBPRECONDITION([[directoryURL absoluteString] hasSuffix:@"/"]);
    
    if (!(self = [super initWithDocumentStore:documentStore]))
        return nil;
    
    _directoryURL = [directoryURL copy];
    _isTrash = (scopeType == ODSLocalDirectoryScopeTrash);
    _isTemplate = (scopeType == ODSLocalDirectoryScopeTemplate);
    
    _filePresenterQueue = [[NSOperationQueue alloc] init];
    _filePresenterQueue.name = @"ODSLocalDirectoryScope NSFilePresenter notifications";
    _filePresenterQueue.maxConcurrentOperationCount = 1;
    
#if 0 && defined(DEBUG)
    if (_directoryURL)
        [[NSFileManager defaultManager] logPropertiesOfTreeAtURL:_directoryURL];
#endif
    
    [self _scanItemsWithCompletionHandler:nil];

    if (_isTrash)
        [ODSScope setTrashScope:self];

    return self;
}

- (void)dealloc;
{
    // NOTE: We cannot wait until here to -removeFilePresenter: since -addFilePresenter: retains us. We remove in -_invalidate
    OBASSERT([_filePresenterQueue operationCount] == 0);
}

#pragma mark - ODSConcreteScope

- (NSURL *)documentsURL;
{
    return _directoryURL;
}

- (BOOL)hasFinishedInitialScan;
{
    return _hasFinishedInitialScan;
}

- (BOOL)requestDownloadOfFileItem:(ODSFileItem *)fileItem error:(NSError **)outError;
{
    OBASSERT_NOT_REACHED("Local documents are always downloaded -- this should only be called if the fileItem.isDownloaded == NO");
    return YES;
}

- (void)deleteItems:(NSSet *)items completionHandler:(void (^)(NSSet *deletedFileItems, NSArray *errorsOrNil))completionHandler;
{
    OBPRECONDITION([items all:^BOOL(ODSItem *item) { return item.scope == self; }]);
    OBPRECONDITION([NSThread isMainThread]); // Synchronize with updating of fileItems, and this is the queue we'll invoke the completion handler on.
    
    // capture scope
    completionHandler = [completionHandler copy];
    
    if (!_isTrash) {
        ODSScope *trashScope = self.documentStore.trashScope;
        if (trashScope != nil) {
            [trashScope takeItems:items toFolder:trashScope.rootFolder ignoringFileItems:nil completionHandler:^(NSSet *movedFileItems, NSArray *errorsOrNil) {
                completionHandler(movedFileItems, errorsOrNil);
            }];
            return;
        }
    }

    NSArray *deletions;
    {
        NSMutableArray *collectingDeletions = [NSMutableArray new];
        for (ODSItem *item in items) {
            [item eachFile:^(ODSFileItem *file) {
                [collectingDeletions addObject:[[ODSFileItemDeletion alloc] initWithFileItem:file]];
            }];
        }
        deletions = [collectingDeletions copy];
    }
    DEBUG_STORE(@"Deletions %@", [deletions valueForKey:@"shortDescription"]);
    
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        NSArray *fileItems = [deletions arrayByPerformingBlock:^(ODSFileItemDeletion *deletion){ return deletion.fileItem; }];
        [self.documentStore _willRemoveFileItems:fileItems];
    }];
    
    [self performAsynchronousFileAccessUsingBlock:^{
        // Passing nil for the presenter so that we get our normal deletion notification via file coordination.
        NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
        
        NSMutableSet *deletedFileItems = [NSMutableSet new];
        NSMutableArray *errors = [NSMutableArray new];
        
        for (ODSFileItemDeletion *deletion in deletions) {
            __autoreleasing NSError *error = nil;
            BOOL success = [coordinator removeItemAtURL:deletion.sourceFileURL error:&error byAccessor:^BOOL(NSURL *newURL, NSError **outError){
                DEBUG_STORE(@"  coordinator issued URL to delete %@", newURL);
                
                __autoreleasing NSError *deleteError = nil;
                if (![[NSFileManager defaultManager] removeItemAtURL:newURL error:&deleteError]) {
                    NSLog(@"Error deleting %@: %@", [newURL absoluteString], [deleteError toPropertyList]);
                    if (outError)
                        *outError = deleteError;
                    return NO;
                }
                
                return YES;
            }];
            
            if (success)
                [deletedFileItems addObject:deletion.fileItem];
            else
                [errors addObject:error];
        }
        
        if (completionHandler) {
            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                completionHandler(deletedFileItems, errors);
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
        
        // We can get called a ton when moving a whole bunch of documents into iCloud. Don't start another scan until our first has finished.
        if (_rescanForPresentedItemDidChangeRunning) {
            // Note that there was a rescan request while the first was running. We don't want to queue up an arbitrary number of rescans, but if some operations happened while the first scan was running, we could miss them. So, we need to remember and do one more scan.
            _presentedItemDidChangeCalledWhileRescanning = YES;
            return;
        }
        
        _rescanForPresentedItemDidChangeRunning = YES;
        
        // Note: this will get called when the app is returned to the foreground, if coordinated writes were made while it was backgrounded.
        [self _scanItemsWithCompletionHandler:^{
            _rescanForPresentedItemDidChangeRunning = NO;
            
            // If there were more scans requested while the first was running, do *one* more now to catch any remaining changes (no matter how many requests there were).
            if (_presentedItemDidChangeCalledWhileRescanning) {
                _presentedItemDidChangeCalledWhileRescanning = NO;
                [self _requestScanDueToPresentedItemDidChange];
            }
        }];
    }];
}

#pragma mark - ODSScope subclass

- (NSInteger)documentScopeGroupRank;
{
    if (_isTrash)
        return 999;
    else if (_isTemplate)
        return 998;
    else
        return -1;
}

- (NSString *)identifier;
{
    if (_isTrash)
        return @"trash";
    else if (_isTemplate)
        return @"template";
    else
        return @"local";
}

- (NSString *)displayName;
{
    if (_isTrash)
        return NSLocalizedStringFromTableInBundle(@"Trash", @"OmniDocumentStore", OMNI_BUNDLE, @"Document store scope display name");
    else if (_isTemplate)
        return NSLocalizedStringFromTableInBundle(@"Built-in", @"OmniDocumentStore", OMNI_BUNDLE, @"Document store scope display name");
    else
        return NSLocalizedStringFromTableInBundle(@"Local Documents", @"OmniDocumentStore", OMNI_BUNDLE, @"Document store scope display name");
}

static void _updateObjectValue(ODSFileItem *fileItem, NSString *bindingKey, id newValue)
{
    OBPRECONDITION([NSThread isMainThread]); // Only fire KVO on the main thread
    
    id oldValue = [fileItem valueForKey:bindingKey];
    if (OFNOTEQUAL(oldValue, newValue)) {
        DEBUG_METADATA("  Setting %@ to %@", bindingKey, newValue);
        [fileItem setValue:newValue forKey:bindingKey];
    }
}

static void _updateFlag(ODSFileItem *fileItem, NSString *bindingKey, BOOL value)
{
    id objectValue = value ? (id)kCFBooleanTrue : (id)kCFBooleanFalse;
    _updateObjectValue(fileItem, bindingKey, objectValue);
}

#define UPDATE_LOCAL_FLAG(keySuffix) _updateFlag(fileItem, ODSItem ## keySuffix ## Binding, kODSFileItemDefault_ ## keySuffix)

- (void)updateFileItem:(ODSFileItem *)fileItem withMetadata:(id)metadata fileEdit:(OFFileEdit *)fileEdit;
{
    OBPRECONDITION(metadata == nil);
    OBPRECONDITION([NSThread isMainThread]); // Fire KVO from the main thread
    OBPRECONDITION(fileEdit);
    OBPRECONDITION(fileItem.isDownloaded); // Local files should always be downloaded and never post a ODSFileItemFinishedDownloadingNotification notification
    
    // Local filesystem items have the actual filesystem time as their user edit time.
    fileItem.fileEdit = fileEdit;
    fileItem.userModificationDate = fileEdit.fileModificationDate;
    
    UPDATE_LOCAL_FLAG(HasDownloadQueued);
    UPDATE_LOCAL_FLAG(IsDownloaded);
    UPDATE_LOCAL_FLAG(IsDownloading);
    UPDATE_LOCAL_FLAG(IsUploaded);
    UPDATE_LOCAL_FLAG(IsUploading);
    
    // Local items currently don't record their total size or size uploaded/downloaded -- we could start doing this, but for now it is just need for calculating the download progress on folders
    
    OBPOSTCONDITION(fileItem.isDownloaded); // should still be downloaded...
}

- (NSMutableSet *)copyCurrentlyUsedFileNamesInFolderAtURL:(NSURL *)folderURL ignoringFileURL:(NSURL *)fileURLToIgnore;
{
    // Collecting the names asynchronously from filesystem edits will yield out of date results. We still have race conditions with cloud services adding/removing files since coordinated reads of whole Documents directories does nothing to block writers.
    OBPRECONDITION([self isRunningOnActionQueue], "bug:///137297");
    
    if (!folderURL)
        folderURL = _directoryURL;
    
    NSMutableSet *usedFileNames = [[NSMutableSet alloc] init];
    
    fileURLToIgnore = [fileURLToIgnore URLByStandardizingPath];
    
    // <bug:///88352> (Need to deal with remotely defined package extensions when scanning our document store scopes)
    OFScanPathExtensionIsPackage isPackage = OFIsPackageWithKnownPackageExtensions(nil);
    OFScanDirectoryItemHandler itemHandler = ^(NSFileManager *fileManager, NSURL *fileURL){
        if (fileURLToIgnore && OFURLEqualsURL(fileURLToIgnore, [fileURL URLByStandardizingPath]))
            return;
        [usedFileNames addObject:[fileURL lastPathComponent]];
    };
    OFScanErrorHandler errorHandler = nil;
    
    OFScanDirectory(folderURL, NO/*shouldRecurse*/, ODSScanDirectoryExcludeInboxItemsFilter(), isPackage, itemHandler, errorHandler);
    
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
            __autoreleasing NSError *error;
            OFFileEdit *fileEdit = [[OFFileEdit alloc] initWithFileURL:fileURL error:&error];
            if (!fileEdit) {
                [error log:@"Unable to get info about file at %@", fileURL];
                return;
            }
            
            cacheKeyToFileInfo[ODSScopeCacheKeyForURL(fileURL)] = fileEdit;
        };
        
        void (^scanFinished)(void) = ^{
            OBASSERT([NSThread isMainThread]);
            
            // Index the existing file items
            NSMutableDictionary *existingFileItemByCacheKey = [[NSMutableDictionary alloc] init];
            for (ODSFileItem *fileItem in self.fileItems) {
                NSString *cacheKey = ODSScopeCacheKeyForURL(fileItem.fileURL);
                OBASSERT(existingFileItemByCacheKey[cacheKey] == nil);
                existingFileItemByCacheKey[cacheKey] = fileItem;
            }

            DEBUG_STORE(@"existingFileItemByCacheKey = %@", existingFileItemByCacheKey);
            
            NSMutableSet *updatedFileItems = [[NSMutableSet alloc] init];;
            
            // Update or create file items
            [cacheKeyToFileInfo enumerateKeysAndObjectsUsingBlock:^(NSString *cacheKey, OFFileEdit *fileEdit, BOOL *stop){
                ODSFileItem *fileItem = existingFileItemByCacheKey[cacheKey];
                
                // Our filesystem and user modification date are the same for local directory documents
                NSDate *fileModificationDate = fileEdit.fileModificationDate;
                NSDate *userModificationDate = fileModificationDate;
                
                NSURL *fileURL = fileEdit.originalFileURL;

                if (!fileItem) {
                    NSString *fileType = OFUTIForFileExtensionPreferringNative([fileURL pathExtension], @(fileEdit.directory));

                    if (![self.documentStore canViewFileTypeWithIdentifier:fileType]) {
                        [self performAsynchronousFileAccessUsingBlock:^{
                            // Passing nil for the presenter so that we get our normal deletion notification via file coordination.
                            NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
                            __autoreleasing NSError *error = nil;
                            [coordinator removeItemAtURL:fileURL error:&error byAccessor:^BOOL(NSURL *newURL, NSError **outError){
                                DEBUG_STORE(@"  coordinator issued URL to delete %@", newURL);

                                __autoreleasing NSError *deleteError = nil;
                                if (![[NSFileManager defaultManager] removeItemAtURL:newURL error:&deleteError]) {
                                    NSLog(@"Error deleting %@: %@", [newURL absoluteString], [deleteError toPropertyList]);
                                    if (outError)
                                        *outError = deleteError;
                                    return NO;
                                }

                                return YES;
                            }];
                        }];
                        return;
                    }

                    fileItem = [self makeFileItemForURL:fileURL isDirectory:fileEdit.directory fileEdit:fileEdit userModificationDate:userModificationDate];
                    if (!fileItem) {
                        OBASSERT_NOT_REACHED("Failed to make a file item!");
                        return;
                    }
                } else
                    [existingFileItemByCacheKey removeObjectForKey:cacheKey];

                [updatedFileItems addObject:fileItem];

                DEBUG_METADATA(@"Updating metadata properties on file item %@", [fileItem shortDescription]);
                [self updateFileItem:fileItem withMetadata:nil fileEdit:fileEdit];
            }];

            [self setFileItems:updatedFileItems itemMoved:NO];

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
        
        // <bug:///88352> (Need to deal with remotely defined package extensions when scanning our document store scopes)
        OFScanPathExtensionIsPackage isPackage = OFIsPackageWithKnownPackageExtensions(nil);
        OFScanErrorHandler errorHandler = ^(NSURL *fileURL, NSError *error){
            [error log:@"Unable to scan local file(s) at %@", fileURL];
            return YES; // Keep trying to get as many as we can...
        };
        
        OFScanDirectory(_directoryURL, YES/*shouldRecurse*/, ODSScanDirectoryExcludeInboxItemsFilter(), isPackage, itemBlock, errorHandler);
        
        if (scanFinished)
            [[NSOperationQueue mainQueue] addOperationWithBlock:scanFinished];
    }];
}

@end
