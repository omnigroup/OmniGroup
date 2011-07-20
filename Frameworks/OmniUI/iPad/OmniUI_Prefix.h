// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#ifdef __OBJC__
    #import <Foundation/Foundation.h>
    #import <OmniBase/OmniBase.h>
    #import <UIKit/UIKit.h>
    #import <QuartzCore/QuartzCore.h>
    #import <OmniFoundation/OFNull.h>
    #import <OmniFoundation/NSString-OFSimpleMatching.h>
    #import <OmniFoundation/NSArray-OFExtensions.h>

typedef struct {
    NSInteger value;
    CFStringRef name;
} OUIEnumName;

__private_extern__ const OUIEnumName OUITextDirectionEnumNames[], OUITextSelectionGranularityNames[];
__private_extern__ NSString *OUINameOfEnum(NSInteger v, const OUIEnumName *ns);

#define OUITextDirectionName(d) OUINameOfEnum(d, OUITextDirectionEnumNames)
#define OUISelectionGranularityName(g) OUINameOfEnum(g, OUITextSelectionGranularityNames)

#endif
