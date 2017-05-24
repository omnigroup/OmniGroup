// Copyright 2013-2014,2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFXContainerDocumentIndex.h"

#import "OFXFileItem.h"
#import "OFXContainerAgent.h"
#import "OFXFileSnapshotRemoteEncoding.h"

RCS_ID("$Id$")

@implementation OFXContainerDocumentIndex
{
    __weak OFXContainerAgent *_weak_containerAgent;
    
    /*
     Maps the uuid of documents inside Snapshots (which is a flat directory of uuid folders) to the user visible Documents directory.
     Locally deleted documents will only appear in the _documentIdentifierToFileItem (since they don't have a local path).
     
     In the case that multiple server-side documents want to claim the same relative path, we'll have local automatic moves (which aren't published to the server), so we'll still have a to-one mapping from the local relative path to the file item.
     
     A further wrinkle in all this is that we want be wary of case sensitivity in local relative paths since some filesystems are case sensitive (iOS device) and others aren't (Mac and iOS Simulator). Not only can this happen in the filename of the document itself, but in the containing folders ("foo/A.ext" vs "Foo/A.ext").
     
     An important case to test is when we have a published document with local edits and a new document comes in desiring that path from the server. We need the local document with edits to not lose its contents in favor of the new document (unless we generate a new conflict document from them).
     */
    NSMutableDictionary <NSString *, OFXFileItem *> *_documentIdentifierToFileItem;
    NSMutableDictionary <NSString *, OFXFileItem *> *_localRelativePathToFileItem;
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
    _localRelativePathToFileItem = [NSMutableDictionary new];
    
    return self;
}

- (NSMutableSet <NSString *> *)copyRegisteredFileItemIdentifiers;
{
    return [_documentIdentifierToFileItem mutableCopyKeySet];
}

- (NSMutableDictionary <NSString *, OFXFileItem *> *)copyLocalRelativePathToFileItem;
{
    return [_localRelativePathToFileItem mutableCopy];
}

#ifdef OMNI_ASSERTIONS_ON
- (NSObject <NSCopying> *)copyIndexState;
{
    NSDictionary *documentIdentifierToFileItem = [_documentIdentifierToFileItem copy];
    NSDictionary *localRelativePathToFileItem = [_localRelativePathToFileItem copy];
    return [NSArray arrayWithObjects:documentIdentifierToFileItem, localRelativePathToFileItem, nil];
}
#endif

- (OFXFileItem *)fileItemWithIdentifier:(NSString *)identifier;
{
    OBPRECONDITION([identifier containsString:OFXRemoteFileIdentifierToVersionSeparator] == NO, @"Should not contain our separator");
    
    OFXFileItem *fileItem = _documentIdentifierToFileItem[identifier];
    OBASSERT(!fileItem || [fileItem.identifier isEqual:identifier]);
    return fileItem;
}

- (OFXFileItem *)fileItemWithLocalRelativePath:(NSString *)localRelativePath;
{
    return _localRelativePathToFileItem[localRelativePath];
}

- (void)enumerateFileItems:(void (^)(NSString *identifier, OFXFileItem *fileItem))block;
{
    [_documentIdentifierToFileItem enumerateKeysAndObjectsUsingBlock:^(NSString *identifier, OFXFileItem *fileItem, BOOL *stop) {
        block(identifier, fileItem);
    }];
}

- (NSDictionary <NSString *, NSArray <OFXFileItem *> *> *)copyIntendedLocalRelativePathToFileItems;
{
    NSMutableDictionary <NSString *, NSMutableArray <OFXFileItem *> *> *results = [[NSMutableDictionary alloc] init];
    
    // _localRelativePathToFileItem has the actual path, not the desired path.
    // TODO: Make our own cache here? Would have to ensure it is up to date when an incoming name change happens or user initiated (attempted) name change happens.
    
    [_documentIdentifierToFileItem enumerateKeysAndObjectsUsingBlock:^(NSString *identifier, OFXFileItem *fileItem, BOOL *stop) {
        if (fileItem.localState.deleted)
            return; // No local path. Not enumerating _localRelativePathToFileItem since we want the intended path, not the actual current (possibly auto-moved) path.
        
        NSString *path = fileItem.intendedLocalRelativePath;
        NSMutableArray <OFXFileItem *> *fileItems = results[path];
        if (!fileItems) {
            fileItems = [[NSMutableArray alloc] initWithObjects:fileItem, nil];
            results[path] = fileItems;
        } else {
            [fileItems addObject:fileItem];
        }
    }];
    
    DEBUG_LOCAL_RELATIVE_PATH(1, @"Copy intended local relative path to file items %@", results);
    return [results copy];
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

    OBPOSTCONDITION([self _checkInvariants]);
}

