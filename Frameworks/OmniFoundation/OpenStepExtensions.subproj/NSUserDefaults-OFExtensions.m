// Copyright 1997-2005, 2007-2008, 2011 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSUserDefaults-OFExtensions.h>

#import <OmniFoundation/OFPreference.h>

RCS_ID("$Id$")

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
#import <OmniFoundation/OFScheduler.h>
#import <OmniFoundation/OFScheduledEvent.h>

@interface NSUserDefaults (OFPrivate)
- (void)_doSynchronize;
- (void)_scheduleSynchronizeEvent;
@end
#endif

NSString * const OFUserDefaultsRegistrationItemName = @"defaultsDictionary";

@implementation NSUserDefaults (OFExtensions)

// OFBundleRegistryTarget informal protocol

+ (void)registerItemName:(NSString *)itemName bundle:(NSBundle *)bundle description:(NSDictionary *)description;
{
    if ([itemName isEqualToString:OFUserDefaultsRegistrationItemName]) {
        [[self standardUserDefaults] registerDefaults:description];
        [OFPreference recacheRegisteredKeys];
    }
}

- (void)autoSynchronize;
{
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    [self synchronize];
#else
    // -_scheduleSynchronizeEvent pulls in OFScheduler and all that.  We might pull that in later anyway, but for now not so much.
    [self _scheduleSynchronizeEvent];
#endif
}

@end

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
@implementation NSUserDefaults (OFPrivate)

// TODO: Make pendingEventLock and pendingEvent instance-specific variables

static NSLock *_pendingEventLock = nil;
static OFScheduledEvent *_pendingEvent = nil;

+ (void)didLoad;
{
    _pendingEventLock = [[NSLock alloc] init];
}

- (void)_doSynchronize;
{
    [_pendingEventLock lock];
    [_pendingEvent release];
    _pendingEvent = nil;
    [_pendingEventLock unlock];
    [self synchronize];
}

- (void)_scheduleSynchronizeEvent;
{
    [_pendingEventLock lock];
    if (_pendingEvent == nil)
        _pendingEvent = [[[OFScheduler mainScheduler] scheduleSelector:@selector(_doSynchronize) onObject:self afterTime:60.0] retain];
    [_pendingEventLock unlock];
}

@end
#endif
