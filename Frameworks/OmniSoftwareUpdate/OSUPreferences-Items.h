// Copyright 2001-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniSoftwareUpdate/OSUPreferences.h>

// This category is in its own file so that the iOS library can easily avoid importing it, since this header isn't exportable (since OSU_FULL is defined in the targets right now).
#import "OSUFeatures.h"

@class OSUItem;

@interface OSUPreferences (Items)
+ (void)setItem:(OSUItem *)anItem isIgnored:(BOOL)shouldBeIgnored;
+ (BOOL)itemIsIgnored:(OSUItem *)anItem;
@end
