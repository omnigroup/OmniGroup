// Copyright 2003-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OASpringLoadHelper.h"

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>

RCS_ID("$Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniAppKit/Widgets.subproj/OASpringLoadHelper.m 66043 2005-07-25 21:17:05Z kc $");

@interface OASpringLoadHelper (Private)
+ (NSNumberFormatter *)_numberFormatter;
- (id)_initWithDelegate:(id <OASpringLoadHelper>)aDelegate;
- (void)_startSpringTimer;
- (BOOL)_shouldFlash;
- (void)_startFlashing;
- (void)_flash;
- (void)_stopSpringTimer;
- (void)_springLoad;
@end

@implementation OASpringLoadHelper

+ (OASpringLoadHelper *)springLoadHelperWithDelegate:(id <OASpringLoadHelper>)aDelegate;
{
    return [[[OASpringLoadHelper alloc] _initWithDelegate:aDelegate] autorelease];
}

// Init and dealloc

- (void)dealloc;
{
    [self _stopSpringTimer];

    nonretainedDelegate = nil;

    [super dealloc];
}

// API

- (void)beginSpringLoad;
{
    NSPoint startPoint = [NSEvent mouseLocation];

    slopRect = NSMakeRect(startPoint.x - 2.0, startPoint.y - 2.0, 4.0, 4.0);

    [self _startSpringTimer];
}

- (void)updateSpringLoad;
{
    // Make sure that the spring load only fires if the user holds the mouse relatively still
    if (!NSPointInRect([NSEvent mouseLocation], slopRect)) {
        [self cancelSpringLoad];
        [self beginSpringLoad];
    }
}

- (void)cancelSpringLoad;
{
    [self _stopSpringTimer];
}

@end

@implementation OASpringLoadHelper (Private)

+ (NSNumberFormatter *)_numberFormatter;
{
    static NSNumberFormatter *numberFormatter = nil;

    if (numberFormatter == nil)
        numberFormatter = [[NSNumberFormatter alloc] init];

    return numberFormatter;
}

- (id)_initWithDelegate:(id <OASpringLoadHelper>)aDelegate;
{
    if ([super init] == nil)
        return nil;

    nonretainedDelegate = aDelegate;

    return self;
}

- (void)_startSpringTimer;
{
    if (springTimer != nil)
        [self _stopSpringTimer];

    double springingDelayMilliseconds = 668.0; // Magic value that's Finder's default
    CFPropertyListRef finderDefaultValue = CFPreferencesCopyAppValue((CFStringRef)@"SpringingDelayMilliseconds", (CFStringRef)@"com.apple.finder");
    if (finderDefaultValue != NULL) {
        NSNumber *number = (id)finderDefaultValue;
        if (![number isKindOfClass:[NSNumber class]]) {
            NSString *inputString = [number description];
            NSNumber *outputNumber;
            NSString *errorDescription = nil;

            if ([[isa _numberFormatter] getObjectValue:&outputNumber forString:inputString errorDescription:&errorDescription]) {
                number = outputNumber;
            } else {
                number = nil;
#ifdef DEBUG_kc
                NSLog(@"-[%@ %s]: Unable to convert '%@' to a number: %@", OBShortObjectDescription(self), _cmd, inputString, errorDescription);
#endif
            }
        }
        if (number != nil)
            springingDelayMilliseconds = [number doubleValue];
    }

#ifdef DEBUG_kc
    NSLog(@"-[%@ %s]: Springing delay set to %0.3f seconds (%@=%@)", OBShortObjectDescription(self), _cmd, springingDelayMilliseconds / 1000.0, NSStringFromClass([(id)finderDefaultValue class]), [(id)finderDefaultValue description]);
#endif

    if ([self _shouldFlash]) {
        springTimer = [[NSTimer scheduledTimerWithTimeInterval:(springingDelayMilliseconds / 1000.0) target:self selector:@selector(_startFlashing) userInfo:nil repeats:NO] retain];
    } else {
        springTimer = [[NSTimer scheduledTimerWithTimeInterval:(springingDelayMilliseconds / 1000.0) target:self selector:@selector(_springLoad) userInfo:nil repeats:NO] retain];
    }
}

- (BOOL)_shouldFlash;
{
    return [nonretainedDelegate springLoadHelperShouldFlash:self];
}

- (void)_startFlashing;
{
#ifdef DEBUG_SpringLoad
    NSLog(@"-[%@ %s]", OBShortObjectDescription(self), _cmd);
#endif

    flashCount = 0;

    if (springTimer != nil)
        [self _stopSpringTimer];

    springTimer = [[NSTimer scheduledTimerWithTimeInterval:0.075 target:self selector:@selector(_flash) userInfo:nil repeats:YES] retain];
}

- (void)_flash;
{
#ifdef DEBUG_SpringLoad
    NSLog(@"-[%@ %s]", OBShortObjectDescription(self), _cmd);
#endif

    if (flashCount++ == 4) {
        // The spring load action invoked by -springLoadHelperWantsSpringLoad: may leave the target selected, but we don't necessarily want to leave the flash on since the delegate might not actually select the target on spring load (OmniOutliner might hoist or expand a row, for example).
        [nonretainedDelegate springLoadHelper:self wantsFlash:NO];
        [self _springLoad];
    } else {
        [nonretainedDelegate springLoadHelper:self wantsFlash:!(flashCount % 2 == 0)];
    }
}

- (void)_stopSpringTimer;
{
#ifdef DEBUG_SpringLoad
    NSLog(@"-[%@ %s]", OBShortObjectDescription(self), _cmd);
#endif

    [springTimer invalidate];
    [springTimer release];
    springTimer = nil;
}

- (void)_springLoad;
{
#ifdef DEBUG_SpringLoad
    NSLog(@"-[%@ %s]", OBShortObjectDescription(self), _cmd);
#endif

    if (springTimer != nil)
        [self _stopSpringTimer];

    [nonretainedDelegate springLoadHelperWantsSpringLoad:self];
}

@end
