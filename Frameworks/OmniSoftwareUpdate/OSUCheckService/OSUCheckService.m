// Copyright 2015-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OSUCheckService.h"

#import "OSURunOperation.h"

RCS_ID("$Id$")

@implementation OSUCheckService

- (void)performCheck:(OSURunOperationParameters *)parameters runtimeStats:(NSDictionary *)runtimeStats probes:(NSDictionary *)probes lookupCredential:(id <OSULookupCredential>)lookupCredential withReply:(void (^)(NSDictionary *results, NSError *error))reply;
{
    OSURunOperation(parameters, runtimeStats, probes, lookupCredential, reply);
}

@end
