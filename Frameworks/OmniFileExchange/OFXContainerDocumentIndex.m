// Copyright 2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFXContainerDocumentIndex.h"

#import "OFXFileItem.h"
#import "OFXContainerAgent.h"
#import "OFXFileSnapshotRemoteEncoding.h"

#import <OmniFileStore/OFSURL.h>

RCS_ID("$Id$")

@implementation OFXContainerDocumentIndex
{
    __weak OFXContainerAgent *_weak_containerAgent;
    
    /*
     Maps the uuid of documents inside Snapshots (which is a flat directory of uuid folders) to the user visible Documents directory.
     Locally deleted documents will only appear in the _documentIdentifierToFileItem (since they don't have a local path).
     We also map the container relative local path for file items so that we know what server-side document to apply changes to when we find out about them on the local filesystem. In the case that two server documents want to claim the same container-relative path, only one can be present on the local filesystem (actually zero might be if neither are downloaded). In this case, we want to rename one of the documents so that the user can actually interact with all their content. But, we have to be careful since we can transiently think we have a conflict (say one client renames A->B and then makes a new A).
     
     One approach to this would be to try to make sure we have an entirely up-to-date copy of all the metadata on the server before making conflict renames. But, this is a losing proposition since the instant we think we have current metadata, another client could change it.
     
     A further wrinkle in all this is that we want be wary of case sensitivity in local relative paths since some filesystems are case sensitive (iOS device) and others aren't (Mac and iOS Simulator). Not only can this happen in the filename of the document itself, but in the containing folders ("foo/A.ext" vs "Foo/A.ext").
     
     Another approach might be to have a 'document index' object that does the work of mapping identifier->file and case-insensitive-path->multiple files, with one being the published item. We can then periodically check if we have unpublishable documents that are hidden by some other published document and we can do the conflict rename at that time.
     
     An important case to test is when we have a published document with local edits and a new document comes in desiring that path from the server. We need the local document with edits to not lose its contents in favor of the new document (unless we generate a new conflict document from them).
     */
    NSMutableDictionary *_documentIdentifierToFileItem;
    NSMutableDictionary *_localRelativePathToFileItems;
}

- (id)init;
{
    OBRejectUnusedImplementation(self, _cmd);
}

- initWithContainerAgent:(OFXContainerAgent *)containerAgent;
{
    OBPRECONDITION(containerAgent);
    
    if (!(self = [super init]))
        return nil;
    
    _weak_containerAgent = containerAgent;
    _documentIdentifierToFileItem = [NSMutableDictionary new];
    _localRelativePathToFileItems = [NSMutableDictionary new];
    
    return self;
}

- (NSMutableSet *)copyRegisteredFileItemIdentifiers;
{
    NSMutableSet *identifiers = [NSMutableSet new];
    for (NSString *identifier in _documentIdentifierToFileItem)
        [identifiers addObject:identifier];
    return identifiers;
}

static OFXFileItem *_publishedFileItem(NSArray *fileItems)
{
    OFXFileItem *publishedFileItem;
    
    for (OFXFileItem *fileItem in fileItems) {
        if (_isPublished(fileItem)) {
            OBASSERT(publishedFileItem == nil, @"Only one file item can be published for a given path, but the same path is claimed by %@ and %@", [publishedFileItem shortDescription], [fileItem shortDescription]);
            publishedFileItem = fileItem;
#if !defined(OMNI_ASSERTIONS_ON)
            break; // keep looking through the whole array if assertions are on.
#endif
        }
    }
    
    return publishedFileItem;
}

static OFXFileItem *_publishableFileItem(NSArray *fileItems)
{
    OFXFileItem *publishedFileItem = _publishedFileItem(fileItems);
    if (publishedFileItem)
        return publishedFileItem;
    
    // Might be trying to download a new file, for example.
    // We could maybe try to return the file item with the lexigraphically least identifier so that two clients would make the same decision about what to show. But really, if this condition lasts long enough for a user to notice, we should have started a conflict rename.
    for (OFXFileItem *fileItem in fileItems) {
        if (_isPublishable(fileItem))
            return fileItem;
    }
    
    return nil;
}

- (NSMutableDictionary *)copyLocalRelativePathToPublishedFileItem;
{
    NSMutableDictionary *result = [NSMutableDictionary new];
    [_localRelativePathToFileItems enumerateKeysAndObjectsUsingBlock:^(NSString *localRelativePath, NSArray *fileItems, BOOL *stop) {
        OFXFileItem *fileItem = _publishedFileItem(fileItems);
        if (fileItem)
            result[localRelativePath] = fileItem;
    }];
    return result;
}

