// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIInspectorLabel.h>

#import <OmniUI/OUIDrawing.h>
#import <OmniUI/OUIInspector.h>
#import <OmniUI/OUIInspectorAppearance.h>

RCS_ID("$Id$");

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

- (void)willMoveToSuperview:(UIView *)newSuperview
{
    if ([OUIInspectorAppearance inspectorAppearanceEnabled]) {
        [self notifyChildrenThatAppearanceDidChange:OUIInspectorAppearance.appearance];
    }
}

- (void)themedAppearanceDidChange:(OUIThemedAppearance *)changedAppearance;
{
    [super themedAppearanceDidChange:changedAppearance];
    
    OUIInspectorAppearance *appearance = OB_CHECKED_CAST_OR_NIL(OUIInspectorAppearance, changedAppearance);
    
    self.textColor = appearance.InspectorTextColor;
    if (OUIInspectorAppearance.currentTheme == OUIThemedAppearanceThemeDark) {
        self.shadowColor = OUIShadowColor(OUIShadowTypeLightContentOnDarkBackground);
        self.shadowOffset = OUIShadowOffset(OUIShadowTypeLightContentOnDarkBackground);
    } else {
        self.shadowColor = OUIShadowColor(OUIShadowTypeDarkContentOnLightBackground);
        self.shadowOffset = OUIShadowOffset(OUIShadowTypeDarkContentOnLightBackground);
    }
}


@end
