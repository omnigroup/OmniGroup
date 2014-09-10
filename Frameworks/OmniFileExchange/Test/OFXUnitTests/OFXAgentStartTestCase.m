// Copyright 2013-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFXTestCase.h"

RCS_ID("$Id$")

@interface OFXAgentStartTestCase : OFXTestCase
@end

@implementation OFXAgentStartTestCase

- (NSSet *)automaticallyStartedAgentNames;
{
    return nil;
}

- (void)testStartAndStopAgent;
{
    OFXAgent *agent = self.agentA;
    [agent applicationLaunched];
    [self stopAgents];
}

// TODO: This produces various errors, but we probably don't need it in real apps. Once more of the real needs are worked out, it would be great to make this work in whatever structure we end up with.
#if 0
- (void)testQuicklyRestartAgent;
{
    OFXAgent *agent = self.agentA;
    
    for (NSUInteger repeat = 0; repeat < 10; repeat++) {
        [agent applicationLaunched];
        [agent applicationWillTerminateWithCompletionHandler:nil]; // Don't use -stopAgent since that is synchronous and defeats the point of the test.
    }
}
#endif

// TODO: Test that if the local documents directory is deleted while the agent isn't running (or maybe even while running) that we recreate it and download everything again? Or should we treat it as deleting all your files (yikes!)

@end
