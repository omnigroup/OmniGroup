// Copyright 2003-2011, 2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Availability.h>

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
#import <UIKit/NSParagraphStyle.h>
#else

#import <AppKit/NSParagraphStyle.h>

// UIKit cleaned up these names -- let's use the nicer names in shared code.
#define NSTextAlignmentLeft NSLeftTextAlignment
#define NSTextAlignmentRight NSRightTextAlignment
#define NSTextAlignmentCenter NSCenterTextAlignment
#define NSTextAlignmentJustified NSJustifiedTextAlignment
#define NSTextAlignmentNatural NSNaturalTextAlignment

#endif