#ifdef OMNI_ASSERTIONS_ON
- (NSObject <NSCopying> *)copyIndexState;
{
    NSDictionary *documentIdentifierToFileItem = [_documentIdentifierToFileItem copy];
    NSDictionary *localRelativePathToFileItems = [_localRelativePathToFileItems copy];
    return [NSArray arrayWithObjects:documentIdentifierToFileItem, localRelativePathToFileItems, nil];
}
#endif

- (OFXFileItem *)fileItemWithIdentifier:(NSString *)identifier;
{
    OBPRECONDITION([identifier containsString:OFXRemoteFileIdentifierToVersionSeparator] == NO, @"Should not contain our separator");
    
    OFXFileItem *fileItem = _documentIdentifierToFileItem[identifier];
    OBASSERT(!fileItem || [fileItem.identifier isEqual:identifier]);
    return fileItem;
}

- (OFXFileItem *)publishedFileItemWithLocalRelativePath:(NSString *)localRelativePath;
{
    return _publishedFileItem(_localRelativePathToFileItems[localRelativePath]);
}

- (OFXFileItem *)publishableFileItemWithLocalRelativePath:(NSString *)localRelativePath;
{
    return _publishableFileItem(_localRelativePathToFileItems[localRelativePath]);
}

- (void)enumerateFileItems:(void (^)(NSString *identifier, OFXFileItem *fileItem))block;
{
    [_documentIdentifierToFileItem enumerateKeysAndObjectsUsingBlock:^(NSString *identifier, OFXFileItem *fileItem, BOOL *stop) {
        block(identifier, fileItem);
    }];
}

// Some of the returned file item might be shadowed and some might not.
- (NSDictionary *)copyRenameConflictLoserFileItemsByWinningFileItem;
{
    __block NSMutableDictionary *losersByWinner = nil;
    
    [_localRelativePathToFileItems enumerateKeysAndObjectsUsingBlock:^(NSString *localRelativePath, NSMutableArray *fileItems, BOOL *stop) {
        if ([fileItems count] <= 1)
            return;
        
        // Try to pick a winner that will cause the least grief (or at least be consistent across devices).
        [fileItems sortedArrayUsingComparator:^NSComparisonResult(OFXFileItem *fileItem1, OFXFileItem *fileItem2) {
            // Locally created items should come first (that is, be least likely to be the winner).
            if (fileItem1.remoteState.missing)
                return NSOrderedDescending;
            if (fileItem2.remoteState.missing)
                return NSOrderedDescending;
            
            // Older items should win more often.
            NSComparisonResult result = [fileItem1.userCreationDate compare:fileItem2.userCreationDate];
            if (result != NSOrderedSame)
                return result;
            
            // Fall back to comparing by identifier
            return [fileItem1.identifier compare:fileItem2.identifier];
        }];
        
        if (!losersByWinner)
            losersByWinner = [NSMutableDictionary new];
        
        // Add all but one, the winner
        NSMutableArray *losers = [fileItems mutableCopy];
        OFXFileItem *winner = [fileItems lastObject];
        [losers removeLastObject];
        
        losersByWinner[winner] =  losers;
    }];
    
    return losersByWinner;
}

// Called at startup, so we might get a file item that has been locally deleted.
- (void)registerScannedLocalFileItem:(OFXFileItem *)fileItem;
{
    OBPRECONDITION(_documentIdentifierToFileItem[fileItem.identifier] == nil);
    
    _documentIdentifierToFileItem[fileItem.identifier] = fileItem;
    
    if (fileItem.localState.deleted) {
        // Deleted items have no local path
    } else {
        _registerFileItemByLocalRelativePath(self, fileItem, fileItem.localRelativePath);
        DEBUG_LOCAL_RELATIVE_PATH(1, @"Registering %@", [fileItem shortDescription]);
    }
}

static BOOL _isPublished(OFXFileItem *fileItem)
{
    return (fileItem.localState.missing == NO && fileItem.localState.deleted == NO);
}

static BOOL _isPublishable(OFXFileItem *fileItem)
{
    return (fileItem.localState.deleted == NO);
}

static void _updateShadowing(NSArray *fileItems)
{
    // We could almost do something like conflict NSFileVersions here, but we don't have a guaranteed winner (unless we build a stable ordering and this would require being willing to hide local edits under a conflict version).
    OBPRECONDITION([fileItems count] > 1); // Only call this for non-trivial cases
    OFXFileItem *publishableFileItem = _publishableFileItem(fileItems);
    for (OFXFileItem *fileItem in fileItems) {
        if (!_isPublishable(fileItem))
            fileItem.shadowedByOtherFileItem = NO; // Deleted file items don't publish metadata anyway and complain if you try to ask for their localDocumentURL.
        else
            fileItem.shadowedByOtherFileItem = (fileItem != publishableFileItem); // All but the first publishable file are invisible
    }
}

