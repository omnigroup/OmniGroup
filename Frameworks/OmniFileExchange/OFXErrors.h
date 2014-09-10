// Copyright 2013-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

enum {
    // skip zero since it means 'no error' to AppleScript (actually the first 10-ish are defined in NSScriptCommand)
    
    // OFXServerAccountType account validation
    OFXServerAccountCannotLoad = 1,
    OFXServerAccountNotConfigured,
    OFXServerAccountLocationNotFound,
    
    OFXLocalAccountDocumentsDirectoryMissing,
    OFXCannotResolveLocalDocumentsURL,
    OFXUnableToLockAccount,
    OFXAgentNotStarted,
    OFXFileNotContainedInAnyAccount,
    OFXNoFileForURL,
    OFXAccountRepositoryCorrupt,
    OFXAccountRepositoryTooNew,
    OFXAccountRepositoryTooOld,
    OFXFileUpdatedWhileDeleting,
    OFXFileItemDetectedRemoteEdit,
    OFXFileDeletedWhileDownloading,
    
    // Syncing
    OFXCloudScanFailed,
    OFXAccountScanFailed,
    OFXLocalAccountDirectoryNotUsable,
    OFXLocalAccountDirectoryModifiedWhileScanning,
    OFXAccountUnableToStoreClientInfo,
    OFXAccountUnableToCreateContainer,
    OFXAccountUnableToRecordFileContents,
    OFXAccountUnableToReadFileItem,
    OFXSnapshotCorrupt,
    OFXSnapshotInfoCorrupt,
    OFXDownloadFailed,
    OFXDownloadNotNeeded,
    OFXAccountNotPreparedForRemoval, // Internal and should never been seen under properly working conditions
    OFXAccountLocalDocumentsDirectoryInvalidForDeletion, // Returned by +[OFXServerAccount deleteGeneratedLocalDocumentsURL:error:] if the passed in URL looks suspicious
    OFXNoContainer,
    OFXTooManyRecentFileTransferErrors,
    
    // Document store scope
    OFXFileItemNotDownloaded,
};

extern NSString * const OFXErrorDomain;

#define OFXErrorWithInfo(error, code, description, suggestion, ...) _OBError(error, OFXErrorDomain, code, __FILE__, __LINE__, NSLocalizedDescriptionKey, description, NSLocalizedRecoverySuggestionErrorKey, (suggestion), ## __VA_ARGS__)
#define OFXError(error, code, description, reason) OFXErrorWithInfo((error), (code), (description), (reason), nil)

@interface OFXRecentError : NSObject

+ (instancetype)recentError:(NSError *)error withDate:(NSDate *)date;
- (instancetype)initWithError:(NSError *)error withDate:(NSDate *)date;

@property(nonatomic,readonly) NSDate *date;
@property(nonatomic,readonly) NSError *error;

@end
