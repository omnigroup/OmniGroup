// Copyright 2013-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFXFileSnapshot.h"

#import <OmniBase/macros.h>

@interface OFXFileSnapshot ()

- _initTemporarySnapshotWithTargetLocalSnapshotURL:(NSURL *)localTargetURL localRelativePath:(NSString *)localRelativePath error:(NSError **)outError;
- (BOOL)_updateInfoDictionary:(NSDictionary *)infoDictionary error:(NSError **)outError;
- (BOOL)_updateVersionDictionary:(NSDictionary *)versionDictionary reason:(NSString *)reason error:(NSError **)outError;
#ifdef OMNI_ASSERTIONS_ON
- (BOOL)_checkInvariants;
#endif
@end

typedef NS_ENUM(NSUInteger, OFXContentsType) {
    OFXInfoContentsType,
    OFXVersionContentsType,
};

extern BOOL OFXFileItemRecordContents(OFXContentsType type, NSMutableDictionary *contents, NSURL *fileURL, NSError **outError) OB_HIDDEN;

#define kOFXLocalInfoFileName @"Info.plist"
#define kOFXVersionFileName @"Version.plist"

//
// Info.plist keys and constants
//
#define kOFXInfo_ArchiveVersion (0)
#define kOFXInfo_ArchiveVersionKey @"Version"

// The desired relative path of the user-visible document. It may get published to a different relative path if there is a conflict.
#define kOFXInfo_PathKey @"Path"

#define kOFXInfo_ContentsKey @"Contents"
//#define kOFXInfo_ContentsIsDirectoryKey @"ContentsIsDirectory"

// Optional info about the author (not written by earlier versions), used in building conflict names if present.
#define kOFXInfo_LastEditedByKey @"LastEditedBy"
#define kOFXInfo_LastEditedHostKey @"LastEditedHost"

// plist archiving of dates doesn't record fractional seconds; doesn't matter for display to users, but our unit tests like to see things change over time. We record these via our ISO8601 datetime archiving.
// These are the overall dates shown to the user, which aren't necessarily the same as the timestamp on the local files.
#define kOFXInfo_CreationDateKey @"CreationDate"
#define kOFXInfo_ModificationDateKey @"ModificationDate"

//
// Version.plist keys and constants
//
#define kOFXVersion_ArchiveVersion (0)
#define kOFXVersion_ArchiveVersionKey @"Version"
#define kOFXVersion_ContentsKey @"Contents"
#define kOFXVersion_NumberKey @"Number" // Incrementing integer version
#define kOFXVersion_LocalState @"LocalState"
#define kOFXVersion_RemoteState @"RemoteState"
#define kOFXVersion_RelativePath @"RelativePath" // If we have been moved locally (either by the user or by an automatic local-only move)

//
// Contents dictionaries that record the state of a file. These are mostly common to the Info.plist and Version.plist, but some items only make sense on one side or the other.
//

#define kOFXContents_DirectoryChildrenKey @"Children"

#define kOFXContents_FileTypeKey @"Type"
#define   kOFXContents_FileTypeRegular @"file"
#define   kOFXContents_FileTypeDirectory @"directory"
#define   kOFXContents_FileTypeLink @"link"

#define kOFXContents_FileHashKey @"Hash" // Only in Info.plist
#define kOFXContents_FileSizeKey @"Size"
#define kOFXContents_FileCreationTime @"CreationTime" // Only in Version.plist; the actual local timestamp
#define kOFXContents_FileModificationTime @"ModificationTime" // Only in Version.plist; the actual local timestamp
#define kOFXContents_FileInode @"INode" // Only in Version.plist; to protect against swapping out two files with the same times and sizes but different contents w/o hashing

#define kOFXContents_LinkDestinationKey @"Destination"

