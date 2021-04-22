// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIInspectorLabel.h>

#import <OmniUI/OUIDrawing.h>
#import <OmniUI/OUIInspector.h>

void OUIConfigureInspectorLabel(UILabel *label)
{
    label.textColor = [OUIInspector labelTextColor];
    label.shadowColor = OUIShadowColor(OUIShadowTypeDarkContentOnLightBackground);
    label.shadowOffset = OUIShadowOffset(OUIShadowTypeDarkContentOnLightBackground);
}

@implementation OUIInspectorLabel

static id _commonInit(OUIInspectorLabel *self)
{
    OUIConfigureInspectorLabel(self);
    return self;
}

- (id)initWithFrame:(CGRect)frame;
{
    if (!(self = [super initWithFrame:frame]))
        return nil;
    return _commonInit(self);
}

- initWithCoder:(NSCoder *)coder;
{
    if (!(self = [super initWithCoder:coder]))
        return nil;
    return _commonInit(self);
}

@end
