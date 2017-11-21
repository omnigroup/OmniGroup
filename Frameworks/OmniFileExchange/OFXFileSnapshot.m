// Copyright 2013-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFXFileSnapshot.h"

#import <OmniFoundation/CFPropertyList-OFExtensions.h>
#import <OmniFoundation/NSData-OFSignature.h>
#import <OmniFoundation/NSFileManager-OFTemporaryPath.h>
#import <OmniFoundation/NSFileCoordinator-OFExtensions.h>
#import <OmniFoundation/OFPreference.h>

#import "OFXFileSnapshot-Internal.h"
#import "OFXFileState.h"
#import "OFXFileSnapshotRemoteEncoding.h"
#import "OFXContentIdentifier.h"

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
#import <UIKit/UIDevice.h>
#endif

RCS_ID("$Id$")

OFDeclareDebugLogLevel(OFXSnapshotDebug);
#define DEBUG_SNAPSHOT(level, format, ...) do { \
    if (OFXSnapshotDebug >= (level)) \
        NSLog(@"SNAPSHOT %@: " format, [self shortDescription], ## __VA_ARGS__); \
    } while (0)


BOOL OFXFileItemRecordContents(OFXContentsType type, NSMutableDictionary *contents, NSURL *fileURL, NSError **outError)
{
    __autoreleasing NSError *error = nil;
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:[fileURL path] error:&error];
    if (!attributes) {
        if (outError)
            *outError = error;
        OBChainError(outError);
        return NO;
    }
        
    if (type == OFXVersionContentsType) {
        contents[kOFXContents_FileCreationTime] = @([attributes.fileCreationDate timeIntervalSinceReferenceDate]);
        contents[kOFXContents_FileModificationTime] = @([attributes.fileModificationDate timeIntervalSinceReferenceDate]);
        contents[kOFXContents_FileInode] = @(attributes.fileSystemFileNumber);
    }
    
    // Storing the contents as a tree means we can store empty directories easily. We might also want to store a reverse index of id->relativePath.
    NSString *fileType = attributes[NSFileType];
    if ([fileType isEqualToString:NSFileTypeDirectory]) {
        NSMutableDictionary *children = [NSMutableDictionary dictionary];
        contents[kOFXContents_FileTypeKey] = kOFXContents_FileTypeDirectory;
        contents[kOFXContents_DirectoryChildrenKey] = children;
        
        NSArray *childrenURLs = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:fileURL includingPropertiesForKeys:nil options:0 error:outError];
        if (!childrenURLs) {
            OFXError(outError, OFXAccountUnableToRecordFileContents, ([NSString stringWithFormat:@"Unable to get children of directory at %@", fileURL]), nil);
            return NO;
        }
        
        for (NSURL *childURL in childrenURLs) {
            NSString *name = [childURL lastPathComponent];
            NSMutableDictionary *childContents = [NSMutableDictionary dictionary];
            children[name] = childContents;
            
            if (!OFXFileItemRecordContents(type, childContents, childURL, outError)) {
                OBChainError(outError);
                return NO;
            }
        }
        
        return YES;
    } else if ([fileType isEqualToString:NSFileTypeRegular]) {
        contents[kOFXContents_FileTypeKey] = kOFXContents_FileTypeRegular;
        
        NSNumber *fileSize = @(attributes.fileSize);
        contents[@"Size"] = fileSize;
        
        NSData *fileData = [[NSData alloc] initWithContentsOfURL:fileURL options:NSDataReadingMappedIfSafe|NSDataReadingUncached error:outError];
        if (!fileData) {
            OFXError(outError, OFXAccountUnableToRecordFileContents, ([NSString stringWithFormat:@"Unable to read file at %@", fileURL]), nil);
            return NO;
        }
        
        if (type == OFXInfoContentsType) {
            contents[kOFXContents_FileHashKey] = OFXHashFileNameForData(fileData);
        } else if (type == OFXVersionContentsType) {
            // did everything above
        } else {
            OBASSERT_NOT_REACHED("Unknown contents type");
        }
        contents[kOFXContents_FileSizeKey] = @(fileData.length);
        
        return YES;
    } else if ([fileType isEqualToString:NSFileTypeSymbolicLink]) {
        contents[kOFXContents_FileTypeKey] = kOFXContents_FileTypeLink;
        
        NSString *destination = [[NSFileManager defaultManager] destinationOfSymbolicLinkAtPath:[fileURL path] error:outError];
        if (!destination) {
            OFXError(outError, OFXAccountUnableToRecordFileContents, ([NSString stringWithFormat:@"Unable to read link destination at %@", fileURL]), nil);
            return NO;
        }
        
        contents[kOFXContents_LinkDestinationKey] = destination;
        return YES;
    } else {
        OFXError(outError, OFXAccountUnableToRecordFileContents, ([NSString stringWithFormat:@"Unsupported file type %@ found at %@", fileType, fileURL]), nil);
        return NO;
    }
}

@implementation OFXFileSnapshot

static BOOL OFXValidateInfoDictionary(NSDictionary *infoDictionary, NSError **outError)
{
    if (![infoDictionary isKindOfClass:[NSDictionary class]]) {
        OFXError(outError, OFXSnapshotInfoCorrupt, ([NSString stringWithFormat:@"Info property list is not a dictionary but rather a %@", [infoDictionary class]]), nil);
        return NO;
    }
    
    if (![infoDictionary[kOFXInfo_ArchiveVersionKey] isEqual:@(kOFXInfo_ArchiveVersion)]) {
        // TODO: If we ever add a second storage format, we'll need to handle loading the old version.
        OFXError(outError, OFXSnapshotInfoCorrupt, ([NSString stringWithFormat:@"Info property list has unrecognized version number %@", infoDictionary[kOFXInfo_ArchiveVersionKey]]), nil);
        return NO;
    }

    if ([NSString isEmptyString:infoDictionary[kOFXInfo_PathKey]]) {
        OFXError(outError, OFXSnapshotInfoCorrupt, @"Info property list doesn't specify a local relative path", nil);
        return NO;
    }

    return YES;
}

