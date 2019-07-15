// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFObject.h>

#import <OmniAppKit/OAColor.h>

@interface OAColorPalette : OFObject

+ (OA_PLATFORM_COLOR_CLASS *)colorForHexString:(NSString *)colorString;
+ (OA_PLATFORM_COLOR_CLASS *)colorForString:(NSString *)colorString;
+ (NSString *)stringForColor:(OA_PLATFORM_COLOR_CLASS *)color;

@end
