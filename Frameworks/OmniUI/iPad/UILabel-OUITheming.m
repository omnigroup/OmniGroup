// Copyright 2010-2012 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/UILabel-OUITheming.h>

#import <OmniUI/OUIInspectorWell.h>
#import <OmniUI/OUIDrawing.h>

RCS_ID("$Id$");

@implementation UILabel (OUITheming)

- (void)applyStyle:(OUILabelStyle)style;
{
    self.opaque = NO;
    self.backgroundColor = nil;
    self.textColor = [OUIInspectorWell textColor];
    self.shadowColor = OUIShadowColor(OUIShadowTypeDarkContentOnLightBackground);
    self.shadowOffset = OUIShadowOffset(OUIShadowTypeDarkContentOnLightBackground);

    switch (style) {
        case OUILabelStyleInspectorSliceGroupHeading:
            self.font = [UIFont fontWithName:@"HelveticaNeue-Bold" size:17.0];
            break;
            
        case OUILabelStyleInspectorSliceInstructionText:
            self.font = [UIFont fontWithName:@"HelveticaNeue" size:16.0];
            break;
            
        default:
            OBASSERT_NOT_REACHED("Invalid OUILabelStyle.");
            break;
    }
}

@end
