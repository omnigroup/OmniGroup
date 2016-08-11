// Copyright 2010-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>
#import <Foundation/NSObjCRuntime.h> // MAX

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE

    #import <UIKit/NSAttributedString.h>

    // iOS doesn't have a superscript attribute
    extern NSString * const OASuperscriptAttributeName;

#else

    #import <AppKit/NSAttributedString.h>

    #define OASuperscriptAttributeName NSSuperscriptAttributeName

#endif

#define OAUnderlineStyle NSUnderlineStyle
#define OAUnderlineByWordMask NSUnderlineByWord

// In OmniStyle's text storage subclass, we add a font descriptor to the attributes for the _desired_ font, leaving the other font attribute around for the best calculated match.
extern NSString * const OAFontDescriptorAttributeName;
