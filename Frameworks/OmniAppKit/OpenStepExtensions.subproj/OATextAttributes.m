// Copyright 2010-2011 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OATextAttributes.h>

#import <OmniBase/OmniBase.h>

RCS_ID("$Id$");

#define UNDERLINE_BY_WORD_MASK (0x8000) // Not documented anywhere. We'll assert this stays true on Mac OS X

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
NSString * const OABackgroundColorAttributeName = @"OABackgroundColorAttributeName";
NSString * const OALinkAttributeName = @"OALinkAttributeName";
NSString * const OAStrikethroughStyleAttributeName = @"OAStrikethroughStyleAttributeName";
NSString * const OAStrikethroughColorAttributeName = @"OAStrikethroughColorAttributeName";
NSUInteger const OAUnderlineByWordMask = UNDERLINE_BY_WORD_MASK;
#else

static void _checkUnderlineByWordMaks(void) __attribute__((constructor));
static void _checkUnderlineByWordMaks(void)
{
    OBASSERT(NSUnderlineByWordMask == UNDERLINE_BY_WORD_MASK);
}

#endif

NSString * const OAFontDescriptorAttributeName = @"OAFontDescriptor";



