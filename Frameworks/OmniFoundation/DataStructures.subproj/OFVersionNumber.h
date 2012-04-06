// Copyright 2004-2005, 2008, 2010-2012 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>
#import <OmniBase/system.h>

@interface OFVersionNumber : NSObject <NSCopying>
{
    NSString *_originalVersionString;
    NSString *_cleanVersionString;
    
    NSUInteger  _componentCount;
    NSUInteger *_components;
}

+ (OFVersionNumber *)userVisibleOperatingSystemVersionNumber;

// Convenience methods for testing the current operating system.  One nice thing about using these (rather than looking up the operating system and comparing it by hand) is that we can remove these methods when they become irrelevant (e.g. when we require Snow Leopard), helping us find and update any code which is unnecessarily trying to support an older operating system.
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
+ (BOOL)isOperatingSystemiOS32OrLater; // iOS 3.2
+ (BOOL)isOperatingSystemiOS40OrLater; // iOS 4.0
+ (BOOL)isOperatingSystemiOS50OrLater; // iOS 5.0
+ (BOOL)isOperatingSystemiOS51OrLater; // iOS 5.1
#else
+ (BOOL)isOperatingSystemLeopardOrLater; // 10.5
+ (BOOL)isOperatingSystemSnowLeopardOrLater; // 10.6
+ (BOOL)isOperatingSystemLionOrLater; // 10.7
+ (BOOL)isOperatingSystemMountainLionOrLater; // 10.8
#endif

- initWithVersionString:(NSString *)versionString;

- (NSString *)originalVersionString;
- (NSString *)cleanVersionString;
- (NSString *)prettyVersionString; // NB: This version string can't be parsed back into an OFVersionNumber. For display only!

- (NSUInteger)componentCount;
- (NSUInteger)componentAtIndex:(NSUInteger)componentIndex;

- (NSComparisonResult)compareToVersionNumber:(OFVersionNumber *)otherVersion;

@end
