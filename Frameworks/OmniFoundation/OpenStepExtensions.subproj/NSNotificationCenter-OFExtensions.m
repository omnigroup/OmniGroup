// Copyright 1998-2005, 2007-2008, 2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSNotificationCenter-OFExtensions.h>

#import <OmniFoundation/OFObject-Queue.h>

RCS_ID("$Id$")

@implementation NSNotificationCenter (OFExtensions)

- (void)addObserver:(id)observer selector:(SEL)aSelector name:(NSString *)aName objects:(NSArray *)objects;
{
    for (id object in objects)
        [self addObserver:observer selector:aSelector name:aName object:object];
}

- (void)removeObserver:(id)observer name:(NSString *)aName objects:(NSArray *)objects;
{
    for (id object in objects)
        [self removeObserver:observer name:aName object:object];
}

- (void)mainThreadPostNotificationName:(NSString *)aName object:(id)anObject;
    // Asynchronously post a notification in the main thread
{
    [self mainThreadPerformSelector:@selector(postNotificationName:object:) withObject:aName withObject:anObject];
}

- (void)mainThreadPostNotificationName:(NSString *)aName object:(id)anObject userInfo:(NSDictionary *)aUserInfo;
    // Asynchronously post a notification in the main thread
{
    [self mainThreadPerformSelector:@selector(postNotificationName:object:userInfo:) withObject:aName withObject:anObject withObject:aUserInfo];
}

@end
