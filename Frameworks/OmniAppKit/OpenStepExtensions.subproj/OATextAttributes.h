// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFObject.h>
#import <Foundation/NSObjCRuntime.h> // MAX
#import <Foundation/NSAttributedString.h>

#if OMNI_BUILDING_FOR_IOS

    // iOS doesn't have a superscript attribute
    extern NSString * const OASuperscriptAttributeName;

#endif

#if OMNI_BUILDING_FOR_MAC

    #define OASuperscriptAttributeName NSSuperscriptAttributeName

#endif

#if OMNI_BUILDING_FOR_MAC || OMNI_BUILDING_FOR_IOS

#define OALinkAttributeName NSLinkAttributeName

#define OAUnderlineStyle NSUnderlineStyle
#define OAUnderlineStyleNone NSUnderlineStyleNone
#define OAUnderlineStyleSingle NSUnderlineStyleSingle
#define OAUnderlineStyleThick NSUnderlineStyleThick
#define OAUnderlineStyleDouble NSUnderlineStyleDouble
#define OAUnderlinePatternSolid NSUnderlinePatternSolid
#define OAUnderlinePatternDot NSUnderlinePatternDot
#define OAUnderlinePatternDash NSUnderlinePatternDash
#define OAUnderlinePatternDashDot NSUnderlinePatternDashDot
#define OAUnderlinePatternDashDotDot NSUnderlinePatternDashDotDot
#define OAUnderlineByWord NSUnderlineByWord


#else

extern NSString * const OALinkAttributeName;

typedef NS_ENUM(NSInteger, OAUnderlineStyle) {
    OAUnderlineStyleNone          = 0x00,
    OAUnderlineStyleSingle        = 0x01,
    OAUnderlineStyleThick         = 0x02,
    OAUnderlineStyleDouble        = 0x09,

    OAUnderlinePatternSolid       = 0x0000,
    OAUnderlinePatternDot         = 0x0100,
    OAUnderlinePatternDash        = 0x0200,
    OAUnderlinePatternDashDot     = 0x0300,
    OAUnderlinePatternDashDotDot  = 0x0400,

    OAUnderlineByWord             = 0x8000
};



#endif

#define OAUnderlineByWordMask NSUnderlineByWord

// In OmniStyle's text storage subclass, we add a font descriptor to the attributes for the _desired_ font, leaving the other font attribute around for the best calculated match.
extern NSString * const OAFontDescriptorAttributeName;
