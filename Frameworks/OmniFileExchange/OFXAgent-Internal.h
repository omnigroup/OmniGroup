// Copyright 2013-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFileExchange/OFXAgent.h>

static inline NSString *OFXCopyRegistrationKeyForAccountMetadataItems(NSString *accountUUID)
{
    return [[NSString alloc] initWithFormat:@"metadata %@", accountUUID];
}

extern BOOL OFXShouldSyncAllPathExtensions(NSSet *pathExtensions) OB_HIDDEN;

@interface OFXAgent ()
- (NSOperationQueue *)_operationQueueForAccount:(OFXServerAccount *)serverAccount;
@end
