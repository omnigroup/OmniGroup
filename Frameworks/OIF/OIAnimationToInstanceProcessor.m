// Copyright 1998-2005, 2010-2012 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OIAnimationToInstanceProcessor.h"

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>
#import <OWF/OWF.h>

#import <OIF/OIAnimation.h>
#import <OIF/OIAnimationInstance.h>
#import <OIF/OIImage.h>

RCS_ID("$Id$")

@implementation OIAnimationToInstanceProcessor

+ (void)didLoad;
{
    [self registerProcessorClass:self fromContentTypeString:@"omni/animation" toContentTypeString:@"omni/image" cost:0.1f producingSource:NO];
}

- initWithContent:(OWContent *)initialContent context:(id <OWProcessorContext>)aPipeline;
{
    if (!(self = [super initWithContent:initialContent context:aPipeline]))
        return nil;

    animation = [initialContent objectValue];
    OBASSERT([animation isKindOfClass:[OIAnimation class]]);
    [animation retain];

    return self;
}

- (void)dealloc;
{
    [animation release];
    [super dealloc];
}

// Normally, startProcessing invokes -processInThread in a subthread, which calls a couple of status-updating methods and calls -process. There's no need to create a subthread for something this simple, however.
- (void)startProcessing;
{
    OBFinishPorting; // 64->32 warnings; if we even keep this class/framework
#if 0    
    OWContent *newContent;
    OIAnimationInstance *animationInstance;
    
    [self processBegin];
    animationInstance = (OIAnimationInstance *)[animation animationInstance];

    // Do think for OIAnimationInstances, not frames.
    if ([animationInstance isKindOfClass:[OIAnimationInstance class]]) {
        int animationLimitMode = [[pipeline preferenceForKey:@"OIAnimationLimitationMode"] integerValue];
        unsigned int aLoopCount = [animation loopCount];
        int loopSeconds = -1;
        switch (animationLimitMode) {
            case OIAnimationAnimateForever:
                break;
            
            case OIAnimationAnimateOnce:
                aLoopCount = MIN(aLoopCount, 1U);
                break;
            
            case OIAnimationAnimateThrice:
                aLoopCount = MIN(aLoopCount, 3U);
                break;
            
            case OIAnimationAnimateSeconds:
                aLoopCount = OIAnimationInfiniteLoopCount;
                loopSeconds = [[OFPreference preferenceForKey:@"OIAnimationLimitationSeconds"] integerValue];
                break;
            
            case OIAnimationAnimateNever:
                aLoopCount = 0;
                break;
            
            default:
                break;
        }
        
        [animationInstance setLoopCount:aLoopCount];
        [animationInstance setLoopSeconds:loopSeconds];
    }
    
    newContent = [(OWContent *)[OWContent alloc] initWithContent:animationInstance];
    [newContent markEndOfHeaders];
    [pipeline addContent:newContent fromProcessor:self flags:OWProcessorTypeDerived];
    [newContent release];

    [self processEnd];
    [self retire];
#endif
}
    
@end