static BOOL OFXRequireKey(NSDictionary *dict, NSString *key, Class cls, NSError **outError)
{
    id value = dict[key];
    if (![value isKindOfClass:cls]) {
        OFXError(outError, OFXSnapshotInfoCorrupt, ([NSString stringWithFormat:@"Property list has bad value for key %@: %@ (%@)", key, value, [value class]]), nil);
        OBASSERT_NOT_REACHED("Should not produce invalid info/version dictionaries.");
        return NO;
    }
    return YES;
}

static BOOL _OFXValidateVersionDictionary(NSDictionary *versionDictionary, NSError **outError)
{
    if (![versionDictionary isKindOfClass:[NSDictionary class]]) {
        OFXError(outError, OFXSnapshotInfoCorrupt, ([NSString stringWithFormat:@"Version property list is not a dictionary but rather a %@", [versionDictionary class]]), nil);
        return NO;
    }
    
    if (![versionDictionary[kOFXVersion_ArchiveVersionKey] isEqual:@(kOFXVersion_ArchiveVersion)]) {
        // TODO: If we ever add a second storage format, we'll need to handle loading the old version.
        NSString *message = [NSString stringWithFormat:@"Version property list has unrecognized version number %@", versionDictionary[kOFXVersion_ArchiveVersionKey]];
        OFXError(outError, OFXSnapshotInfoCorrupt, message, nil);
        return NO;
    }

    if (!OFXRequireKey(versionDictionary, kOFXVersion_LocalState, [NSString class], outError))
        return NO;
    if (!OFXRequireKey(versionDictionary, kOFXVersion_RemoteState, [NSString class], outError))
        return NO;
    
    OFXFileState *localState = [OFXFileState stateFromArchiveString:versionDictionary[kOFXVersion_LocalState]];
    OFXFileState *remoteState = [OFXFileState stateFromArchiveString:versionDictionary[kOFXVersion_RemoteState]];
    
    OBASSERT(remoteState.autoMoved == NO, "The server only has user intended moves");

    // If one side is missing, the other side can't be missing.
    if (localState.missing && remoteState.missing) {
        OFXError(outError, OFXSnapshotInfoCorrupt, ([NSString stringWithFormat:@"Version property list has invalid edits; both sides are missing: %@", versionDictionary]), nil);
        return NO;
    }

    if (!OFXRequireKey(versionDictionary, kOFXVersion_NumberKey, [NSNumber class], outError))
        return NO;
    NSNumber *versionNumber = versionDictionary[kOFXVersion_NumberKey];
    
    if (remoteState.missing && [versionNumber unsignedIntegerValue] != 0) {
        OFXError(outError, OFXSnapshotInfoCorrupt, ([NSString stringWithFormat:@"New local document should have version number 0, but has %@", versionDictionary]), nil);
        return NO;
    }
    
    if (localState.userMoved || localState.autoMoved) {
        if (!OFXRequireKey(versionDictionary, kOFXVersion_RelativePath, [NSString class], outError)) {
            OFXError(outError, OFXSnapshotInfoCorrupt, ([NSString stringWithFormat:@"Version property list is marked as moved, but no relative path specified %@", versionDictionary]), nil);
            return NO;
        }
    } else {
        if (versionDictionary[kOFXVersion_RelativePath]) {
            OFXError(outError, OFXSnapshotInfoCorrupt, ([NSString stringWithFormat:@"Version property list is not marked as moved, but has a relative path specified %@", versionDictionary]), nil);
            return NO;
        }
    }
    
    BOOL shouldHaveContents = YES;
    
    if (localState.missing || localState.deleted) {
        // Never downloaded or locally deleted
        shouldHaveContents = NO;
    }
    
    if (shouldHaveContents) {
        if (!OFXRequireKey(versionDictionary, kOFXVersion_ContentsKey, [NSDictionary class], outError))
            return NO;
    } else {
        if (versionDictionary[kOFXVersion_ContentsKey]) {
            OFXError(outError, OFXSnapshotInfoCorrupt, ([NSString stringWithFormat:@"Version property list has unexpected Contents key set %@", versionDictionary]), nil);
            return NO;
        }
    }

    return YES;
}

static BOOL OFXValidateVersionDictionary(NSDictionary *versionDictionary, NSError **outError)
{
    __autoreleasing NSError *error;
    if (!_OFXValidateVersionDictionary(versionDictionary, &error)) {
        NSLog(@"Version dictionary is not valid %@: %@", versionDictionary, [error toPropertyList]);
        OBASSERT_NOT_REACHED("Should not hit this -- hit breakpoint");
        if (outError)
            *outError = error;
        return NO;
    }
    return YES;
}

// We take a coordinator so that the higher level code can pass us one with the local file presenter for the containing account. Higher level operations may want dirty reads or not, so we take that too. Callers that pass NSFileCoordinatorReadingWithoutChanges should ensure they'll get called again if the document does actually change and provoke another scan/upload.
static NSDictionary *_recordVersionContents(NSURL *localDocumentURL, NSFileCoordinator *coordinator, BOOL withChanges, NSError **outError)
{
    OBPRECONDITION(localDocumentURL);
    
    NSMutableDictionary *versionContents = [NSMutableDictionary new];
    
    __autoreleasing NSError *error;
    
    BOOL success = [coordinator readItemAtURL:localDocumentURL withChanges:withChanges error:&error byAccessor:
     ^BOOL (NSURL *newReadingURL, NSError **outCoordinatorError) {
         // Read the information about the version of the document we are uploading (including the inodes and modification dates). We can't record this on the copy, but must do it on the original or we can't validate whether the original has changed.
         return OFXFileItemRecordContents(OFXVersionContentsType, versionContents, newReadingURL, outCoordinatorError);
     }];
    
    if (!success) {
        if (outError)
            *outError = error;
        return nil;
    }
    
    return [versionContents copy];
}

