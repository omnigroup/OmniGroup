// Copyright 2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFXDownloadFileSnapshot.h"

#import <OmniFileStore/OFSDAVFileManager.h>
#import <OmniFileStore/OFSFileInfo.h>
#import <OmniFileStore/OFSURL.h>
#import <OmniFoundation/CFPropertyList-OFExtensions.h>

#import "OFXFileSnapshotContentsActions.h"
#import "OFXFileSnapshot-Internal.h"
#import "OFXFileState.h"
#import "OFXFileSnapshotRemoteEncoding.h"

RCS_ID("$Id$")

@implementation OFXDownloadFileSnapshot

// For DEBUG_TRANSFER ... lame, but better that the instance methods log something at least.
+ (NSString *)debugName;
{
    return @"";
}

// Downloads the info about the snapshot from the server and writes it to a local snapshot, which is expected to be in a temporary location.
+ (BOOL)writeSnapshotToTemporaryURL:(NSURL *)temporaryLocalSnapshotURL byFetchingMetadataOfRemoteSnapshotAtURL:(NSURL *)remoteSnapshotURL fileIdentifier:(NSString **)outFileIdentifier fileManager:(OFSDAVFileManager *)fileManager error:(NSError **)outError;
{
    OBPRECONDITION(temporaryLocalSnapshotURL);
    OBPRECONDITION(fileManager);
    OBPRECONDITION([temporaryLocalSnapshotURL checkResourceIsReachableAndReturnError:NULL] == NO); // we create this
    OBPRECONDITION(OFSURLIsStandardized([temporaryLocalSnapshotURL URLByDeletingLastPathComponent])); // make sure the eventual path is standardized
    

    DEBUG_TRANSFER(1, @"Making new snapshot at %@ by downloading metadata from %@", temporaryLocalSnapshotURL, remoteSnapshotURL);
        
    NSUInteger version;
    NSString *fileIdentifier = OFXFileItemIdentifierFromRemoteSnapshotURL(remoteSnapshotURL, &version, outError);
    if (!fileIdentifier) {
        OBChainError(outError);
        return NO;
    }
    
    // Grab the manifest property list. No need to do any ETag predication since the remote document's URL has a content-based hash.
    NSURL *infoURL = [remoteSnapshotURL URLByAppendingPathComponent:@"Info.plist" isDirectory:NO];
    
    NSData *infoData = [fileManager dataWithContentsOfURL:infoURL error:outError];
    if (!infoData) {
        // Document modified/removed while we were attempting to download it?
        OBChainError(outError);
        return NO;
    }
    
    // Validate that Info.plist is actually a plist. But we don't validate that it has the right structure. The caller is expected to do this by loading the results into a OFXFileSnapshot instance from the temporary location.
    NSDictionary *infoDictionary = [NSPropertyListSerialization propertyListWithData:infoData options:0 format:NULL error:outError];
    if (!infoDictionary) {
        OBChainError(outError);
        return NO;
    }
    
    // Prepare a local snapshot in a temporary location
    if (![[NSFileManager defaultManager] createDirectoryAtURL:temporaryLocalSnapshotURL withIntermediateDirectories:NO attributes:nil error:outError]) {
        OBChainError(outError);
        return NO;
    }
    DEBUG_TRANSFER(1, @"  Building local temporary snapshot at %@", temporaryLocalSnapshotURL);
    
    NSMutableDictionary *versionDictionary = [NSMutableDictionary new];
    versionDictionary[kOFXVersion_ArchiveVersionKey] = @(kOFXVersion_ArchiveVersion);
    versionDictionary[kOFXVersion_NumberKey] = @(version);
    
    // This temporary snapshot is always "new" (no contents).
    versionDictionary[kOFXVersion_LocalState] = [OFXFileState missing].archiveString;
    versionDictionary[kOFXVersion_RemoteState] = [OFXFileState normal].archiveString;
    
    // No kOFXVersion_ContentsKey key since the item isn't downloaded.
        
    if (!OFWriteNSPropertyListToURL(versionDictionary, [temporaryLocalSnapshotURL URLByAppendingPathComponent:kOFXVersionFileName], outError)) {
        [[NSFileManager defaultManager] removeItemAtURL:temporaryLocalSnapshotURL error:NULL];
        OBChainError(outError);
        return NO;
    }
    
    if (!OFWriteNSPropertyListToURL(infoDictionary, [temporaryLocalSnapshotURL URLByAppendingPathComponent:kOFXLocalInfoFileName], outError)) {
        [[NSFileManager defaultManager] removeItemAtURL:temporaryLocalSnapshotURL error:NULL];
        OBChainError(outError);
        return NO;
    }
        
    if (outFileIdentifier)
        *outFileIdentifier = fileIdentifier;
    return YES;
}

