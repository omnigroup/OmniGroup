// Copyright 2013-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFileExchange/OFXAccountAgent.h>

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

@end

extern NSString * const OFXAccountAgentDidStopForReplacementNotification;

NS_ASSUME_NONNULL_END
