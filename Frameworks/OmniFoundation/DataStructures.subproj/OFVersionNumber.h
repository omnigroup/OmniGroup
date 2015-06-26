// Copyright 2004-2015 Omni Development, Inc. All rights reserved.
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
+ (BOOL)isOperatingSystemiOS90OrLater; // iOS 9.0
#else
+ (BOOL)isOperatingSystemElCapitanOrLater; // 10.11
#endif

- initWithVersionString:(NSString *)versionString;

- (NSString *)originalVersionString;
- (NSString *)cleanVersionString;
- (NSString *)prettyVersionString; // NB: This version string can't be parsed back into an OFVersionNumber. For display only!

- (NSUInteger)componentCount;
- (NSUInteger)componentAtIndex:(NSUInteger)componentIndex;

- (NSComparisonResult)compareToVersionNumber:(OFVersionNumber *)otherVersion;

@end

extern NSString * const OFVersionNumberTransformerName;
