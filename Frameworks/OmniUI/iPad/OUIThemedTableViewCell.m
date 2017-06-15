// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIThemedTableViewCell.h>

#import <OmniUI/OUIInspectorAppearance.h>

RCS_ID("$Id$");

@implementation OUIThemedTableViewCell

- (void)prepareForReuse;
{
    [super prepareForReuse];
    self.textLabel.textColor = nil;
    
    if ([OUIInspectorAppearance inspectorAppearanceEnabled])
        [self themedAppearanceDidChange:[OUIInspectorAppearance appearance]];
}

- (void)willMoveToSuperview:(UIView *)superview;
{
    if ([OUIInspectorAppearance inspectorAppearanceEnabled])
        [self themedAppearanceDidChange:[OUIInspectorAppearance appearance]];
}
    
- (void)themedAppearanceDidChange:(OUIThemedAppearance *)changedAppearance;
{
    [super themedAppearanceDidChange:changedAppearance];
    
    OUIInspectorAppearance *appearance = OB_CHECKED_CAST_OR_NIL(OUIInspectorAppearance, changedAppearance);
    self.backgroundColor = appearance.TableCellBackgroundColor;
    self.textLabel.textColor = appearance.TableCellTextColor;
    self.detailTextLabel.textColor = appearance.TableCellDetailTextLabelColor;
}

@end