- (instancetype)initWithExistingLocalSnapshotURL:(NSURL *)localSnapshotURL error:(NSError **)outError;
{
    OBPRECONDITION(localSnapshotURL);
    OBPRECONDITION([localSnapshotURL checkResourceIsReachableAndReturnError:NULL]);
    OBPRECONDITION(OFURLIsStandardized(localSnapshotURL));

    if (!(self = [super init]))
        return nil;
    
    _localSnapshotURL = [localSnapshotURL copy];

    NSURL *infoURL = [localSnapshotURL URLByAppendingPathComponent:kOFXLocalInfoFileName];
    _infoDictionary = OFReadNSPropertyListFromURL(infoURL, outError);
    if (!_infoDictionary) {
        OFXError(outError, OFXAccountUnableToReadFileItem, @"Error loading Info.plist", nil);
        return nil;
    }
    
    if (!OFXValidateInfoDictionary(_infoDictionary, outError)) {
        OBChainError(outError);
        return nil;
    }
    
    _versionDictionary = [OFReadNSPropertyListFromURL([localSnapshotURL URLByAppendingPathComponent:kOFXVersionFileName], outError) copy];
    if (!_versionDictionary) {
        OFXError(outError, OFXAccountUnableToReadFileItem, @"Error loading Version.plist", nil);
        return nil;
    }
    if (!OFXValidateVersionDictionary(_versionDictionary, outError)) // Validate before looking at the contents of the dictionary
        return nil;

    // We are initialized enough for this method to work (since it reads from _versionDictionary).
    OFXFileState *localState = self.localState;

    // Local the updated relative path if we've been locally moved but haven't pushed the move yet.
    if (localState.userMoved || localState.autoMoved) {
        _localRelativePath = [_versionDictionary[kOFXVersion_RelativePath] copy];
        if (!_localRelativePath) {
            NSString *reason = [NSString stringWithFormat:@"Snapshot at %@ is marked as moved, but no relative path specified in Version.plist", localSnapshotURL];
            OFXError(outError, OFXAccountUnableToReadFileItem, @"Error loading snapshot.", reason);
            return nil;
        }
    } else
        _localRelativePath = [_infoDictionary[kOFXInfo_PathKey] copy];
    
    OBASSERT(![NSString isEmptyString:_localRelativePath]); // Checked in OFXValidateInfoDictionary;
    
    DEBUG_SNAPSHOT(1, @"Created from existing local snapshot at %@ %@/%@", localSnapshotURL, self.localState, self.remoteState);
    DEBUG_CONTENT(1, @"Created snapshot has content \"%@\"", OFXLookupDisplayNameForContentIdentifier(self.currentContentIdentifier));
    
    OBPOSTCONDITION([self _checkInvariants]);
    return self;
}

- _initTemporarySnapshotWithTargetLocalSnapshotURL:(NSURL *)localTargetURL localRelativePath:(NSString *)localRelativePath error:(NSError **)outError;
{
    // The parent directory should exist and be standardized, but the target might not.
    OBPRECONDITION([[localTargetURL URLByDeletingLastPathComponent] checkResourceIsReachableAndReturnError:NULL]);
    OBPRECONDITION(OFURLIsStandardized([localTargetURL URLByDeletingLastPathComponent]));
    OBPRECONDITION(![NSString isEmptyString:localRelativePath]);
    
    __autoreleasing NSError *error = nil;
    NSURL *snapshotURL = [[NSFileManager defaultManager] temporaryURLForWritingToURL:localTargetURL allowOriginalDirectory:YES error:&error];
    if (!snapshotURL) {
        NSLog(@"Unable to determine temporary location for writing to %@: %@", localTargetURL, [error toPropertyList]);
        if (outError)
            *outError = error;
        OBChainError(outError);
        return nil;
    }
    
    // Make sure _localSnapshotURL ends up with a standardized path
    OBASSERT([[[snapshotURL URLByDeletingLastPathComponent] URLByStandardizingPath] isEqual:[snapshotURL URLByDeletingLastPathComponent]]);
    
    _localSnapshotURL = [snapshotURL absoluteURL];
    _localRelativePath = [localRelativePath copy];
    
    error = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtURL:_localSnapshotURL withIntermediateDirectories:NO attributes:nil error:&error]) {
        NSLog(@"Unable to create local snapshot directory %@: %@", _localSnapshotURL, [error toPropertyList]);
        if (outError)
            *outError = error;
        OBChainError(outError);
        return nil;
    }
    
    return self;
}

static NSString *ClientComputerName(void)
{
#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
    NSString *fullHostname = OFHostName();
    NSRange dotRange = [fullHostname rangeOfString:@"."];
    if (dotRange.length == 0)
        return fullHostname;
    else
        return [fullHostname substringToIndex:dotRange.location];
#else
    return [[UIDevice currentDevice] name];
#endif
}


