// Copyright 1998-2005, 2011 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OIF/OIAnimationFrame.h>

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>
#import <OmniAppKit/OmniAppKit.h>
#import <OWF/OWF.h>

RCS_ID("$Id$")

@implementation OIAnimationFrame

static NSString *OIAnimationMinimumDelayIntervalKey = @"OIAnimationMinimumDelayInterval";

- initWithDelayInterval:(NSTimeInterval)aDelayInterval;
{
    NSTimeInterval minimumDelayInterval;

    if (!(self = [super initWithSourceContent:nil]))
	return nil;

    minimumDelayInterval = [[NSUserDefaults standardUserDefaults] floatForKey:OIAnimationMinimumDelayIntervalKey];
    if (aDelayInterval < minimumDelayInterval)
	delayInterval = minimumDelayInterval;
    else
        delayInterval = aDelayInterval;
    return self;
}

- (NSTimeInterval)delayInterval;
{
    return delayInterval;
}

// Debugging

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *debugDictionary;

    debugDictionary = [super debugDictionary];
    [debugDictionary setObject:[NSNumber numberWithDouble:delayInterval] forKey:@"delayInterval"];
    return debugDictionary;
}

@end
