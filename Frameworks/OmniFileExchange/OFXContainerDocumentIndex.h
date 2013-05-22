// Copyright 2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>

@class OFXContainerAgent, OFXFileItem;

@interface OFXContainerDocumentIndex : NSObject

- initWithContainerAgent:(OFXContainerAgent *)containerAgent;

- (NSMutableSet *)copyRegisteredFileItemIdentifiers;
- (NSMutableDictionary *)copyLocalRelativePathToPublishedFileItem;
#ifdef OMNI_ASSERTIONS_ON
- (NSObject <NSCopying> *)copyIndexState;
#endif

- (OFXFileItem *)fileItemWithIdentifier:(NSString *)identifier;
- (OFXFileItem *)publishedFileItemWithLocalRelativePath:(NSString *)localRelativePath; // The single published file item, if any
- (OFXFileItem *)publishableFileItemWithLocalRelativePath:(NSString *)localRelativePath; // If there is a published file item, return that, otherwise some other publishable file item

- (void)enumerateFileItems:(void (^)(NSString *identifier, OFXFileItem *fileItem))block;

- (NSDictionary *)copyRenameConflictLoserFileItemsByWinningFileItem;

- (void)registerScannedLocalFileItem:(OFXFileItem *)fileItem;
- (void)registerRemotelyAppearingFileItem:(OFXFileItem *)fileItem;
- (void)registerLocallyAppearingFileItem:(OFXFileItem *)fileItem;

- (void)addFileItems:(NSMutableArray *)fileItems inDirectoryWithRelativePath:(NSString *)localDirectoryRelativePath;

- (void)forgetFileItemForRemoteDeletion:(OFXFileItem *)fileItem;
- (void)beginLocalDeletionOfFileItem:(OFXFileItem *)fileItem;
#ifdef OMNI_ASSERTIONS_ON
- (BOOL)hasBegunLocalDeletionOfFileItem:(OFXFileItem *)fileItem;
#endif
- (void)completeLocalDeletionOfFileItem:(OFXFileItem *)fileItem;

- (void)fileItemMoved:(OFXFileItem *)fileItem fromLocalRelativePath:(NSString *)oldRelativePath toLocalRelativePath:(NSString *)newRelativePath;

- (void)invalidate;

@property(nonatomic,readonly) NSString *debugName;

#ifdef OMNI_ASSERTIONS_ON
- (BOOL)_checkInvariants;
#endif

@end