- (instancetype)initWithTargetLocalSnapshotURL:(NSURL *)localTargetURL forNewLocalDocumentAtURL:(NSURL *)localDocumentURL localRelativePath:(NSString *)localRelativePath intendedLocalRelativePath:(NSString *)intendedLocalRelativePath coordinator:(NSFileCoordinator *)coordinator error:(NSError **)outError;
{
    OBPRECONDITION(localTargetURL);
    OBPRECONDITION(localRelativePath);
    OBPRECONDITION(localDocumentURL);
    OBPRECONDITION(!intendedLocalRelativePath || coordinator, "If an original item is specified, we must also get a file coordinator that is already reading it"); // We get passed down a file coordinator that was involved in reading the (now moved) localDocumentURL or the original item and reuse it here to avoid deadlock.

    if (!(self = [self _initTemporarySnapshotWithTargetLocalSnapshotURL:localTargetURL localRelativePath:localRelativePath error:outError]))
        return nil;
    
    // Record the info about the snapshot we just made and the fact that it isn't uploaded yet.
    NSMutableDictionary *versionDictionary = [NSMutableDictionary new];
    versionDictionary[kOFXVersion_ArchiveVersionKey] = @(kOFXVersion_ArchiveVersion);
    versionDictionary[kOFXVersion_RemoteState] = [OFXFileState missing].archiveString;
    versionDictionary[kOFXVersion_NumberKey] = @(0);
    
    // We need to record the contents so we can at least know the total size of the document and whether it is a directory. We don't provoke saves since the containing account will rescan and grab an updated version if there is a later autosave.
    if (!coordinator)
        coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
    
    NSDictionary *versionContents = _recordVersionContents(localDocumentURL, coordinator, NO/*with changes*/, outError);
    if (!versionContents)
        return nil;
    versionDictionary[kOFXVersion_ContentsKey] = versionContents;
    // No kOFXVersion_ETagKey, kOFXVersion_EditIdentifierKey, or kOFXVersion_ServerModificationDateKey since this hasn't been uploaded
    
    // Build the Info.plist
    NSMutableDictionary *infoDictionary = [NSMutableDictionary dictionary];
    infoDictionary[kOFXInfo_ArchiveVersionKey] = @(kOFXInfo_ArchiveVersion);

    NSDate *creationDate = nil;
    NSNumber *creationTimeNumber = versionContents[kOFXContents_FileCreationTime];
    if (creationTimeNumber != nil) {
        NSTimeInterval creationTimestamp = creationTimeNumber.doubleValue;
        creationDate = [NSDate dateWithTimeIntervalSinceReferenceDate:creationTimestamp];
    }
    if (!creationDate) {
        NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:[localDocumentURL path] error:outError];
        if (!attributes)
            return nil;
        creationDate = attributes.fileCreationDate;
        if (!creationDate) {
            OBASSERT_NOT_REACHED("No creation date in attributes");
            creationDate = [NSDate date];
        }
    }
    
    if (intendedLocalRelativePath) {
        // We are for a conflict version and the document doesn't live where the user wanted it.
        versionDictionary[kOFXVersion_LocalState] = [[OFXFileState normal] withAutoMoved].archiveString;
        versionDictionary[kOFXVersion_RelativePath] = localRelativePath;
        infoDictionary[kOFXInfo_PathKey] = intendedLocalRelativePath;
    } else {
        versionDictionary[kOFXVersion_LocalState] = [OFXFileState normal].archiveString;
        infoDictionary[kOFXInfo_PathKey] = localRelativePath;
    }

    NSString *currentDateString = [creationDate xmlString];
    infoDictionary[kOFXInfo_CreationDateKey] = currentDateString;
    infoDictionary[kOFXInfo_ModificationDateKey] = currentDateString;
    
    infoDictionary[kOFXInfo_LastEditedByKey] = NSUserName();
    infoDictionary[kOFXInfo_LastEditedHostKey] = ClientComputerName();
    
    if (![self _updateVersionDictionary:versionDictionary reason:@"initialized" error:outError])
        return nil;
    if (![self _updateInfoDictionary:infoDictionary error:outError])
        return nil;
    
    OBPOSTCONDITION(self.remoteState.missing);
    OBPOSTCONDITION(self.remoteState.missing);
    OBPOSTCONDITION([self _checkInvariants]);
    return self;
}

// OBFinishPorting - <bug:///147841> (iOS-OmniOutliner Engineering: Use the 'actions' class in OFXIterateContentFiles)
static void OFXIterateContentFiles(NSDictionary *contents, void (^action)(NSDictionary *fileInfo))
{
    NSString *fileType = contents[kOFXContents_FileTypeKey];
    OBASSERT(fileType);
    
    if ([fileType isEqualToString:kOFXContents_FileTypeRegular]) {
        action(contents);
        return;
    }
    
    if ([fileType isEqualToString:kOFXContents_FileTypeDirectory]) {
        NSDictionary *children = contents[kOFXContents_DirectoryChildrenKey];
        OBASSERT(children);
        
        [children enumerateKeysAndObjectsUsingBlock:^(NSString *name, NSDictionary *entry, BOOL *stop) {
            OFXIterateContentFiles(entry, action);
        }];
        return;
    }
    
    if ([fileType isEqualToString:kOFXContents_FileTypeLink]) {
        // Only iterating real files here.
        return;
    }
    
    OBASSERT_NOT_REACHED("Unhandled file type %@", fileType);
}

@synthesize localRelativePath = _localRelativePath;
- (NSString *)localRelativePath;
{
    OBPRECONDITION(self.localState.deleted == NO, @"Don't ask for the path of deleted files."); // It has no meaning and might be 'incorrect' by some measure if the file was moved before being deleted (since -markAsLocallyDeleted: partially rolls back the new relative path info).
    return _localRelativePath;
}

- (NSString *)intendedLocalRelativePath;
{
    if (self.localState.autoMoved) {
        NSString *path = _infoDictionary[kOFXInfo_PathKey];
        OBASSERT(![NSString isEmptyString:path]);
        OBASSERT_NOTNULL(_localRelativePath);
        OBASSERT(![path isEqualToString:_localRelativePath]);
        return path;
    } else
        return self.localRelativePath;
}

- (OFXFileState *)localState;
{
    OFXFileState *state = [OFXFileState stateFromArchiveString:_versionDictionary[kOFXVersion_LocalState]];
    OBPOSTCONDITION(state);
    return state;
}

- (OFXFileState *)remoteState;
{
    OFXFileState *state = [OFXFileState stateFromArchiveString:_versionDictionary[kOFXVersion_RemoteState]];
    OBASSERT(state);
    OBASSERT(state.autoMoved == NO, "The server only has user intended moves");
    return state;
}

- (BOOL)isDirectory;
{
    OBPRECONDITION([self _checkInvariants]);

    // If we have a local copy, use that (for example, for files that haven't been uploaded yet).
    NSDictionary *contents = _versionDictionary[kOFXInfo_ContentsKey];
    
    // Otherwise, we might have a file that has never been downloaded or has been deleted while we are currently downloading
    if (!contents) {
        contents = _infoDictionary[kOFXInfo_ContentsKey];
        OBASSERT(self.localState.missing || self.localState.deleted);
        OBASSERT(self.remoteState.normal || self.remoteState.deleted || self.remoteState.edited);
        OBASSERT(contents);
    }
    
    NSString *fileType = contents[kOFXContents_FileTypeKey];
    OBASSERT(fileType);
    return [fileType isEqualToString:kOFXContents_FileTypeDirectory];
}

