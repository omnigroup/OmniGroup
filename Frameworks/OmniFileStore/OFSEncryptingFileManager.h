// Copyright 2014-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFileStore/OFSFileManager.h>

#import <OmniFoundation/OFAsynchronousOperation.h>
#import <OmniBase/macros.h>

@class OFSDocumentKey;
@class OFSEncryptingFileManagerTasteOperation;
@class ODAVFileInfo;

NS_ASSUME_NONNULL_BEGIN

#define OFSFileManagerSlotWrote   0x0001
#define OFSFileManagerSlotRead    0x0002
#define OFSFileManagerSlotTasted  0x0004

typedef BOOL (^OFSEncryptingFileManagerFileMatch)(NSURL *fileURL);

@interface OFSEncryptingFileManager : OFSFileManager <OFSConcreteFileManager>

- initWithFileManager:(OFSFileManager <OFSConcreteFileManager> *)underlyingFileManager keyStore:(OFSDocumentKey *)keyStore error:(OBNSErrorOutType)outError NS_DESIGNATED_INITIALIZER ;

@property (readwrite, nonatomic, nonnull, copy) OFSDocumentKey *keyStore;
@property (readwrite, nonatomic, nullable, retain) ODAVFileInfo *keyStoreOrigin;
@property (readonly, nonatomic, retain) OFSFileManager *underlyingFileManager;

- (nullable OFSEncryptingFileManagerTasteOperation *)asynchronouslyTasteKeySlot:(ODAVFileInfo *)file;
- (nullable NSIndexSet *)unusedKeySlotsOfSet:(NSIndexSet *)slots amongFiles:(NSArray <ODAVFileInfo *> *)files error:(NSError **)outError;

- (void)maskFilesMatching:(OFSEncryptingFileManagerFileMatch)matchBlock;
- (BOOL)maskingFileAtURL:(NSURL *)fileURL;

@end

@interface OFSEncryptingFileManagerTasteOperation : OFAsynchronousOperation
/* These properties are not necessarily KVOable. Wait for the operation to be finished, then read them. */
@property (atomic,readonly) int keySlot;
@property (atomic,readonly,copy,nullable) NSError *error;
@end

NS_ASSUME_NONNULL_END
