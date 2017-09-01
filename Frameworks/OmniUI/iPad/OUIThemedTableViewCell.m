// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIThemedTableViewCell.h>

#import <OmniUI/OUIInspectorAppearance.h>
#import <OmniUI/UIView-OUIExtensions.h>
#import <OmniUI/OUIImages.h>

RCS_ID("$Id$");

@interface _OUITintableDisclosureIndicatorView : UIView {
@private
    UIImageView *_imageView;
}

+ (instancetype)disclosureIndicatorView;

@end

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
    
    [self setHasTintableDisclosureIndicator:NO];

    if ([OUIInspectorAppearance inspectorAppearanceEnabled]) {
        [self applyDefaultLabelColors];
        UITableView *tableView = [self containingViewOfClass:[UITableView class]];
        [self applyBackgroundColorsForTableView:tableView];
    }
}

- (BOOL)hasTintableDisclosureIndicator;
{
    if (self.accessoryType == UITableViewCellAccessoryNone) {
        UIView *accessoryView = self.accessoryView;
        return [accessoryView isKindOfClass:[_OUITintableDisclosureIndicatorView class]];
    }
    
    return NO;
}

- (void)setHasTintableDisclosureIndicator:(BOOL)usesTintableDisclosureIndicator;
{
    if (usesTintableDisclosureIndicator != self.hasTintableDisclosureIndicator) {
        self.accessoryType = UITableViewCellAccessoryNone;
        self.accessoryView = usesTintableDisclosureIndicator ? [_OUITintableDisclosureIndicatorView disclosureIndicatorView] : nil;
    }
}

- (void)setAccessoryType:(UITableViewCellAccessoryType)accessoryType;
{
    if (accessoryType == UITableViewCellAccessoryDisclosureIndicator) {
        OBASSERT_NOT_REACHED(@"Subclasses of OUIDetailInspectorSliceTableViewCell should use `cell.%@ = YES;` instead.", NSStringFromSelector(@selector(hasTintableDisclosureIndicator)));
    }
    
    [super setAccessoryType:accessoryType];
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
    [self applyDefaultLabelColors];
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


static const CGFloat DisclosureIndicatorLeftMargin = 13;
static const CGFloat DisclosureIndicatorTopMargin = 5;
static const CGFloat DisclosureIndicatorBottomMargin = 5;

static const CGFloat DisclosureIndicatorWidth = 8;
static const CGFloat DisclosureIndicatorHeight = 13;

@implementation _OUITintableDisclosureIndicatorView



+ (instancetype)disclosureIndicatorView;
{
    return [[self alloc] initWithImage:OUIDisclosureIndicatorImage()];
}

- (instancetype)initWithImage:(UIImage *)image;
{
    // Set our frame to our desired size
    CGFloat desiredWidth = DisclosureIndicatorLeftMargin + DisclosureIndicatorWidth;
    CGFloat desiredHeight = DisclosureIndicatorTopMargin + DisclosureIndicatorHeight + DisclosureIndicatorBottomMargin;
    CGRect frame = CGRectMake(0, 0, desiredWidth, desiredHeight);
    
    self = [super initWithFrame:frame];
    if (self == nil) {
        return nil;
    }
    
    _imageView = [[UIImageView alloc] initWithImage:image];
    
    CGRect imageFrame = _imageView.frame; // N.B. auto-sized to fit the image by -initWithImage
    imageFrame.origin.x = DisclosureIndicatorLeftMargin;
    imageFrame.origin.y = DisclosureIndicatorTopMargin;
    _imageView.frame = imageFrame;
    
    [self addSubview:_imageView];
    
    return self;
}

- (void)dealloc;
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)willMoveToSuperview:(UIView *)superview;
{
    if ([OUIInspectorAppearance inspectorAppearanceEnabled]) {
        OUIInspectorAppearance *appearance = OUIInspectorAppearance.appearance;
        [self themedAppearanceDidChange:appearance];
    }
}

#pragma mark OUIInspectorAppearance
- (void)themedAppearanceDidChange:(OUIThemedAppearance *)changedAppearance;
{
    [super themedAppearanceDidChange:changedAppearance];
    
    OUIInspectorAppearance *appearance = OB_CHECKED_CAST_OR_NIL(OUIInspectorAppearance, changedAppearance);
    self.tintColor = appearance.TableCellDetailTextLabelColor;
}

@end

