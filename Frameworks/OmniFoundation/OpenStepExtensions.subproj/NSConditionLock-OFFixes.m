// Copyright 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSLock.h>
#import <OmniBase/OmniBase.h>

#import <OmniFoundation/NSDate-OFExtensions.h>

RCS_ID("$Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniFoundation/OpenStepExtensions.subproj/NSConditionLock-OFFixes.m 103130 2008-07-22 01:14:47Z wiml $")

@implementation NSConditionLock (OFFixes)

static BOOL (*originalLockWhenConditionBeforeDate)(id self, SEL _cmd, int condition, NSDate *limit);

+ (void)performPosing;
{
    originalLockWhenConditionBeforeDate = (typeof(originalLockWhenConditionBeforeDate))OBReplaceMethodImplementationWithSelector(self, @selector(lockWhenCondition:beforeDate:), @selector(replacement_lockWhenCondition:beforeDate:));
}

#define LIMIT_DATE_ACCURACY 0.1

- (BOOL)replacement_lockWhenCondition:(NSInteger)condition beforeDate:(NSDate *)limitDate;
{
    do {
        BOOL locked = originalLockWhenConditionBeforeDate(self, _cmd, condition, limitDate);
        if (locked)
            return YES; // We have the lock

        NSTimeInterval limitDateInterval = [limitDate timeIntervalSinceNow];
        if (limitDateInterval <= 0.0)
            return NO; // Timeout reached

        // We woke up too early (which is the whole reason we need this patch).  Let's try an alternate means of sleeping:  -[NSDate(OFExtensions) sleepUntilDate] (which calls +[NSThread sleepUntilDate:]).
#ifdef DEBUG_kc
        NSLog(@"%@: Woke up %5.3f (%g) seconds too early, sleeping until %@", [self shortDescription], limitDateInterval, limitDateInterval, limitDate);
#endif

        if (limitDateInterval < LIMIT_DATE_ACCURACY) {
            // We're close to the first event's date, let's only sleep until that precise date.
            [limitDate sleepUntilDate];
        } else {
            // We woke up much earlier than we'd like.  Let's sleep for a little while before we check our condition again
            [[NSDate dateWithTimeIntervalSinceNow:LIMIT_DATE_ACCURACY] sleepUntilDate];
        }
    } while (1);
}

@end
