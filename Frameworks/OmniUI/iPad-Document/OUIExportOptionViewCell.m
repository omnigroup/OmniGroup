// Copyright 2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIExportOptionViewCell.h"

RCS_ID("$Id$")

@implementation OUIExportOptionViewCell

- (void)awakeFromNib;
{
    [self.button setTitleColor:[UIColor colorWithRed:0.196 green:0.224 blue:0.29 alpha:1] forState:UIControlStateNormal];
    [self.button setTitleShadowColor:[UIColor colorWithWhite:1 alpha:.5] forState:UIControlStateNormal];
    self.button.titleLabel.numberOfLines = 2;
    self.button.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.button.titleLabel.lineBreakMode = NSLineBreakByWordWrapping;
    self.button.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    self.button.titleEdgeInsets = (UIEdgeInsets){
        .top = 128, // 128 is the icon image width and height.
        .right = 0,
        .bottom = 0,
        .left = -128
    };
}

@end
