// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIInspectorTextWell.h>

@class OAColor;

@interface OUIColorAttributeInspectorWell : OUIInspectorTextWell
{
    BOOL singleSwatch;
}

@property(nonatomic,strong) OAColor *color;
@property(nonatomic) BOOL singleSwatch;
@end