- (BOOL)isSymbolicLink;
{
    OBPRECONDITION([self _checkInvariants]);
    
    // If we have a local copy, use that (for example, for files that haven't been uploaded yet).
    NSDictionary *contents = _versionDictionary[kOFXInfo_ContentsKey];
    
    // Otherwise, we might have a file that has never been downloaded or has been deleted while we are currently downloading
    if (!contents) {
        contents = _infoDictionary[kOFXInfo_ContentsKey];
        OBASSERT(self.localState.missing);
        OBASSERT(self.remoteState.normal || self.remoteState.deleted || self.remoteState.edited);
        OBASSERT(contents);
    }
    
    NSString *fileType = contents[kOFXContents_FileTypeKey];
    OBASSERT(fileType);
    return [fileType isEqualToString:kOFXContents_FileTypeLink];
}

- (unsigned long long)totalSize;
{
    OBPRECONDITION([self _checkInvariants]);

    // If we have a local copy, use that (for example, for files that haven't been uploaded yet).
    NSDictionary *contents = _versionDictionary[kOFXInfo_ContentsKey];
    
    // Otherwise, we might have a file that has never been downloaded or has been deleted while we are currently downloading
    if (!contents) {
        contents = _infoDictionary[kOFXInfo_ContentsKey];
        OBASSERT(self.localState.missing || self.localState.deleted);
        OBASSERT(self.remoteState.normal || self.remoteState.deleted || self.remoteState.edited);
        OBASSERT(contents);
    }
    
    __block unsigned long long totalSize = 0;
    OFXIterateContentFiles(contents, ^(NSDictionary *fileInfo){
        NSNumber *fileSize = fileInfo[kOFXContents_FileSizeKey];
        totalSize += [fileSize unsignedLongLongValue];
    });
    
    return totalSize;
}

- (NSDate *)userCreationDate;
{
    OBPRECONDITION([self _checkInvariants]);

    NSString *dateString = _infoDictionary[kOFXInfo_CreationDateKey];
    if (OFISEQUAL(dateString, @"1984-01-24T08:00:00.000Z")) // This corresponds to kMagicBusyCreationDate
        return self.userModificationDate;

    NSDate *date = [[NSDate alloc] initWithXMLString:dateString];
    OBASSERT(date);
    return date;
}

- (NSDate *)userModificationDate;
{
    OBPRECONDITION([self _checkInvariants]);
    
    NSString *dateString = _infoDictionary[kOFXInfo_ModificationDateKey];
    NSDate *date = [[NSDate alloc] initWithXMLString:dateString];
    OBASSERT(date);
    return date;
}

- (NSString *)lastEditedUser;
{
    OBPRECONDITION([self _checkInvariants]);
    
    NSString *userName = _infoDictionary[kOFXInfo_LastEditedByKey];
    if ([NSString isEmptyString:userName])
        userName = NSUserName();
    return userName;
}

- (NSString *)lastEditedHost;
{
    OBPRECONDITION([self _checkInvariants]);

    NSString *hostName = _infoDictionary[kOFXInfo_LastEditedHostKey];
    if ([NSString isEmptyString:hostName])
        hostName = ClientComputerName();
    return hostName;
}

- (NSUInteger)version;
{
    OBPRECONDITION([self _checkInvariants]);
    
    NSNumber *versionNumber = _versionDictionary[kOFXVersion_NumberKey];
    OBASSERT_NOTNULL(versionNumber);
    return [versionNumber unsignedLongValue];
}

- (NSNumber *)inode;
{
    OBPRECONDITION([self _checkInvariants]);
    
    OFXFileState *localState = self.localState;
    if (localState.missing || localState.deleted)
        return nil; // not downloaded, so no file
    
    NSNumber *inode = _versionDictionary[kOFXVersion_ContentsKey][kOFXContents_FileInode];
    OBASSERT([inode isKindOfClass:[NSNumber class]]);
    
    return inode;
}

- (NSDate *)fileModificationDate;
{
    OBPRECONDITION([self _checkInvariants]);
    
    OFXFileState *localState = self.localState;
    if (localState.missing || localState.deleted)
        return nil; // not downloaded, so no file
    
    NSNumber *timeInterval = _versionDictionary[kOFXVersion_ContentsKey][kOFXContents_FileModificationTime];
    OBASSERT([timeInterval isKindOfClass:[NSNumber class]]);
    
    return [NSDate dateWithTimeIntervalSinceReferenceDate:[timeInterval doubleValue]];
}

// Currently unused
#if 0
static void _appendContentDescription(NSMutableString *desc, NSDictionary *contents)
{
    NSString *type = contents[kOFXContents_FileTypeKey];
    
    if ([type isEqual:kOFXContents_FileTypeRegular]) {
        [desc appendString:@"="];
        [desc appendString:contents[kOFXContents_FileHashKey]];
        return;
    }
    if ([type isEqual:kOFXContents_FileTypeDirectory]) {
        [desc appendString:@"["];
        
        NSDictionary *children = contents[kOFXContents_DirectoryChildrenKey];
        [children enumerateKeysAndObjectsUsingBlock:^(NSString *name, NSDictionary *child, BOOL *stop) {
            [desc appendString:name];
            _appendContentDescription(desc, child);
        }];
        [desc appendString:@"]"];
        return;
    }
    if ([type isEqual:kOFXContents_FileTypeLink]) {
        [desc appendString:@"@"];
        [desc appendString:contents[kOFXContents_LinkDestinationKey]];
        return;
    }
    
    OBASSERT_NOT_REACHED("Unknown file type %@", type);
}

@synthesize contentsHash = _contentsHash;
- (NSString *)contentsHash;
{
    if (!_contentsHash) {
        NSMutableString *contentDescription = [[NSMutableString alloc] init];
        _appendContentDescription(contentDescription, _infoDictionary[kOFXInfo_ContentsKey]);
        _contentsHash = OFXMLCreateIDFromData([[contentDescription dataUsingEncoding:NSUTF8StringEncoding] sha1Signature]);
    }
    return _contentsHash;
}
#endif

// TODO: This could probably early out with a YES, since the top level file or directory will have a new inode.
- (NSNumber *)hasSameContentsAsLocalDocumentAtURL:(NSURL *)localDocumentURL coordinator:(NSFileCoordinator *)coordinator withChanges:(BOOL)withChanges error:(NSError **)outError;
{
    OBPRECONDITION([self _checkInvariants]);
    
    NSDictionary *versionContents = _versionDictionary[kOFXVersion_ContentsKey];
    OBASSERT(versionContents);
    
    NSDictionary *currentContents = _recordVersionContents(localDocumentURL, coordinator, withChanges, outError);
    if (!currentContents)
        return nil;
    
    if (OFISEQUAL(versionContents, currentContents))
        return @YES;
    return @NO;
}

