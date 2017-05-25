// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OATextAttributes.h>

#import <OmniBase/OmniBase.h>

RCS_ID("$Id$");

#if OMNI_BUILDING_FOR_IOS
NSString * const OASuperscriptAttributeName = @"OASuperscript";
#endif

NSString * const OAFontDescriptorAttributeName = @"OAFontDescriptor";

#if OMNI_BUILDING_FOR_MAC || OMNI_BUILDING_FOR_IOS
// Have their own attributes via AppKit or UIKit
#else
NSString * const OALinkAttributeName = @"OALinkAttributeName";
#endif