// Just does the local relative path.
static void _registerFileItemByLocalRelativePath(OFXContainerDocumentIndex *self, OFXFileItem *fileItem, NSString *localRelativePath)
{
    NSMutableArray *fileItems = self->_localRelativePathToFileItems[localRelativePath];
    if (fileItems) {
        OBASSERT([fileItems count] > 0, @"Don't keep around empty arrays");
        OBASSERT([fileItems indexOfObject:fileItem] == NSNotFound, @"Duplicate registration of file?");
        [fileItems addObject:fileItem];
        
        _updateShadowing(fileItems);
    } else {
        fileItem.shadowedByOtherFileItem = NO;
        fileItems = [[NSMutableArray alloc] initWithObjects:&fileItem count:1];
        self->_localRelativePathToFileItems[localRelativePath] = fileItems;
    }
}

static void _registerFileItem(OFXContainerDocumentIndex *self, OFXFileItem *fileItem)
{
    OBPRECONDITION(self->_documentIdentifierToFileItem[fileItem.identifier] == nil, @"Duplicate registration of file?");
    self->_documentIdentifierToFileItem[fileItem.identifier] = fileItem;
    
    _registerFileItemByLocalRelativePath(self, fileItem, fileItem.localRelativePath);
}

- (void)registerRemotelyAppearingFileItem:(OFXFileItem *)fileItem;
{
    OBPRECONDITION(fileItem.localState.missing);
        
    _registerFileItem(self, fileItem);
    DEBUG_LOCAL_RELATIVE_PATH(1, @"New remote document %@ -> %@", fileItem.localRelativePath, [fileItem shortDescription]);
    DEBUG_LOCAL_RELATIVE_PATH(2, @"  shadow losers %@", [self copyRenameConflictLoserFileItemsByWinningFileItem]);
}

- (void)registerLocallyAppearingFileItem:(OFXFileItem *)fileItem;
{
    OBPRECONDITION(fileItem.remoteState.missing);
    
    // Actually, this can happen if there is a remotely existing file that we've found out about but not downloaded. So, we can find the local file while the remote file is still downloading (or it might not be downloading at all if it is too big or auto-downloading is off).
    //OBPRECONDITION(_localRelativePathToFileItems[fileItem.localRelativePath] == nil, @"A file can't be newly appearing in the local filesystem unless nothing was there before");

    _registerFileItem(self, fileItem);
    DEBUG_LOCAL_RELATIVE_PATH(1, @"New local document %@ -> %@", fileItem.localRelativePath, [fileItem shortDescription]);
    DEBUG_LOCAL_RELATIVE_PATH(2, @"  shadow losers %@", [self copyRenameConflictLoserFileItemsByWinningFileItem]);
}

// This is to detect folder renames. If we have two items requesting that they by "foo/A.ext", and we rename "foo" to "bar", we want both file items to move along too.
- (void)addFileItems:(NSMutableArray *)resultFileItems inDirectoryWithRelativePath:(NSString *)localDirectoryRelativePath;
{
    OBPRECONDITION([localDirectoryRelativePath hasSuffix:@"/"]);
    
    [_localRelativePathToFileItems enumerateKeysAndObjectsUsingBlock:^(NSString *localRelativePath, NSArray *fileItems, BOOL *stop) {
        // TEST CASE: Do a case-insensitive prefix check here?
        if ([localRelativePath hasPrefix:localDirectoryRelativePath])
            [resultFileItems addObjectsFromArray:fileItems];
    }];
}

static void _forgetItemByLocalRelativePath(OFXContainerDocumentIndex *self, OFXFileItem *fileItem, NSString *localRelativePath)
{
    NSMutableArray *fileItems = self->_localRelativePathToFileItems[localRelativePath];
    OBASSERT([fileItems containsObject:fileItem]);
    [fileItems removeObject:fileItem];
    
    switch ([fileItems count]) {
        case 0:
            [self->_localRelativePathToFileItems removeObjectForKey:localRelativePath];
            break;
        case 1: {
            OFXFileItem *fileItem = [fileItems lastObject];
            fileItem.shadowedByOtherFileItem = NO;
            break;
        }
        default:
            _updateShadowing(fileItems);
            break;
    }
}

- (void)forgetFileItemForRemoteDeletion:(OFXFileItem *)fileItem;
{
    DEBUG_LOCAL_RELATIVE_PATH(1, @"Forgetting file item %@", [fileItem shortDescription]);
    
    _forgetItemByLocalRelativePath(self, fileItem, fileItem.localRelativePath);
    [_documentIdentifierToFileItem removeObjectForKey:fileItem.identifier];
    [fileItem invalidate]; // Unpublishes the file's metadata
}

- (void)beginLocalDeletionOfFileItem:(OFXFileItem *)fileItem;
{
    OBPRECONDITION(fileItem.localState.deleted); // We can't ask for the localRelativePath of a file item, which is why we pass it in here.
    
    // Deleted items don't like to be asked the mundane -localRelativePath.
    NSString *localRelativePath = fileItem.requestedLocalRelativePath;
    
    _forgetItemByLocalRelativePath(self, fileItem, localRelativePath);
    
    DEBUG_LOCAL_RELATIVE_PATH(1, @"Deleted %@", [fileItem shortDescription]);
}