// Returns YES if the structure and content of the two snapshots are the same. Does *not* consider the relative path of the snapshot (so this can be used to detect when the difference between two snapshots is a simple move).
- (BOOL)hasSameContentsAsSnapshot:(OFXFileSnapshot *)otherSnapshot;
{
    OBPRECONDITION(otherSnapshot);
    
    NSDictionary *contents = _infoDictionary[kOFXInfo_ContentsKey];
    OBASSERT(contents);
    
    NSDictionary *otherContents = otherSnapshot.infoDictionary[kOFXInfo_ContentsKey];
    OBASSERT(otherContents);

    return OFISEQUAL(contents, otherContents);
}

#ifdef OMNI_ASSERTIONS_ON
static BOOL RunningOnAccountQueue(void)
{
    // Ugly, but we want to make sure that only the account and its containers are making changes to the database of snapshots. We don't want transfers clobbering stuff -- they need to pass back to the account/container/file item and let it decide what to do on the account's serial bookkeeping queue.
    return [[[NSOperationQueue currentQueue] name] containsString:@"com.omnigroup.OmniFileExchange.OFXAccountAgent.bookkeeping"];
}
#endif

- (BOOL)_updateInfoDictionary:(NSDictionary *)infoDictionary error:(NSError **)outError;
{
    OBPRECONDITION(RunningOnAccountQueue());
    OBPRECONDITION(!_infoDictionary || OFISEQUAL(_infoDictionary[kOFXInfo_ContentsKey], infoDictionary[kOFXInfo_ContentsKey]), @"Make a new snapshot if you have new contents");
    
    // Make sure we can validate what we'll read later.
    if (!OFXValidateInfoDictionary(infoDictionary, outError)) {
        OBChainError(outError);
        return NO;
    }
    
    __autoreleasing NSError *error;
    if (!OFWriteNSPropertyListToURL(infoDictionary, [_localSnapshotURL URLByAppendingPathComponent:kOFXLocalInfoFileName], &error)) {
        NSLog(@"Unable to archive info dictionary for new snapshot at %@:\ninfoDictionary=%@\nerror=%@", _localSnapshotURL, infoDictionary, [error toPropertyList]);
        if (outError)
            *outError = error;
        OBChainError(outError);
        return NO;
    }
    
    _infoDictionary = [infoDictionary copy];
    OBASSERT(_infoDictionary);
    
    DEBUG_CONTENT(1, @"Updated snapshot has content \"%@\"", OFXLookupDisplayNameForContentIdentifier(self.currentContentIdentifier));

    return YES;
}

- (BOOL)_updateVersionDictionary:(NSDictionary *)versionDictionary reason:(NSString *)reason error:(NSError **)outError;
{
    OBPRECONDITION(RunningOnAccountQueue());
    
    // Make sure we can validate what we'll read later.
    if (!OFXValidateVersionDictionary(versionDictionary, outError)) {
        OBChainError(outError);
        return NO;
    }
    
    __autoreleasing NSError *error;
    if (!OFWriteNSPropertyListToURL(versionDictionary, [_localSnapshotURL URLByAppendingPathComponent:kOFXVersionFileName], &error)) {
        NSLog(@"Unable to archive version dictionary for snapshot at %@:\nversionDictionary=%@\nerror=%@", _localSnapshotURL, versionDictionary, [error toPropertyList]);
        if (outError)
            *outError = error;
        OBChainError(outError);
        return NO;
    }
    
    _versionDictionary = [versionDictionary copy];
    
    if (_infoDictionary) // Otherwise, still setting up
        DEBUG_SNAPSHOT(1, @"Updated snapshot with reason \"%@\", has state %@/%@", reason, self.localState, self.remoteState);

    return YES;
}

- (BOOL)_markEditedForKey:(NSString *)editsKey error:(NSError **)outError;
{
    OBINVARIANT([self _checkInvariants]);
    
    OFXFileState *state = [OFXFileState stateFromArchiveString:_versionDictionary[editsKey]];
    OBASSERT(state.normal || state.userMoved || state.autoMoved, "Don't mark deleted/edited documents as edited");
    
    state = [state withEdited];
    
    NSMutableDictionary *versionDictionary = [NSMutableDictionary dictionaryWithDictionary:_versionDictionary];
    versionDictionary[editsKey] = state.archiveString;
    
    BOOL success = [self _updateVersionDictionary:versionDictionary reason:@"mark edited" error:outError];
    OBINVARIANT([self _checkInvariants]);
    return success;
}

- (BOOL)markAsLocallyEdited:(NSError **)outError;
{
    return [self _markEditedForKey:kOFXVersion_LocalState error:outError];
}

- (BOOL)markAsRemotelyEdited:(NSError **)outError;
{
    return [self _markEditedForKey:kOFXVersion_RemoteState error:outError];
}

- (BOOL)markAsLocallyDeleted:(NSError **)outError;
{
    OBINVARIANT([self _checkInvariants]);
    
    // We might be remote=missing if we are deleted before a successful upload. In this case, the delete transfer will just cleanup the original snapshot.
    //OBASSERT(self.remoteState.missing == NO);
    
    NSMutableDictionary *versionDictionary = [NSMutableDictionary dictionaryWithDictionary:_versionDictionary];
    versionDictionary[kOFXVersion_LocalState] = [[OFXFileState deleted] archiveString];
    
    // Nothing on disk now
    [versionDictionary removeObjectForKey:kOFXVersion_ContentsKey];
    
    // If we were moved before, that no longer matters. This leaves the receiver with _localRelativePath set to the destination path, but its Info.plist pointing at the pre-move path. We could maybe flatten the move, or maybe reset _localRelativePath to the original value, but really no one should be looking at the path for delete files, so -localRelativePath asserts if we are deleted.
    [versionDictionary removeObjectForKey:kOFXVersion_RelativePath];
    
    BOOL success = [self _updateVersionDictionary:versionDictionary reason:@"locally deleted" error:outError];
    OBINVARIANT([self _checkInvariants]);
    return success;
}

