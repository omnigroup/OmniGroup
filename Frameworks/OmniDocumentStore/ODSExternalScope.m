// Copyright 2015 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniDocumentStore/ODSExternalScope.h>

#import <OmniFoundation/NSFileCoordinator-OFExtensions.h>
#import <OmniFoundation/NSURL-OFExtensions.h>
#import <OmniFoundation/OFPreference.h>

#import <OmniDocumentStore/ODSScope-Subclass.h>
#import <OmniDocumentStore/ODSStore.h>
#import <OmniDocumentStore/ODSUtilities.h>

RCS_ID("$Id$")

@interface ODSExternalScope () <ODSConcreteScope>
@end

@implementation ODSExternalScope
{
    NSMutableSet *_transientFileItems;
    NSMutableSet *_securedURLs;
}

- initWithDocumentStore:(ODSStore *)documentStore;
{
    self = [super initWithDocumentStore:documentStore];
    if (self == nil)
        return nil;

    _transientFileItems = [[NSMutableSet alloc] init];
    _securedURLs = [[NSMutableSet alloc] init];
    [self setFileItems:_transientFileItems itemMoved:NO];

    return self;
}

- (NSURL *)documentsURL;
{
    return nil;
}

- (void)addExternalFileItem:(ODSFileItem *)fileItem;
{
    [_transientFileItems addObject:fileItem];
    [self setFileItems:_transientFileItems itemMoved:NO];
}

#pragma mark - ODSScope subclass

- (void)setFileItems:(NSSet *)fileItems itemMoved:(BOOL)itemMoved;
{
    if (fileItems != _transientFileItems)
        _transientFileItems.set = fileItems;
    [super setFileItems:fileItems itemMoved:itemMoved];
    if (_itemsDidChangeBlock != NULL)
        _itemsDidChangeBlock(_transientFileItems);
}

- (BOOL)isFileInContainer:(NSURL *)fileURL;
{
    for (ODSFileItem *transientItem in _transientFileItems) {
        if (OFISEQUAL(fileURL, transientItem.fileURL))
            return YES;
    }
    return NO;
}

- (void)addDocumentInFolder:(ODSFolderItem *)folderItem baseName:(NSString *)baseName fileType:(NSString *)fileType fromURL:(NSURL *)fromURL option:(ODSStoreAddOption)option completionHandler:(void (^)(ODSFileItem *duplicateFileItem, NSError *error))completionHandler;
{
    if (_addDocumentBlock != NULL) {
        _addDocumentBlock(folderItem, baseName, fileType, fromURL, option, completionHandler);
    } else {
        completionHandler(nil, [NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError userInfo:nil]); // The user tried to add a new document, but we're not set up to handle that.
    }
}

- (void)takeItems:(NSSet *)items toFolder:(ODSFolderItem *)folderItem ignoringFileItems:(NSSet *)ignoredFileItems completionHandler:(void (^)(NSSet *movedFileItems, NSArray *errorsOrNil))completionHandler;
{
    completionHandler = [completionHandler copy];
    __block NSMutableArray *remainingItems = [[NSMutableArray alloc] initWithArray:[items allObjects]];
    __block NSMutableSet *movedFileItems = [[NSMutableSet alloc] init];
    __block NSMutableArray *errors = [[NSMutableArray alloc] init];
    __block void (^processNextItem)(void) = ^{
        ODSFileItem *item = [remainingItems firstObject];
        if (item == nil) {
            completionHandler(movedFileItems, errors.count != 0 ? errors : nil);
            processNextItem = NULL;
            return;
        }
        [remainingItems removeObjectAtIndex:0];
        [self addDocumentInFolder:folderItem baseName:item.name fromURL:item.fileURL option:ODSStoreAddByCopyingSourceToAvailableDestinationURL completionHandler:^(ODSFileItem *duplicateFileItem, NSError *error) {
            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                if (duplicateFileItem != nil)
                    [movedFileItems addObject:duplicateFileItem];
                if (error != nil)
                    [errors addObject:error];
                processNextItem();
            }];
        }];
    };
    processNextItem();
}

#pragma mark - Subclass-only APIs

- (void)completedMoveOfFileItem:(ODSFileItem *)fileItem toURL:(NSURL *)destinationURL;
{
    [super completedMoveOfFileItem:fileItem toURL:destinationURL];
    [self setFileItems:_transientFileItems itemMoved:YES];
}