// Just does the local relative path.
static void _registerFileItemByLocalRelativePath(OFXContainerDocumentIndex *self, OFXFileItem *fileItem, NSString *localRelativePath)
{
    OBPRECONDITION(self->_localRelativePathToFileItem[localRelativePath] == nil, "Must move aside old file item first");
    self->_localRelativePathToFileItem[localRelativePath] = fileItem;
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

    OBPOSTCONDITION([self _checkInvariants]);
}

- (void)registerLocallyAppearingFileItem:(OFXFileItem *)fileItem;
{
    OBPRECONDITION(fileItem.remoteState.missing);
    
    // Actually, this can happen if there is a remotely existing file that we've found out about but not downloaded. So, we can find the local file while the remote file is still downloading (or it might not be downloading at all if it is too big or auto-downloading is off).
    // TJW 20140204: Reinstating this for the moment since the explanation above doesn't make sense to me now...
    OBPRECONDITION(_localRelativePathToFileItem[fileItem.localRelativePath] == nil, @"A file can't be newly appearing in the local filesystem unless nothing was there before");

    _registerFileItem(self, fileItem);
    DEBUG_LOCAL_RELATIVE_PATH(1, @"New local document %@ -> %@", fileItem.localRelativePath, [fileItem shortDescription]);

    OBPOSTCONDITION([self _checkInvariants]);
}

// This is to detect folder renames. If we have two items requesting that they by "foo/A.ext", and we rename "foo" to "bar", we want both file items to move along too.
- (void)addFileItems:(NSMutableArray <OFXFileItem *> *)resultFileItems inDirectoryWithRelativePath:(NSString *)localDirectoryRelativePath;
{
    OBPRECONDITION([localDirectoryRelativePath hasSuffix:@"/"]);
    
    [_localRelativePathToFileItem enumerateKeysAndObjectsUsingBlock:^(NSString *localRelativePath, OFXFileItem *fileItem, BOOL *stop) {
        // TEST CASE: Do a case-insensitive prefix check here?
        if ([localRelativePath hasPrefix:localDirectoryRelativePath])
            [resultFileItems addObject:fileItem];
    }];

    OBPOSTCONDITION([self _checkInvariants]);
}

static void _forgetItemByLocalRelativePath(OFXContainerDocumentIndex *self, OFXFileItem *fileItem, NSString *localRelativePath)
{
    OBPRECONDITION(self->_localRelativePathToFileItem[localRelativePath] == fileItem);
    [self->_localRelativePathToFileItem removeObjectForKey:localRelativePath];
}

- (void)forgetFileItemForRemoteDeletion:(OFXFileItem *)fileItem;
{
    DEBUG_LOCAL_RELATIVE_PATH(1, @"Forgetting file item %@", [fileItem shortDescription]);
    
    _forgetItemByLocalRelativePath(self, fileItem, fileItem.localRelativePath);
    
    [_documentIdentifierToFileItem removeObjectForKey:fileItem.identifier];
    
    OBPOSTCONDITION([self _checkInvariants]);
}

