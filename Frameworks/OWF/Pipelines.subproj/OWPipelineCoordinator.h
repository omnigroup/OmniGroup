// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFObject.h>

@class NSLock, NSMutableArray;
@class OWAddress, OWPipeline;

@interface OWPipelineCoordinator : OFObject
{
    OWAddress * address;
    OWPipeline *buildingPipeline;
    NSLock *coordinatorLock;
    NSMutableArray *queuedPipelines;
}

+ (OWPipelineCoordinator *)pipelineCoordinatorForAddress:(OWAddress *)anAddress;
- (void)buildPipeInPipeline:(OWPipeline *)aPipeline;
- (void)pipebuildingComplete:(OWPipeline *)aPipeline;
- (void)pipelineAbort:(OWPipeline *)aPipeline;

@end
