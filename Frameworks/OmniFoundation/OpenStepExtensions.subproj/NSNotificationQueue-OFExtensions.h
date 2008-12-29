// Copyright 1998-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniFoundation/OpenStepExtensions.subproj/NSNotificationQueue-OFExtensions.h 68913 2005-10-03 19:36:19Z kc $

#import <Foundation/NSNotificationQueue.h>

@class NSDictionary;

@interface NSNotificationQueue (OFExtensions)

+ (void)enqueueNotificationInMainThread:(NSNotification *)aNote
                           postingStyle:(NSPostingStyle)aStyle;

- (void) enqueueNotificationName: (NSString *) name
                          object: (id) object
                    postingStyle: (NSPostingStyle) postingStyle;

- (void) enqueueNotificationName: (NSString *) name
                          object: (id) object
                        userInfo: (NSDictionary *) userInfo
                    postingStyle: (NSPostingStyle) aStyle;

- (void) enqueueNotificationName: (NSString *) name
                          object: (id) object
                        userInfo: (NSDictionary *) userInfo
                    postingStyle: (NSPostingStyle) aStyle
                    coalesceMask: (unsigned) coalesceMask
                        forModes: (NSArray *) modes;

- (void) dequeueNotificationsMatching: (NSString *) name
                               object: (id) object
                         coalesceMask: (unsigned) coalesceMask;

- (void) firePendingNotifications;

@end
