// Copyright 2013-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/Foundation.h>
#import <OmniFoundation/OFNetStateNotifier.h>
#import <OmniFoundation/OFNetStateRegistration.h>
#import <OmniFoundation/OFXMLIdentifier.h>
#import <OmniFoundation/OFUtilities.h>
#import <OmniFoundation/NSData-OFExtensions.h>

RCS_ID("$Id$")

static NSString * GroupIdentifier = @"OFNetStateSet";

@interface Controller : NSObject <OFNetStateNotifierDelegate>
@end

@implementation Controller
{
    NSString *_memberIdentifier;
    OFNetStateNotifier *_notifier;
    OFNetStateRegistration *_registration;
    NSTimer *_resetTimer;
}

- init;
{
    if (!(self = [super init]))
        return nil;
    
    _memberIdentifier = OFXMLCreateID();
    
    [self _resetTimerFired:nil];
    
    _registration = [[OFNetStateRegistration alloc] initWithGroupIdentifier:GroupIdentifier memberIdentifier:_memberIdentifier name:[NSString stringWithFormat:@"%@.%d", OFHostName(), getpid()] state:[NSData randomDataOfLength:16]];
    
    _resetTimer = [NSTimer scheduledTimerWithTimeInterval:5 target:self selector:@selector(_resetTimerFired:) userInfo:Nil repeats:YES];
    
    return self;
}

- (void)run;
{
    [[NSRunLoop currentRunLoop] run];
}

- (void)dealloc;
{
    [_notifier invalidate];
}

#pragma mark - OFNetStateNotifierDelegate

- (void)netStateNotifierStateChanged:(OFNetStateNotifier *)notifier;
{
    NSLog(@"state changed");
}

#pragma mark - Private

- (void)_resetTimerFired:(NSTimer *)timer;
{
    [_notifier invalidate];
    
    _notifier = [[OFNetStateNotifier alloc] initWithMemberIdentifier:_memberIdentifier];
    _notifier.monitoredGroupIdentifiers = [NSSet setWithObject:GroupIdentifier];
    _notifier.delegate = self;
}

@end

@interface Clients : NSObject
@end
@implementation Clients
{
    NSTimer *_timer;
    NSMutableArray *_registrations;
}

- (void)run;
{
    _registrations = [NSMutableArray new];
    _timer = [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(_timerFired:) userInfo:nil repeats:YES];
}

- (void)_timerFired:(NSTimer *)timer;
{
    static NSUInteger counter = 0;
    NSUInteger registrationCount = [_registrations count];
    if (registrationCount < 300) {
        OFNetStateRegistration *registration = [[OFNetStateRegistration alloc] initWithGroupIdentifier:GroupIdentifier memberIdentifier:OFXMLCreateID() name:[NSString stringWithFormat:@"%@.%d.%ld", OFHostName(), getpid(), counter++] state:[NSData randomDataOfLength:16]];
        [_registrations addObject:registration];
    } else {
        for (NSUInteger i = 0; i < arc4random() % 50; i++) {
            OFNetStateRegistration *registration = [_registrations firstObject];
            [registration invalidate];
            [_registrations removeObjectAtIndex:0];
        }
    }
}

@end

int main(int argc, const char * argv[])
{
    @autoreleasepool {
        Clients *clients = [[Clients alloc] init];
        [clients run];
        
        Controller *controller = [[Controller alloc] init];
        [controller run];
    }
    return 0;
}

