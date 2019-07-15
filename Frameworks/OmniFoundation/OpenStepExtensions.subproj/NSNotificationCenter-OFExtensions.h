// Copyright 1998-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSNotification.h>

@class NSArray;

@interface NSNotificationCenter (OFExtensions)

- (void)addObserver:(id)observer selector:(SEL)aSelector name:(NSString *)aName objects:(NSArray *)objects;
    // Convenience method for registering an observer for the same notification from many objects

- (void)removeObserver:(id)observer name:(NSString *)aName objects:(NSArray *)objects;
    // Convenience method for removing an observer for the same notification from many objects

- (void)mainThreadPostNotificationName:(NSString *)aName object:(id)anObject;
    // Asynchronously post a notification in the main thread

- (void)mainThreadPostNotificationName:(NSString *)aName object:(id)anObject userInfo:(NSDictionary *)aUserInfo;
    // Asynchronously post a notification in the main thread

@end
