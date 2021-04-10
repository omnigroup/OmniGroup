// Copyright 2013-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFXAccountAgent.h"

#import <OmniFileExchange/OFXServerAccount.h> // OFX_MAC_STYLE_ACCOUNT

NS_ASSUME_NONNULL_BEGIN

@class ODAVConnection;
@class OFXContainerAgent, OFXFileItem;

typedef void (^OFXAfterMetadataUpdateAction)(void);

@interface OFXAccountAgent ()

- (ODAVConnection *)_makeConnection;

- (void)_fileItemDidDetectUnknownRemoteEdit:(OFXFileItem *)fileItem;
- (void)_containerAgentNeedsMetadataUpdate:(OFXContainerAgent *)container;
- (void)_afterMetadataUpdate:(OFXAfterMetadataUpdateAction)action NS_SWIFT_NAME(_afterMetadataUpdate(_:));

@property(nonatomic,readonly) NSOperationQueue *operationQueue;

#if !OFX_MAC_STYLE_ACCOUNT
// Set by OFXAgent when a migration is started.
@property(nonatomic,nullable,strong,readwrite) OFXAccountMigration *activeMigration;
#endif

@end

extern NSString * const OFXAccountAgentDidStopForReplacementNotification;

NS_ASSUME_NONNULL_END
