// Copyright 2013-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFXUploadContentsFileSnapshot.h"

#import <OmniFoundation/NSFileManager-OFTemporaryPath.h>
#import <OmniFoundation/NSFileCoordinator-OFExtensions.h>

#import "OFXFileSnapshot-Internal.h"
#import "OFXFileState.h"
#import "OFXFileSnapshotContentsActions.h"

RCS_ID("$Id$")

@implementation OFXUploadContentsFileSnapshot
{
    // The temporary copy of the document.
    NSURL *_documentVersionContentsURL;
}

- (instancetype)initWithTargetLocalSnapshotURL:(NSURL *)localTargetURL forUploadingVersionOfDocumentAtURL:(NSURL *)localDocumentURL localRelativePath:(NSString *)localRelativePath previousSnapshot:(OFXFileSnapshot *)previousSnapshot error:(NSError **)outError;
{
    OBPRECONDITION(localDocumentURL);
    OBPRECONDITION([[[localDocumentURL absoluteURL] path] hasSuffix:([NSString stringWithFormat:@"/%@", localRelativePath])]);
    OBPRECONDITION(previousSnapshot);
    OBPRECONDITION(previousSnapshot.remoteState.missing || previousSnapshot.localState.edited || previousSnapshot.localState.userMoved);
    OBPRECONDITION(!previousSnapshot.localState.missing || (!previousSnapshot.localState.edited && previousSnapshot.localState.userMoved), @"Should only upload a missing snapshot if the thing we are doing is a rename");

    if (!(self = [self _initTemporarySnapshotWithTargetLocalSnapshotURL:localTargetURL localRelativePath:localRelativePath error:outError]))
        return nil;

    // Make a consistent copy of the document. We don't bother to grab the contents until we are actually going to upload since quick edits might get coalesced (and we might be offline when the document is edited).
    {
        __autoreleasing NSError *error;
        _documentVersionContentsURL = [[NSFileManager defaultManager] temporaryURLForWritingToURL:localDocumentURL allowOriginalDirectory:NO error:&error];
        if (!_documentVersionContentsURL) {
            NSLog(@"Error getting temporary URL to make a copy of document for uploading %@: %@", localDocumentURL, [error toPropertyList]);
            [[NSFileManager defaultManager] removeItemAtURL:self.localSnapshotURL error:NULL]; // We are still in a temporary location
            if (outError)
                *outError = error;
            return nil;
        }
    }
    NSMutableDictionary *versionContents = [NSMutableDictionary new];
    __block NSDate *modificationDate;
    {
        __autoreleasing NSError *coordinatedReadError = nil;
        
        // We pass NSFileCoordinatorReadingWithoutChanges to avoid triggering autosave. We want to let editors save at their own rate (though this might mean we'll need to upload again when we wouldn't have to otherwise).
        NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
        
        BOOL success = [coordinator readItemAtURL:localDocumentURL withChanges:NO error:&coordinatedReadError byAccessor:^BOOL(NSURL *newReadingURL, NSError **outCoordinatorError){
            // This should mostly be OK, but we'll maybe get a different contents recorded by OFXFileItemRecordContents() below if this happens and if NSFileCoordinator doesn't preserve inodes at the eventual end state. In this case, once our upload finishes, we'll notice that our document has different inodes and so might have changed. If this happens too often, it will be terrible, but hopefully this should be a rare occurrence if at all.
            // NOTE: I've seen this happen in one case -- case-only renames. In this case if we have renamed "foo" to "Foo" and pass in "Foo" to NSFileCoordinator, it can hand back "foo". Perhaps if we wait a bit before starting uploads to let the file coordination system simmer down, it would flush out its notes about in-flight renames. Note this doesn't happen for other renames like "foo" to "bar", so this may be something specific to their case-insensitivity code or our rename extension in NSFileCoordinator(OFExtensions) that attempts to paper over them.
            // UPDATE: Have also seen this on other very quick moves (we do this for our case-only rename support), but -testMultipleQuickRenamesOfFlatFile hits it too.
            // If this would have failed, we'll bail with the 'cancel' case below and will retry later (possibly coalescing renames).
            // OBASSERT([newReadingURL isEqual:localDocumentURL], "Handle file coordination passing a new URL (passed %@, but got back %@)", localDocumentURL, newReadingURL);
            
            __autoreleasing NSError *copyError;
            if (![[NSFileManager defaultManager] copyItemAtURL:newReadingURL toURL:_documentVersionContentsURL error:&copyError]) {
                // If the file is quickly added and then removed before we can upload it, we should just bail.
                if ([copyError hasUnderlyingErrorDomain:NSPOSIXErrorDomain code:ENOENT]) {
                    DEBUG_TRANSFER(1, @"Local document disappeared before it could be uploaded %@", localDocumentURL);
                    if (outCoordinatorError)
                        *outCoordinatorError = [NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError userInfo:nil];
                } else {
                    [copyError log:@"Error copying contents from %@ to new snapshot at %@", newReadingURL, _documentVersionContentsURL];
                    if (outCoordinatorError)
                        *outCoordinatorError = copyError;
                }
                return NO;
            }

            // Wait until we have a coordinate read dgoing on this and we are sure the URL exists (since OFURLIsStandardized requires it and the file might go missing before we get around to  uploading).
            // NOTE: We pass newReadingURL here since quick renames can substitute the eventual URL if another local move has already happened.
            OBASSERT(previousSnapshot.localState.missing || OFURLIsStandardized(newReadingURL), @"URL should be standardized if the document has been downloaded");

            // Grab the modification date of the original URL. We don't want the current time since we might have modified the file while off line a long time ago and just now be connected and uploading it.
            __autoreleasing NSError *attributesError;
            NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:[newReadingURL path] error:&attributesError];
            if (!attributes) {
                OBASSERT_NOT_REACHED("shouldn't fail since we just copied this URL, but maybe someone is doing uncoordinated file access");
                [attributesError log:@"Error getting attributes of %@", newReadingURL];
                if (outCoordinatorError)
                    *outCoordinatorError = attributesError;
                return NO;
            }
            modificationDate = attributes.fileModificationDate;
            
            // Read the information about the version of the document we are uploading (including the inodes and modification dates). We can't record this on the copy, but must do it on the original or we can't validate whether the original has changed.
            __autoreleasing NSError *childError;
            if (!OFXFileItemRecordContents(OFXVersionContentsType, versionContents, newReadingURL, &childError)) {
                if (outCoordinatorError)
                    *outCoordinatorError = childError;
                return NO;
            }
            
            return YES;
        }];
        
        if (!success) {
            [coordinatedReadError log:@"Snapshot failed for %@", localDocumentURL];
            
            // Clean up our temporary copy
            __autoreleasing NSError *removeError = nil;
            if (![[NSFileManager defaultManager] removeItemAtURL:_documentVersionContentsURL error:&removeError]) {
                if ([removeError causedByMissingFile]) {
                    // The copy we were trying to make never got created.
                } else {
                    [removeError log:@"Error deleting document version snapshot at %@", _documentVersionContentsURL];
                }
            }

            _documentVersionContentsURL = nil;
            
            [[NSFileManager defaultManager] removeItemAtURL:self.localSnapshotURL error:NULL]; // We are still in a temporary location

            if (outError)
                *outError = coordinatedReadError;
            OBChainError(outError);
            return nil;
        }
        
    }
    
    // Record the info about the snapshot we just made and the fact that it isn't uploaded yet.
    NSMutableDictionary *versionDictionary = [NSMutableDictionary new];
    versionDictionary[kOFXVersion_ArchiveVersionKey] = @(kOFXVersion_ArchiveVersion);
    
    // The ETag/editIdentifier are for the uploaded version -- we mark ourselves as edited (since our contents will now match the published document).
    OFXFileState *localState = previousSnapshot.localState;
    OFXFileState *remoteState = previousSnapshot.remoteState;
    
    if (localState.userMoved || localState.autoMoved) {
        // We might be a new conflict version at "foo (conflict from bar).ext" and really want to be at "foo.ext".
        versionDictionary[kOFXVersion_RelativePath] = previousSnapshot.localRelativePath;
    }
    
    versionDictionary[kOFXVersion_LocalState] = localState.archiveString;
    versionDictionary[kOFXVersion_RemoteState] = remoteState.archiveString;
    versionDictionary[kOFXVersion_ContentsKey] = versionContents;
    
    if (previousSnapshot.remoteState.missing)
        versionDictionary[kOFXVersion_NumberKey] = @(0);
    else
        versionDictionary[kOFXVersion_NumberKey] = @(previousSnapshot.version + 1);

    // Build the Info.plist
    NSMutableDictionary *infoDictionary = [NSMutableDictionary dictionary];
    infoDictionary[kOFXInfo_ArchiveVersionKey] = @(kOFXInfo_ArchiveVersion);
    
    if (localState.autoMoved)
        infoDictionary[kOFXInfo_PathKey] = previousSnapshot.intendedLocalRelativePath;
    else
        infoDictionary[kOFXInfo_PathKey] = localRelativePath;
    
    OBASSERT(modificationDate);
    if (!modificationDate)
        modificationDate = [NSDate date];
    NSString *modificationDateString = [modificationDate xmlString];
    NSString *creationDateString = previousSnapshot.infoDictionary[kOFXInfo_CreationDateKey];
    if (!creationDateString) {
        OBASSERT_NOT_REACHED("Previous snapshot should have a creation date");
        creationDateString = modificationDateString;
    }
    infoDictionary[kOFXInfo_CreationDateKey] = creationDateString;
    infoDictionary[kOFXInfo_ModificationDateKey] = modificationDateString;
    
    NSMutableDictionary *contents = [NSMutableDictionary dictionary];
    infoDictionary[kOFXInfo_ContentsKey] = contents;
    
    __autoreleasing NSError *error = nil;
    if (!OFXFileItemRecordContents(OFXInfoContentsType, contents, _documentVersionContentsURL, &error)) {
        NSLog(@"Error recording file contents at %@: %@", _documentVersionContentsURL, [error toPropertyList]);

        // Clean up our temporary copy
        [[NSFileManager defaultManager] removeItemAtURL:_documentVersionContentsURL error:NULL];
        _documentVersionContentsURL = nil;
        
        [[NSFileManager defaultManager] removeItemAtURL:self.localSnapshotURL error:NULL]; // We are still in a temporary location

        if (outError)
            *outError = error;
        OBChainError(outError);
        return nil;
    }
    
    if (![self _updateVersionDictionary:versionDictionary reason:@"init upload contents" error:outError])
        return nil;
    if (![self _updateInfoDictionary:infoDictionary error:outError])
        return nil;
    
    OBPOSTCONDITION([self _checkInvariants]);
    return self;
}

