// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIThemedTableViewCell.h>

#import <OmniUI/OUIInspectorAppearance.h>
#import <OmniUI/UIView-OUIExtensions.h>

RCS_ID("$Id$");

@implementation OUIThemedTableViewCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier;
{
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self == nil) {
        return nil;
    }
    
    [self applyDefaultLabelColors];
    
    return self;
}

- (void)awakeFromNib;
{
    [super awakeFromNib];
    
    [self applyDefaultLabelColors];
}

- (void)prepareForReuse;
{
    [super prepareForReuse];
    
    if ([OUIInspectorAppearance inspectorAppearanceEnabled]) {
        [self applyDefaultLabelColors];
        UITableView *tableView = [self containingViewOfClass:[UITableView class]];
        [self applyBackgroundColorsForTableView:tableView];
    }
}

- (void)willMoveToSuperview:(UIView *)superview;
{
    if ([OUIInspectorAppearance inspectorAppearanceEnabled]) {
        OUIInspectorAppearance *appearance = OUIInspectorAppearance.appearance;
        // This is here because we will likely need to know what tableview we are in in order to pick our default background. But if we have set some of this in cellForRowAtIndexPath: we will blow it away. Maybe we can work something out.
        self.selectedBackgroundView = [[UIView alloc] init];
        [self notifyChildrenThatAppearanceDidChange:appearance];
    }
}

- (void)themedAppearanceDidChange:(OUIThemedAppearance *)changedAppearance;
{
    [super themedAppearanceDidChange:changedAppearance];
    UITableView *tableView = [self containingViewOfClass:[UITableView class]];
    [self applyBackgroundColorsForTableView:tableView];
}

- (void)applyBackgroundColorsForTableView:(nullable UITableView *)tableView;
{
    OUIInspectorAppearance *appearance = OUIInspectorAppearance.appearance;
    self.selectedBackgroundView.backgroundColor = appearance.TableCellSelectedBackgroundColor;
    self.backgroundColor = appearance.TableCellBackgroundColor;
}

- (void)applyDefaultLabelColors;
{
    if ([OUIInspectorAppearance inspectorAppearanceEnabled]) {
        OUIInspectorAppearance *appearance = OUIInspectorAppearance.appearance;
        self.textLabel.textColor = appearance.TableCellTextColor;
        self.detailTextLabel.textColor = appearance.TableCellDetailTextLabelColor;
    }
}

@end