- (BOOL)markAsRemotelyDeleted:(NSError **)outError;
{
    OBINVARIANT([self _checkInvariants]);
    
    NSMutableDictionary *versionDictionary = [NSMutableDictionary dictionaryWithDictionary:_versionDictionary];
    versionDictionary[kOFXVersion_RemoteState] = [[OFXFileState deleted] archiveString];
    
    BOOL success = [self _updateVersionDictionary:versionDictionary reason:@"remotely deleted" error:outError];
    OBINVARIANT([self _checkInvariants]);
    return success;
}

- (BOOL)_markAsLocallyAutomaticallyMovedToRelativePath:(NSString *)relativePath error:(NSError **)outError;
{
    OBPRECONDITION(![NSString isEmptyString:relativePath]);
    OBINVARIANT([self _checkInvariants]);
    
    OFXFileState *localState = self.localState;
    
    // If we are already automatically moved, and the new location is our intended location, then we are undoing a previous automatic move
    if (localState.autoMoved) {
        NSString *intendedLocalRelativePath = self.intendedLocalRelativePath;
        if ([relativePath isEqual:intendedLocalRelativePath]) {
            localState = [localState withAutoMovedCleared];
            
            _localRelativePath = [relativePath copy];
            
            NSMutableDictionary *versionDictionary = [NSMutableDictionary dictionaryWithDictionary:_versionDictionary];
            versionDictionary[kOFXVersion_LocalState] = localState.archiveString;
            [versionDictionary removeObjectForKey:kOFXVersion_RelativePath];
            
            BOOL success = [self _updateVersionDictionary:versionDictionary reason:@"undoing local automove" error:outError];
            
            OBINVARIANT([self _checkInvariants]);
            return success;
        }
    }
    
    // In both the remotely missing and not-missing cases, we just do a local note for automatic moves.
    localState = [localState withAutoMoved];
    if (localState.autoMoved == NO) {
        OBASSERT_NOT_REACHED("Move refused!");
        return YES; // As noted in the calling code, this isn't fatal but can cause file duplication in edge cases.
    }
    
    _localRelativePath = [relativePath copy];
    
    NSMutableDictionary *versionDictionary = [NSMutableDictionary dictionaryWithDictionary:_versionDictionary];
    versionDictionary[kOFXVersion_LocalState] = localState.archiveString;
    versionDictionary[kOFXVersion_RelativePath] = relativePath;
    
    BOOL success = [self _updateVersionDictionary:versionDictionary reason:@"local automove" error:outError];
    
    OBINVARIANT([self _checkInvariants]);
    return success;
}

- (BOOL)markAsLocallyMovedToRelativePath:(NSString *)relativePath isAutomaticMove:(BOOL)isAutomaticMove error:(NSError **)outError;
{
    OBPRECONDITION(![NSString isEmptyString:relativePath]);
    OBINVARIANT([self _checkInvariants]);
    
    if (isAutomaticMove)
        return [self _markAsLocallyAutomaticallyMovedToRelativePath:relativePath error:outError];

    BOOL success;
    OFXFileState *localState = self.localState;
    OFXFileState *remoteState = self.remoteState;
    
    if (remoteState.missing) {
        // If we are a new file, just record the new path. We might be in the middle of uploading, but our file item's commit hook will notice that the snapshot it started uploading and the snapshot it has at the end have different paths and will mark the committed snapshot as being in the move state. If we die before the upload finishes, there is issue. We *might* die in the brief window between publishing the new file on the server and updating our local snapshot, but we could anyway (and we'll just get duplicated data in that case).
        
        _localRelativePath = relativePath;
        
        NSMutableDictionary *infoDictionary = [NSMutableDictionary dictionaryWithDictionary:_infoDictionary];
        infoDictionary[kOFXInfo_PathKey] = relativePath;
        success = [self _updateInfoDictionary:infoDictionary error:outError];
    } else {
        // We might be finalizing an automove name via -_finalizeConflictNamesForFilesIntendingToBeAtRelativePaths:. In this case, we turn automove into a real move and keep the same destination path for the upload transfer
        if (localState.autoMoved && !isAutomaticMove) {
            localState = [localState withAutoMovedCleared];
        }
        
        // We might be uploading -- we need to remember that a moved happened
        localState = [localState withUserMoved];
        if (localState.userMoved == NO) {
            OBASSERT_NOT_REACHED("Move refused!");
            return YES; // As noted in the calling code, this isn't fatal but can cause file duplication in edge cases.
        }
        
        _localRelativePath = relativePath;
        
        NSMutableDictionary *versionDictionary = [NSMutableDictionary dictionaryWithDictionary:_versionDictionary];
        versionDictionary[kOFXVersion_LocalState] = localState.archiveString;
        versionDictionary[kOFXVersion_RelativePath] = relativePath;
        
        success = [self _updateVersionDictionary:versionDictionary reason:@"local move" error:outError];
    }
    
    OBINVARIANT([self _checkInvariants]);
    return success;
}

// Called as part of conflict resolution when the local document's edits are moved aside.
- (BOOL)didGiveUpLocalContents:(NSError **)outError;
{
    OBINVARIANT([self _checkInvariants]);
    
    NSMutableDictionary *versionDictionary = [NSMutableDictionary dictionaryWithDictionary:_versionDictionary];
    versionDictionary[kOFXVersion_RemoteState] = [[OFXFileState normal] archiveString];
    versionDictionary[kOFXVersion_LocalState] = [[OFXFileState missing] archiveString];
    [versionDictionary removeObjectForKey:kOFXVersion_RelativePath];
    [versionDictionary removeObjectForKey:kOFXVersion_ContentsKey];

    
    BOOL success = [self _updateVersionDictionary:versionDictionary reason:@"gave up contents" error:outError];
    
    OBPOSTCONDITION(!success || self.localState.missing);
    OBINVARIANT([self _checkInvariants]);
    return success;
}

