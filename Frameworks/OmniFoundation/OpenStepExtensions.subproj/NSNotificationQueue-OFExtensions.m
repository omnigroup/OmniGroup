// Copyright 1998-2005, 2007 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSNotificationQueue-OFExtensions.h>

#import <OmniFoundation/OFMessageQueue.h>

RCS_ID("$Id$")

@implementation NSNotificationQueue (OFExtensions)

+ (void)enqueueNotificationInMainThread:(NSNotification *)aNote postingStyle:(NSPostingStyle)aStyle
{
    NSArray *arguments = [[NSArray alloc] initWithObjects:aNote, [NSNumber numberWithInt:aStyle], nil];
    [[OFMessageQueue mainQueue] queueSelector:@selector(_mainThreadEnqueue:) forObject:self withObject:arguments];
    [arguments release];
}

+ (void)_mainThreadEnqueue:(NSArray *)parameters
{
    NSNotification *aNote = [parameters objectAtIndex:0];
    NSPostingStyle aStyle = [[parameters objectAtIndex:1] intValue];

    [[NSNotificationQueue defaultQueue] enqueueNotification:aNote postingStyle:aStyle];
}


- (void) enqueueNotificationName: (NSString *) name
                          object: (id) object
                    postingStyle: (NSPostingStyle) postingStyle;
{
    NSNotification *notification;

    notification = [NSNotification notificationWithName: name object: object];

    [self enqueueNotification: notification postingStyle: postingStyle];
}

- (void) enqueueNotificationName: (NSString *) name
                          object: (id) object
                        userInfo: (NSDictionary *) userInfo
                    postingStyle: (NSPostingStyle) aStyle;
{
    NSNotification *notification;

    notification = [NSNotification notificationWithName: name
                                                 object: object
                                               userInfo: userInfo];

    [self enqueueNotification: notification postingStyle: aStyle];
}

- (void) enqueueNotificationName: (NSString *) name
                          object: (id) object
                        userInfo: (NSDictionary *) userInfo
                    postingStyle: (NSPostingStyle) aStyle
                    coalesceMask: (unsigned) coalesceMask
                        forModes: (NSArray *) modes;
{
    NSNotification *notification;

    notification = [NSNotification notificationWithName: name
                                                 object: object
                                               userInfo: userInfo];

    [self enqueueNotification: notification
                 postingStyle: aStyle
                 coalesceMask: coalesceMask
                     forModes: modes];
}

- (void) dequeueNotificationsMatching: (NSString *) name
                               object: (id) object
                         coalesceMask: (unsigned) coalesceMask;
{
    NSNotification *notification;

    notification = [NSNotification notificationWithName: name
                                                 object: object];

    [self dequeueNotificationsMatching: notification
                          coalesceMask: coalesceMask];
}

- (void) firePendingNotifications
{
    NSRunLoop *runLoop;
    NSString  *mode;

    // This hack depends upon the fact that when you call -limitDateForMode: on NSRunLoop
    // it will do some private API goop with NSNotificationQueue to post any pending
    // notification.
    
    runLoop = [NSRunLoop currentRunLoop];
    if (!(mode = [runLoop currentMode]))
        mode = NSDefaultRunLoopMode;
    [runLoop limitDateForMode: mode];
}

@end
