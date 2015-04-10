// Copyright 2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OSUCheckService.h"

#import "OSURunOperation.h"

RCS_ID("$Id$")

@implementation OSUCheckService

- (void)performCheck:(OSURunOperationParameters *)parameters runtimeStatsAndProbes:(NSDictionary *)runtimeStatsAndProbes lookupCredential:(id <OSULookupCredential>)lookupCredential withReply:(void (^)(NSDictionary *results, NSError *error))reply;
{
    OSURunOperation(parameters, runtimeStatsAndProbes, lookupCredential, reply);
}

@end