#ifdef OMNI_ASSERTIONS_ON
- (BOOL)hasBegunLocalDeletionOfFileItem:(OFXFileItem *)fileItem;
{
    OBPRECONDITION(fileItem.localState.deleted); // We can't ask for the localRelativePath of a file item, which is why we pass it in here.

    if (_documentIdentifierToFileItem[fileItem.identifier] != fileItem) {
        OBASSERT_NOT_REACHED("Who is this item?"); // should still be known by identifier
        return NO;
    }
    
    // Deleted items don't like to be asked the mundane -localRelativePath.
    NSString *localRelativePath = fileItem.requestedLocalRelativePath;
    
    NSArray *fileItems = _localRelativePathToFileItems[localRelativePath];
    return ![fileItems containsObject:fileItem]; // but should not be known by path
}
#endif

- (void)completeLocalDeletionOfFileItem:(OFXFileItem *)fileItem;
{
    OBPRECONDITION([self hasBegunLocalDeletionOfFileItem:fileItem], @"Can't finish something you don't start");
    
    // No coming back now!
    [_documentIdentifierToFileItem removeObjectForKey:fileItem.identifier];
    [fileItem invalidate];
}

- (void)fileItemMoved:(OFXFileItem *)fileItem fromLocalRelativePath:(NSString *)oldRelativePath toLocalRelativePath:(NSString *)newRelativePath;
{
    OBPRECONDITION([fileItem.localRelativePath isEqual:newRelativePath], @"Should be called after the move is noted in the file item");
    OBPRECONDITION(OFNOTEQUAL(oldRelativePath, newRelativePath), @"Not really moving.");
    OBASSERT_NOTNULL(oldRelativePath);
    OBASSERT_NOTNULL(newRelativePath);
    
    _registerFileItemByLocalRelativePath(self, fileItem, newRelativePath);
    _forgetItemByLocalRelativePath(self, fileItem, oldRelativePath);
    
    DEBUG_LOCAL_RELATIVE_PATH(1, @"Move %@ from %@ to %@", [fileItem shortDescription], oldRelativePath, newRelativePath);
    
    OBPOSTCONDITION([self _checkInvariants]);
}

- (void)invalidate;
{
    [_documentIdentifierToFileItem enumerateKeysAndObjectsUsingBlock:^(NSString *identifier, OFXFileItem *fileItem, BOOL *stop){
        [fileItem invalidate];
    }];
    _documentIdentifierToFileItem = nil;
    _localRelativePathToFileItems = nil;
}

#pragma mark - Debugging

- (NSString *)debugName;
{
    OFXContainerAgent *containerAgent = _weak_containerAgent;
    return containerAgent.debugName;
}

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *dict = [super debugDictionary];
    
    dict[@"_documentIdentifierToFileItem"] = [_documentIdentifierToFileItem copy];
    
    return dict;
}

#ifdef OMNI_ASSERTIONS_ON
- (BOOL)_checkInvariants;
{
    // In progress delete notes are not in _localRelativePathToFileItem
    OBINVARIANT([_localRelativePathToFileItems count] <= [_documentIdentifierToFileItem count]);
    
    [_localRelativePathToFileItems enumerateKeysAndObjectsUsingBlock:^(NSString *localRelativePath, NSArray *fileItems, BOOL *stop) {
        NSUInteger publishedCount = 0;
        for (OFXFileItem *fileItem in fileItems) {
            OBINVARIANT(OFISEQUAL(localRelativePath, fileItem.localRelativePath));
            if (_isPublished(fileItem))
                publishedCount++;
        }
        
        OBINVARIANT(publishedCount <= 1, @"If we have multiple files wanting to be at a local path, only one of them can be present.");
    }];
    
    [_documentIdentifierToFileItem enumerateKeysAndObjectsUsingBlock:^(NSString *identifier, OFXFileItem *fileItem, BOOL *stop) {
        OBINVARIANT(OFISEQUAL(identifier, fileItem.identifier));
        
        // _localRelativePathToFileItem doesn't have entries for delete notes, but should for everything else.
        if (fileItem.localState.deleted) {
            [_localRelativePathToFileItems enumerateKeysAndObjectsUsingBlock:^(NSString *localRelativePath, NSArray *fileItems, BOOL *stop) {
                OBINVARIANT([fileItems indexOfObject:fileItem] == NSNotFound);
            }];
        } else {
            OBINVARIANT([_localRelativePathToFileItems[fileItem.localRelativePath] containsObject:fileItem]);
        }
    }];
    
    return YES;
}
#endif

@end
