// Copyright 1997-2005,2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>
#import <Foundation/NSGeometry.h>

@class NSFont;

typedef struct {
    CGFloat size;
    unsigned int bold:1;
    unsigned int italic:1;
} OAFontAttributes;

@interface OAFontCache : OFObject

+ (void)refreshFontSubstitutionDefaults;

+ (NSString *)fontFamilyMatchingName:(NSString *)fontFamily;
+ (NSFont *)fontWithFamily:(NSString *)aFamily attributes:(OAFontAttributes)someAttributes;
+ (NSFont *)fontWithFamily:(NSString *)aFamily size:(CGFloat)size bold:(BOOL)bold italic:(BOOL)italic;
+ (NSFont *)fontWithFamily:(NSString *)aFamily size:(CGFloat)size;

@end
