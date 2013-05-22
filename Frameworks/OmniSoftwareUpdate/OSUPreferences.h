// Copyright 2001-2006,2009-2010, 2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>

@class OFPreference;
@class OSUItem;

/* Some of our preference keys aren't accessible through NSUserDefaults */
#define OSUSharedPreferencesDomain CFSTR("com.omnigroup.OmniSoftwareUpdate")

#define OSUTrackVisibilityChangedNotification (@"OSUTrackVisibilityChanged")

@interface OSUPreferences : OFObject

// API
+ (OFPreference *)automaticSoftwareUpdateCheckEnabled;
+ (OFPreference *)checkInterval;
+ (OFPreference *)includeHardwareDetails;
+ (OFPreference *)includeOpenGLDetails;
+ (OFPreference *)ignoredUpdates;

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE // Not including OSUItem on iOS currently
+ (void)setItem:(OSUItem *)anItem isIgnored:(BOOL)shouldBeIgnored;
+ (BOOL)itemIsIgnored:(OSUItem *)anItem;
#endif

+ (NSArray *)visibleTracks;
+ (void)setVisibleTracks:(NSArray *)orderedTrackList;

@end
