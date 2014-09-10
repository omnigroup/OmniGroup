// Copyright 2013-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFXTestCase.h"

#import <OmniFileExchange/OFXAccountClientParameters.h>
#import <OmniFileExchange/OFXErrors.h>

RCS_ID("$Id$")

@interface OFXTestClientVersion : OFXTestCase

@end

@implementation OFXTestClientVersion

- (OFXAccountClientParameters *)accountClientParametersForAgentName:(NSString *)agentName;
{
    OFXAccountClientParameters *parameters = [super accountClientParametersForAgentName:agentName];
    
    if ([agentName isEqual:OFXTestFirstAgentName]) {
        parameters.currentFrameworkVersion = [[OFVersionNumber alloc] initWithVersionString:@"9999"];
    }

    return parameters;
}

- (void)testSyncRepositoryTooNew;
{
    // Start the first agent and wait for it to sync once.
    __block BOOL finished = NO;
    [[self agentA] sync:^{
        finished = YES;
    }];
    [self waitUntil:^{ return finished; }];
    
    // Try to start the second agent. It should fail.
    [NSError suppressingLogsWithUnderlyingDomain:OFXErrorDomain code:OFXAccountRepositoryTooNew action:^{
        finished = NO;
        OFXAgent *agentB = self.agentB;
        [agentB sync:^{
            finished = YES;
        }];
        [self waitUntil:^{ return finished; }];
        
        OFXServerAccount *accountB = [agentB.accountRegistry.validCloudSyncAccounts lastObject];
        NSError *accountError = accountB.lastError;
        XCTAssertTrue([accountError hasUnderlyingErrorDomain:OFXErrorDomain code:OFXAccountRepositoryTooNew]);
    }];
}

@end
