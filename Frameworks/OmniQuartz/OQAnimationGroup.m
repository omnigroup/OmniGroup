// Copyright 2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniQuartz/OQAnimationGroup.h>

RCS_ID("$Id$");

@implementation OQAnimationGroup

- (void)dealloc;
{
    [completionHandler release];
    [super dealloc];
}

- (id)copyWithZone:(NSZone *)zone;
{
    OQAnimationGroup *copy = [super copyWithZone:zone];
    copy->completionHandler = [completionHandler copy];
    return copy;
}

- (void)setCompletionHandler:(void (^)(BOOL finished))completion;
{
    completion = [completion copy];
    [completionHandler release];
    completionHandler = completion;
}

- (void)animationDidComplete:(BOOL)flag;
{
    if (completionHandler) {
        DEBUG_ANIMATION(@"animationDidComplete %@ completion state: %d.  Perform completion block.", self, flag); 
        completionHandler(flag);
    }
}

@end
