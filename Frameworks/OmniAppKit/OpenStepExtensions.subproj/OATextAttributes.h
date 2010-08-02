// Copyright 2010 Omni Development, Inc.  All rights reserved.
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
#else
#define OABackgroundColorAttributeName NSBackgroundColorAttributeName
#define OALinkAttributeName NSLinkAttributeName
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