- (void)dealloc;
{
    // We should have cleaned this up.
    OBASSERT(_documentVersionContentsURL == nil);
}

- (BOOL)iterateFiles:(NSError **)outError withApplier:(BOOL (^)(NSURL *fileURL, NSString *hash, NSError **outError))applier;
{
    OFXFileSnapshotContentsActions *uploadActions = [OFXFileSnapshotContentsActions new];
    uploadActions[kOFXContents_FileTypeRegular] = ^BOOL(NSURL *actionURL, NSDictionary *contents, NSError **actionError){
        // TODO: Avoid rewriting data we've already written. This is not terribly likely, but we could have a document with the same image attached multiple times. We could at least to a 'if not exists' precondition.
        NSString *hash = contents[kOFXContents_FileHashKey];
        return applier(actionURL, hash, actionError);
    };
    
    NSDictionary *infoDictionary = self.infoDictionary;
    NSDictionary *contents = infoDictionary[kOFXInfo_ContentsKey];
    OBASSERT(contents);
    
    if (![uploadActions applyToContents:contents localContentsURL:_documentVersionContentsURL error:outError]) {
        OBChainError(outError);
        OBPOSTCONDITION([self _checkInvariants]);
        return NO;
    }
    
    return YES;
}

- (void)removeTemporaryCopyOfDocument;
{
    // Clean up the temporary snapshot when we are done with it.
    if (_documentVersionContentsURL) {
        __autoreleasing NSError *removeError;
        if (![[NSFileManager defaultManager] removeItemAtURL:_documentVersionContentsURL error:&removeError]) {
            [removeError log:@"Error removing temporary copy of file made for uploading."];
        }
        _documentVersionContentsURL = nil;
    }
}

@end
