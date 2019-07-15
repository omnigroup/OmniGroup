// Copyright 2001-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFObject.h>

@class OFPreference;

/* Some of our preference keys aren't accessible through NSUserDefaults */
#define OSUSharedPreferencesDomain CFSTR("com.omnigroup.OmniSoftwareUpdate")

#define OSUTrackVisibilityChangedNotification (@"OSUTrackVisibilityChanged")

@interface OSUPreferences : OFObject

// API

// This provides the capability to do a one-time migration of a persistent value from AutomaticSoftwareUpdateCheckEnabled to OSUSendSystemInfoEnabled for relevant platforms.
// r240736 changed the automaticSoftwareUpdateCheckEnabled key from AutomaticSoftwareUpdateCheckEnabled to OSUSendSystemInfoEnabled for <bug:///119795> (Bug: Send Anonymous Data needs to be off by default) when building for iOS.
//
// In the case of OmniFocus-iOS, we prompt in first run for permission to collect system info. In versions <= 2.8, the persistent values was stored in AutomaticSoftwareUpdateCheckEnabled.
// Upon upgrading to 2.8, the user's preference was lost and we now can use this helper to propagate the value.
#if MAC_APP_STORE || TARGET_OS_IPHONE
+ (void)performOneTimeSendSystemInfoPreferenceMigrationIfNecessary;
#endif

// N.B. This is a lie on MAC_APP_STORE and TARGET_OS_IPHONE where it really signifies if the user has given permission to gather system info.
+ (OFPreference *)automaticSoftwareUpdateCheckEnabled;

+ (OFPreference *)checkInterval;
+ (OFPreference *)includeHardwareDetails;
+ (OFPreference *)ignoredUpdates;

+ (NSArray<NSString *> *)visibleTracks;
+ (void)setVisibleTracks:(NSArray<NSString *> *)orderedTrackList;

+ (OFPreference *)unreadNews; // bool
+ (OFPreference *)currentNewsURL; // read or unread.
+ (OFPreference *)newsPublishDate; // date the news item was published by OSU.
@end