- (NSMutableSet *)copyCurrentlyUsedFileNamesInFolderAtURL:(NSURL *)folderURL ignoringFileURL:(NSURL *)fileURLToIgnore;
{
    // Collecting the names asynchronously from filesystem edits will yield out of date results. We still have race conditions with cloud services adding/removing files since coordinated reads of whole Documents directories does nothing to block writers.
    OBPRECONDITION([self isRunningOnActionQueue]);
    
    if (folderURL == nil)
        return [NSMutableSet set];
    
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

- (BOOL)canRenameDocuments;
{
    return NO;
}

- (BOOL)canCreateFolders;
{
    return NO;
}

- (BOOL)isExternal;
{
    return YES;
}

- (BOOL)prepareToRelinquishItem:(ODSItem *)item error:(NSError **)outError;
{
    if (!self.allowDeletes) {
        if (outError != NULL)
            *outError = [NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError userInfo:nil];
        return NO;
    }

    ODSFileItem *fileItem = OB_CHECKED_CAST(ODSFileItem, item); // We only have ODSFileItems in this scope
    if ([fileItem.fileURL startAccessingSecurityScopedResource]) {
        [_securedURLs addObject:fileItem.fileURL];
    }
    return YES;
}

- (void)finishRelinquishingMovedItems:(NSSet *)movedItems;
{
    for (NSURL *securedURL in _securedURLs) {
#ifdef DEBUG_kc
        NSLog(@"Finish relinquishing item: %@", securedURL);
#endif
        [securedURL stopAccessingSecurityScopedResource]; // TODO: Did this URL change when the item moved?
    }
    [_securedURLs removeAllObjects];

    [self _removeTransientItems:movedItems errorsOrNil:@[] completionHandler:NULL];
}

#pragma mark - ODSConcreteScope

- (BOOL)hasFinishedInitialScan;
{
    return YES;
}

- (BOOL)requestDownloadOfFileItem:(ODSFileItem *)fileItem error:(NSError **)outError;
{
    OBASSERT_NOT_REACHED("External scopes should only contain files which have already started downloading");
    return NO;
}

- (NSURL *)urlForNewDocumentInFolderAtURL:(NSURL *)folderURL baseName:(NSString *)baseName fileType:(NSString *)documentUTI;
{
    OBRejectInvalidCall(self, _cmd, @"External scopes cannot provide URLs for new documents (folderURL=[%@], baseName=[%@], fileType=[%@]", [folderURL absoluteString], baseName, documentUTI);
}

- (void)_removeTransientItems:(NSSet *)deletedFileItems errorsOrNil:(NSArray *)errorsOrNil completionHandler:(void (^)(NSSet *deletedFileItems, NSArray *errorsOrNil))completionHandler;
{
    // Remove them from our transient list of file items
    NSMutableSet *deletedItems = [NSMutableSet set];
    for (ODSItem *item in deletedFileItems) {
        if ([_transientFileItems containsObject:item]) {
            [_transientFileItems removeObject:item];
            [deletedItems addObject:item];
        }
    }

    [self setFileItems:_transientFileItems itemMoved:NO];

    if (completionHandler != NULL)
        completionHandler(deletedItems, errorsOrNil);
}

- (void)deleteItems:(NSSet *)items completionHandler:(void (^)(NSSet *deletedFileItems, NSArray *errorsOrNil))completionHandler;
{
    completionHandler = [completionHandler copy];

    ODSScope *trashScope = self.documentStore.trashScope;
    if (self.allowDeletes && trashScope != nil) {
        // If we have a trash scope, move deleted items to the trash
        NSMutableArray *securedURLs = [[NSMutableArray alloc] init];
        for (ODSFileItem *fileItem in items) {
            NSURL *fileURL = fileItem.fileURL;
            if ([fileURL startAccessingSecurityScopedResource])
                [securedURLs addObject:fileURL];
        }
        [trashScope takeItems:items toFolder:trashScope.rootFolder ignoringFileItems:nil completionHandler:^(NSSet *deletedFileItems, NSArray *errorsOrNil) {
            for (NSURL *fileURL in securedURLs) {
                [fileURL stopAccessingSecurityScopedResource];
            }

            [self _removeTransientItems:deletedFileItems errorsOrNil:errorsOrNil completionHandler:completionHandler];
        }];
    } else {
        [self _removeTransientItems:items errorsOrNil:@[] completionHandler:completionHandler];
    }
}

- (void)renameFileItem:(ODSFileItem *)fileItem baseName:(NSString *)baseName fileType:(NSString *)fileType completionHandler:(void (^)(NSURL *destinationURL, NSError *errorOrNil))completionHandler;
{
#if 1
    // If the user tries to rename our document, just ignore the change since we can't actually do that
    completionHandler(nil, [NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError userInfo:nil]);
#else
    // This code works with iCloud Drive in the simulator, but not with iCloud Drive on an actual device (it returns an EPERM posix error).
    completionHandler = [completionHandler copy];
    NSURL *sourceURL = fileItem.fileURL;
    NSURL *securedURL = sourceURL;
    if (![securedURL startAccessingSecurityScopedResource])
        securedURL = nil;
    void (^deferredCompletion)(NSURL *, NSError *) = ^(NSURL *destinationURL, NSError *errorOrNil) {
        [securedURL stopAccessingSecurityScopedResource];
        if (completionHandler == NULL)
            return;

        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            completionHandler(destinationURL, errorOrNil);
        }];
    };

    NSURL *containingDirectoryURL = [sourceURL URLByDeletingLastPathComponent];
    OBASSERT(containingDirectoryURL);
    NSString *extension = OFPreferredPathExtensionForUTI(fileType);
    if (extension == nil)
        OBRequestConcreteImplementation(self, _cmd); // UTI not registered in the Info.plist?
    NSString *destinationFileName = [baseName stringByAppendingPathExtension:extension];
    NSURL *destinationURL = [containingDirectoryURL URLByAppendingPathComponent:destinationFileName isDirectory:NO];

    NSError *moveError = nil;
    NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
    if (![coordinator moveItemAtURL:sourceURL toURL:destinationURL createIntermediateDirectories:YES error:&moveError success:^(NSURL *resultURL) {
        [self completedMoveOfFileItem:fileItem toURL:destinationURL];
        deferredCompletion(resultURL, nil);
    }]) {
        deferredCompletion(nil, moveError);
    }
#endif
}

@end
