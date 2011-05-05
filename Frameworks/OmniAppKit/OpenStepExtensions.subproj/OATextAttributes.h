// Copyright 2010-2011 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
#import <CoreText/CTStringAttributes.h>
#else
#import <AppKit/NSAttributedString.h>
#endif

// Text attributes that have no matching attribute in CoreText
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
extern NSString * const OABackgroundColorAttributeName;
extern NSString * const OALinkAttributeName;
extern NSString * const OAStrikethroughStyleAttributeName;
extern NSString * const OAStrikethroughColorAttributeName;
extern NSUInteger const OAUnderlineByWordMask;
#else
#define OABackgroundColorAttributeName NSBackgroundColorAttributeName
#define OALinkAttributeName NSLinkAttributeName
#define OAStrikethroughStyleAttributeName NSStrikethroughStyleAttributeName
#define OAStrikethroughColorAttributeName NSStrikethroughColorAttributeName
#define OAUnderlineByWordMask NSUnderlineByWordMask
#endif

// Text attributes that we can map right across
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
#define OA_TEXT_KEY(mac,ipad) ((id)ipad)
#else
#define OA_TEXT_KEY(mac,ipad) (mac)
#endif

#define OAForegroundColorAttributeName OA_TEXT_KEY(NSForegroundColorAttributeName, kCTForegroundColorAttributeName)
#define OAStrokeWidthAttributeName OA_TEXT_KEY(NSStrokeWidthAttributeName, kCTStrokeWidthAttributeName)
#define OAStrokeColorAttributeName OA_TEXT_KEY(NSStrokeColorAttributeName, kCTStrokeColorAttributeName)
#define OAFontAttributeName OA_TEXT_KEY(NSFontAttributeName, kCTFontAttributeName)
#define OASuperscriptAttributeName OA_TEXT_KEY(NSSuperscriptAttributeName,kCTSuperscriptAttributeName)
#define OAUnderlineStyleAttributeName OA_TEXT_KEY(NSUnderlineStyleAttributeName, kCTUnderlineStyleAttributeName)
#define OAUnderlineColorAttributeName OA_TEXT_KEY(NSUnderlineColorAttributeName, kCTUnderlineColorAttributeName)
#define OAParagraphStyleAttributeName OA_TEXT_KEY(NSParagraphStyleAttributeName, kCTParagraphStyleAttributeName)

// In OmniStyle's text storage subclass, we add a font descriptor to the attributes for the _desired_ font, leaving the other font attribute around for the best calculated match.
extern NSString * const OAFontDescriptorAttributeName;
