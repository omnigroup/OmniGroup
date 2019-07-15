// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

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

OB_HIDDEN extern const OUIEnumName OUITextDirectionEnumNames[], OUITextSelectionGranularityNames[];
NSString *OUINameOfEnum(NSInteger v, const OUIEnumName *ns) OB_HIDDEN;

#define OUITextDirectionName(d) OUINameOfEnum(d, OUITextDirectionEnumNames)
#define OUISelectionGranularityName(g) OUINameOfEnum(g, OUITextSelectionGranularityNames)
