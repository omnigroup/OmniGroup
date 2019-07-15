// Copyright 2013-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>

@class OFXContainerAgent, OFXFileItem;
@class OFXContainerDocumentIndexMove;

@interface OFXContainerDocumentIndex : NSObject

- initWithContainerAgent:(OFXContainerAgent *)containerAgent;

- (NSMutableSet *)copyRegisteredFileItemIdentifiers;
- (NSMutableDictionary *)copyLocalRelativePathToFileItem;
#ifdef OMNI_ASSERTIONS_ON
- (NSObject <NSCopying> *)copyIndexState;
#endif

- (OFXFileItem *)fileItemWithIdentifier:(NSString *)identifier;
- (OFXFileItem *)fileItemWithLocalRelativePath:(NSString *)localRelativePath; // The single published file item, if any
//- (OFXFileItem *)publishableFileItemWithLocalRelativePath:(NSString *)localRelativePath; // If there is a published file item, return that, otherwise some other publishable file item

- (void)enumerateFileItems:(void (^)(NSString *identifier, OFXFileItem *fileItem))block;

- (NSDictionary <NSString *, NSArray <OFXFileItem *> *> *)copyIntendedLocalRelativePathToFileItems;

- (void)registerScannedLocalFileItem:(OFXFileItem *)fileItem;
- (void)registerRemotelyAppearingFileItem:(OFXFileItem *)fileItem;
- (void)registerLocallyAppearingFileItem:(OFXFileItem *)fileItem;

- (void)addFileItems:(NSMutableArray <OFXFileItem *> *)fileItems inDirectoryWithRelativePath:(NSString *)localDirectoryRelativePath;

- (void)forgetFileItemForRemoteDeletion:(OFXFileItem *)fileItem;
- (void)beginLocalDeletionOfFileItem:(OFXFileItem *)fileItem;
#ifdef OMNI_ASSERTIONS_ON
- (BOOL)hasBegunLocalDeletionOfFileItem:(OFXFileItem *)fileItem;
#endif
- (void)completeLocalDeletionOfFileItem:(OFXFileItem *)fileItem;

- (void)fileItemMoved:(OFXFileItem *)fileItem fromLocalRelativePath:(NSString *)oldRelativePath toLocalRelativePath:(NSString *)newRelativePath;
- (void)fileItemsMoved:(NSArray <OFXContainerDocumentIndexMove *> *)moves; // Bulk move; array of OFXContainerDocumentIndexMove instances

@property(nonatomic,readonly) NSString *debugName;

#ifdef OMNI_ASSERTIONS_ON
- (BOOL)_checkInvariants;
#endif

@end

// For bulk moves.
@interface OFXContainerDocumentIndexMove : NSObject
@property(nonatomic,strong) OFXFileItem *fileItem;
@property(nonatomic,copy) NSString *originalRelativePath;
@property(nonatomic,copy) NSString *updatedRelativePath;
@end
