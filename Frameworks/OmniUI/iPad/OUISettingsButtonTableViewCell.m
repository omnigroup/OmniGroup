// Copyright 2014-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUISettingsButtonTableViewCell.h>

RCS_ID("$Id$");

#import <OmniAppKit/OAAppearanceColors.h>

@implementation OUISettingsButtonTableViewCell

+ (instancetype)dequeueButtonTableViewCellFromTable:(UITableView *)tableView withLabelText:(NSString *)text;
{
    OUISettingsButtonTableViewCell *result = OB_CHECKED_CAST_OR_NIL(OUISettingsButtonTableViewCell, [tableView dequeueReusableCellWithIdentifier:[self reuseIdentifier]]);
    if (result == nil) {
        result = [[self alloc] initWithLabelText:text];
    } else {
        result.textLabel.text = text;
    }
    return result;
}

+ (NSString *)reuseIdentifier;
{
    return NSStringFromClass(self);
}

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier;
{
    OBASSERT(style == UITableViewCellStyleDefault);
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self != nil) {
        [self _configureDisplayProperties];
    }
    return self;
}

- (instancetype)initWithLabelText:(NSString *)text;
{
    self = [self initWithStyle:UITableViewCellStyleDefault reuseIdentifier:[[self class] reuseIdentifier]];
    if (self != nil) {
        self.textLabel.text = text;
    }
    return self;
}

+ (UIColor *)defaultTextColor;
{
    return [UIColor colorNamed:@"OUISettingsButtonText" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil];
}

+ (UIFont *)defaultFont;
{
    return [UIFont systemFontOfSize:[UIFont labelFontSize]];
}

- (void)didMoveToWindow
{
    [super didMoveToWindow];
    
    // tint color can change when we join a view hierarchy, so update
    if (self.window != nil) {
        [self _reapplyColorToUse];
    }
}

- (void)prepareForReuse;
{
    [super prepareForReuse];
    [self _configureDisplayProperties];
    self.textLabel.text = @"";
    self.textColor = [[self class] defaultTextColor];
}

- (void)setTextColor:(UIColor *)textColor;
{
    if (textColor == _textColor) {
        return;
    }
    
    _textColor = [textColor copy];
    [self _reapplyColorToUse];
}

- (void)setNeedsAppearanceUpdate;
{
    [self _reapplyColorToUse];
}

#pragma mark - Private API

- (void)_configureDisplayProperties;
{
    [self _reapplyColorToUse];
    self.textLabel.font = [[self class] defaultFont];
    self.textLabel.textAlignment = NSTextAlignmentCenter;
    self.accessibilityTraits |= UIAccessibilityTraitLink;
}

- (void)_reapplyColorToUse;
{
    UIColor *colorToUse = _textColor;
    if (self.useTintColor) {
        colorToUse = self.tintColor;
    }
    if (colorToUse == nil) {
        colorToUse = [[self class] defaultTextColor];
    }
    self.textLabel.textColor = colorToUse;
}

@end