- (void)beginLocalDeletionOfFileItem:(OFXFileItem *)fileItem;
{
    OBPRECONDITION(fileItem.localState.deleted); // We can't ask for the localRelativePath of a file item, which is why we pass it in here.
    
    // Deleted items don't like to be asked the mundane -localRelativePath.
    NSString *localRelativePath = fileItem.requestedLocalRelativePath;
    
    _forgetItemByLocalRelativePath(self, fileItem, localRelativePath);
    
    DEBUG_LOCAL_RELATIVE_PATH(1, @"Deleted %@", [fileItem shortDescription]);
    OBPOSTCONDITION([self _checkInvariants]);
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
    
    OFXFileItem *registeredFileItem = _localRelativePathToFileItem[localRelativePath];

    OBPOSTCONDITION([self _checkInvariants]);
    return registeredFileItem != fileItem; // but should not be known by path
}
#endif

- (void)completeLocalDeletionOfFileItem:(OFXFileItem *)fileItem;
{
    OBPRECONDITION([self hasBegunLocalDeletionOfFileItem:fileItem], @"Can't finish something you don't start");
    
    // No coming back now!
    [_documentIdentifierToFileItem removeObjectForKey:fileItem.identifier];

    OBPOSTCONDITION([self _checkInvariants]);
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

// Bulk by-user move
- (void)fileItemsMoved:(NSArray <OFXContainerDocumentIndexMove *> *)moves; // Bulk move; array of OFXContainerDocumentIndexMove instances
{
    // De-register all the moving items (so we can deal with swapping moves).
    for (OFXContainerDocumentIndexMove *move in moves) {
        OFXFileItem *fileItem = move.fileItem;
        NSString *originalRelativePath = move.originalRelativePath;
#ifdef OMNI_ASSERTIONS_ON
        NSString *updatedRelativePath = move.updatedRelativePath;
#endif
        
        OBASSERT([fileItem.localRelativePath isEqual:updatedRelativePath], @"Should be called after the move is noted in the file item");
        OBASSERT(OFNOTEQUAL(originalRelativePath, updatedRelativePath), @"Not really moving.");
        OBASSERT_NOTNULL(originalRelativePath);
#ifdef OMNI_ASSERTIONS_ON
        OBASSERT_NOTNULL(updatedRelativePath);
#endif
        
        _forgetItemByLocalRelativePath(self, fileItem, originalRelativePath);
        
        DEBUG_LOCAL_RELATIVE_PATH(1, @"Move %@", [move shortDescription]);
    }

    // Re-register all the moved items under their new paths.
    for (OFXContainerDocumentIndexMove *move in moves)
        _registerFileItemByLocalRelativePath(self, move.fileItem, move.updatedRelativePath);
    
    OBPOSTCONDITION([self _checkInvariants]);
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
    OBINVARIANT([_localRelativePathToFileItem count] <= [_documentIdentifierToFileItem count]);
    
    NSMutableSet *inodes = [NSMutableSet set];
    [_localRelativePathToFileItem enumerateKeysAndObjectsUsingBlock:^(NSString *localRelativePath, OFXFileItem *fileItem, BOOL *stop) {
        OBINVARIANT(OFISEQUAL(localRelativePath, fileItem.localRelativePath));
        
        if (fileItem.localState.missing)
            OBINVARIANT(fileItem.inode == nil, "Missing files aren't on disk and don't have an inode");
        else {
            OBINVARIANT([inodes member:fileItem.inode] == nil, "Each file item should have a unique inode");
            [inodes addObject:fileItem.inode];
        }
    }];
    
    [_documentIdentifierToFileItem enumerateKeysAndObjectsUsingBlock:^(NSString *identifier, OFXFileItem *fileItem, BOOL *stop) {
        OBINVARIANT(OFISEQUAL(identifier, fileItem.identifier));
        
        // _localRelativePathToFileItem doesn't have entries for delete notes, but should for everything else.
        if (fileItem.localState.deleted) {
            OBINVARIANT([_localRelativePathToFileItem keyForObjectEqualTo:fileItem] == nil);
        } else {
            OBINVARIANT(_localRelativePathToFileItem[fileItem.localRelativePath] == fileItem);
        }
    }];
    
    return YES;
}
#endif

@end

@implementation OFXContainerDocumentIndexMove

- (NSString *)shortDescription;
{
    return [NSString stringWithFormat:@"%@ %@ -> %@", [_fileItem shortDescription], _originalRelativePath, _updatedRelativePath];
}

@end