- (BOOL)makeDownloadStructureAt:(NSURL *)temporaryDocumentURL error:(NSError **)outError withFileApplier:(void (^)(NSURL *fileURL, long long fileSize, NSString *hash))fileApplier;
{
    OBPRECONDITION([self _checkInvariants]);
    OBPRECONDITION(temporaryDocumentURL);
    OBPRECONDITION(![temporaryDocumentURL checkResourceIsReachableAndReturnError:NULL]); // We'll create this
        
    OFXFileSnapshotContentsActions *downloadActions = [OFXFileSnapshotContentsActions new];
    downloadActions[kOFXContents_FileTypeDirectory] = ^BOOL(NSURL *actionURL, NSDictionary *contents, NSError **actionError){
        return [[NSFileManager defaultManager] createDirectoryAtURL:actionURL withIntermediateDirectories:NO attributes:nil error:actionError];
    };
    downloadActions[kOFXContents_FileTypeRegular] = ^BOOL(NSURL *actionURL, NSDictionary *contents, NSError **actionError){
        NSString *hash = contents[kOFXContents_FileHashKey];
        unsigned long long fileSize = [contents[kOFXContents_FileSizeKey] unsignedLongLongValue];
        fileApplier(actionURL, fileSize, hash);
        return YES;
    };
    downloadActions[kOFXContents_FileTypeLink] = ^BOOL(NSURL *actionURL, NSDictionary *contents, NSError **actionError){
        NSString *destination = contents[kOFXContents_LinkDestinationKey];
        return [[NSFileManager defaultManager] createSymbolicLinkAtPath:[[actionURL absoluteURL] path] withDestinationPath:destination error:actionError];
    };
    
    NSDictionary *contents = self.infoDictionary[kOFXInfo_ContentsKey];
    OBASSERT(contents);
    
    BOOL success = [downloadActions applyToContents:contents localContentsURL:temporaryDocumentURL error:outError];
    OBPOSTCONDITION([self _checkInvariants]);
    return success;
}

// Downloads the contents for the snapshot to the specified location (which is assumed to be somewhere temporary).
- (BOOL)downloadFromRemoteDocumentURL:(NSURL *)remoteDocumentURL toTemporaryDocumentURL:(NSURL *)temporaryDocumentURL withPreviousSnapshot:(OFXFileSnapshot *)previousSnapshot fileManager:(OFSFileManager *)fileManager error:(NSError **)outError;
{
    
    return [self finishedDownloadingToURL:temporaryDocumentURL error:outError];
}

- (BOOL)finishedDownloadingToURL:(NSURL *)temporaryDocumentURL error:(NSError **)outError;
{
    // Update the downloaded snapshot's dates, unless the top level item is a symlink (which will fail).
    if (!self.symbolicLink) {
        NSDictionary *fileDateAttributes = @{NSFileCreationDate:self.userCreationDate, NSFileModificationDate:self.userModificationDate};
        __autoreleasing NSError *setDatesError = nil;
        if (![[NSFileManager defaultManager] setAttributes:fileDateAttributes ofItemAtPath:[temporaryDocumentURL path] error:&setDatesError]) {
            // If we can't preserve the file's dates for some reason, it's not the end of the world--just log a warning and continue
            NSLog(@"Warning: Unable to set dates on downloaded file at %@: %@: %@ (fileDateAttributes=%@)", temporaryDocumentURL, [setDatesError localizedDescription], [setDatesError localizedRecoverySuggestion], fileDateAttributes);
        }
    }

    // Mark the snapshot as fully downloaded, both in the Version.plist (for the next launch) and in our local cached state.
    NSMutableDictionary *versionDictionary = [self.versionDictionary mutableCopy];
    NSMutableDictionary *versionContents = [NSMutableDictionary new];
    versionDictionary[kOFXVersion_ContentsKey] = versionContents;
    
    // This Contents dictionary is pointless -- this isn't the published document and we currently copy this to make the published document (so it'd have different inodes
    // Don't need a file coordinator here since the contents are still in our private area
    if (!OFXFileItemRecordContents(OFXVersionContentsType, versionContents, temporaryDocumentURL, outError)) {
        OBChainError(outError);
        OBPOSTCONDITION([self _checkInvariants]);
        return NO;
    }
    
    NSString *normal = [OFXFileState normal].archiveString;
    versionDictionary[kOFXVersion_LocalState] = normal;
    versionDictionary[kOFXVersion_RemoteState] = normal;
    
    if (![self _updateVersionDictionary:versionDictionary error:outError]) {
        OBChainError(outError);
        return NO;
    }
    
    OBPOSTCONDITION([self _checkInvariants]);
    return YES;
}

@end