- (BOOL)didPublishContentsToLocalDocumentURL:(NSURL *)localDocumentURL error:(NSError **)outError;
{
    OBPRECONDITION(self.localState.deleted == NO);

    // This is called within the scope of a file coordinator on localDocumentURL, so we don't need to perform coordination.
    
    NSMutableDictionary *versionDictionary = [NSMutableDictionary dictionaryWithDictionary:_versionDictionary];
    NSMutableDictionary *versionContents = [NSMutableDictionary new];
    
    if (!OFXFileItemRecordContents(OFXVersionContentsType, versionContents, localDocumentURL, outError)) {
        // The contents are already published at this point, so an error here will mean we'll think that an edit has been made to the document (since it won't match our Version.plist Contents.
        OBChainError(outError);
        return NO;
    }
    
    versionDictionary[kOFXVersion_ContentsKey] = versionContents;
    
    BOOL success = [self _updateVersionDictionary:versionDictionary reason:@"did publish" error:outError];
    OBINVARIANT([self _checkInvariants]);
    return success;
}

- (BOOL)didTakePublishedContentsFromSnapshot:(OFXFileSnapshot *)otherSnapshot error:(NSError **)outError;
{
    OBPRECONDITION(self.localState.normal); // We should be downloaded and are just a rename of an existing snapshot.
    
    NSMutableDictionary *versionDictionary = [NSMutableDictionary dictionaryWithDictionary:_versionDictionary];
    
    NSDictionary *contents = otherSnapshot.versionDictionary[kOFXVersion_ContentsKey];
    if (contents)
        versionDictionary[kOFXVersion_ContentsKey] = contents;
    else {
        // We'll fail validation below and will error out (better than a nil value exception).
    }
    
    BOOL success = [self _updateVersionDictionary:versionDictionary reason:@"did take contents" error:outError];
    OBINVARIANT([self _checkInvariants]);
    return success;
}

- (void)didMoveToTargetLocalSnapshotURL:(NSURL *)targetLocalSnapshotURL;
{
    OBPRECONDITION([self _checkInvariants]);
    OBPRECONDITION([_localSnapshotURL isEqual:targetLocalSnapshotURL] == NO);
    
    _localSnapshotURL = targetLocalSnapshotURL;

    OBPOSTCONDITION([self _checkInvariants]);
}

- (BOOL)finishedUploadingWithError:(NSError **)outError;
{    
    NSDictionary *versionDictionary = self.versionDictionary;
    OBASSERT(versionDictionary); // should have the info from when the snapshot was made of the local document.
    OBASSERT([versionDictionary[kOFXVersion_ArchiveVersionKey] isEqual:@(kOFXVersion_ArchiveVersion)]);
    
    OFXFileState *localState = self.localState;
#ifdef OMNI_ASSERTIONS_ON
    {
        OFXFileState *remoteState = self.remoteState;
        OBASSERT(localState.missing ^ (versionDictionary[kOFXVersion_ContentsKey] != nil));
        OBASSERT(remoteState.missing || localState.edited || localState.userMoved || (localState.missing && localState.userMoved));
        OBASSERT(remoteState.missing || remoteState.normal || remoteState.edited /* might be about to discover a conflict...*/ || (localState.missing && localState.userMoved)/*might be moving a non-downloaded file*/);
    }
#endif
    
    NSMutableDictionary *updatedVersionDictionary = [NSMutableDictionary dictionaryWithDictionary:versionDictionary];
    
    if (localState.missing) {
        OBASSERT(localState.userMoved, @"Should only upload a locally missing file if we are renaming it");
        localState = [OFXFileState missing];
    } else {
        if (localState.autoMoved)
            localState = [[OFXFileState normal] withAutoMoved]; // Keep the automatic move note if present
        else
            localState = [OFXFileState normal];
    }
    
    updatedVersionDictionary[kOFXVersion_LocalState] = localState.archiveString;
    updatedVersionDictionary[kOFXVersion_RemoteState] = [OFXFileState normal].archiveString;

    if (!localState.autoMoved) {
        // We've told the server we want to be at the new location, so we are no longer moved. If this an automatic local move, we haven't told the server and we want to remember our local location.
        [updatedVersionDictionary removeObjectForKey:kOFXVersion_RelativePath];
    }
    
    // Write the results to our local snapshot as a new/updated Version.plist. If we die between here and writing this file, the next sync would produce either a duplicate upload (if this was a new file) or a self-conflict (both preferable to losing data of course).
    if (![self _updateVersionDictionary:updatedVersionDictionary reason:@"finished upload" error:outError]) {
        OBChainError(outError);
        OBPOSTCONDITION([self _checkInvariants]);
        return NO;
    }
    
    OBPOSTCONDITION([self _checkInvariants]);
    return YES;
}

- (NSString *)currentContentIdentifier;
{
    return OFXContentIdentifierForContents(_infoDictionary[kOFXInfo_ContentsKey]);
}

#pragma mark - Debugging

- (NSString *)shortDescription;
{
    if (!_infoDictionary) {
        // This can happen when debug logging is enabled and we are reporting errors during initializing a snapshot (so its dicts aren't set up).
        OBASSERT(!_versionDictionary);
        return [NSString stringWithFormat:@"<%@:%p %@ UNINITIALIZED>", NSStringFromClass([self class]), self, _localSnapshotURL];
    }
    
    return [NSString stringWithFormat:@"<%@:%p %@ %@/%@ version:%lu>", NSStringFromClass([self class]), self, _localSnapshotURL, self.localState, self.remoteState, self.version];
}

#pragma mark - Internal

#ifdef OMNI_ASSERTIONS_ON
- (BOOL)_checkInvariants;
{    
    __autoreleasing NSError *error = nil;
    if (!OFXValidateInfoDictionary(_infoDictionary, &error)) {
        NSLog(@"Info dictionary validation failed: %@", [error toPropertyList]);
        OBINVARIANT(NO, @"_infoDictionary not valid");
    }

    if (!OFXValidateVersionDictionary(_versionDictionary, &error)) {
        NSLog(@"Version dictionary validation failed: %@", [error toPropertyList]);
        OBINVARIANT(NO, @"_versionDictionary not valid");
    }
    return YES;
}
#endif

@end
