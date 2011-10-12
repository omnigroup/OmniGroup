// Copyright 2010-2011 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UIBarButtonItem.h>

typedef enum {
    OUIAppearanceTypeClear
} OUIAppearanceType;

@interface UIBarButtonItem (OUITheming)

- (void)applyAppearance:(OUIAppearanceType)appearance;


@end
