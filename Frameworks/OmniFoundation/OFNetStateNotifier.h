// Copyright 2008-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>

/*
 Allows processes on the same network to communitate small state changes. For example, process that synchronize documents can publish a state change when they've been edited and new changes are available for other processes on the network to synchronize.
 
 Each instance can participate in multiple groups, so typically only one instance of this class would exist and it would be configured by the application to listen to different groups as needed. By default no groups are listened to (and so no notifications will be posted).
 */

@class OFNetStateNotifier;

@protocol OFNetStateNotifierDelegate <NSObject>

// Some peer changed its state for one of the accounts that this notifier monitors. Always dispatched on the main queue.
- (void)netStateNotifierStateChanged:(OFNetStateNotifier *)notifier;

@end

@interface OFNetStateNotifier : NSObject

- initWithMemberIdentifier:(NSString *)memberIdentifier NS_EXTENSION_UNAVAILABLE_IOS("This depends on UIApplication, which isn't available in application extensions");

- (void)invalidate;

@property(nonatomic,readonly) NSString *memberIdentifier;
@property(nonatomic,copy) NSSet *monitoredGroupIdentifiers;

@property(nonatomic,weak) id <OFNetStateNotifierDelegate> delegate;

// Debugging
@property(nonatomic,copy) NSString *name; // Not transmitted on the network, just for debugging

@end
