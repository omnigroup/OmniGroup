// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIThemedTableViewCell.h>

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

- (void)applyBackgroundColorsForTableView:(nullable UITableView *)tableView;
{
    self.selectedBackgroundView.backgroundColor = [UIColor colorNamed:@"TableCellSelectedBackgroundColor" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil];
    self.backgroundColor = [UIColor colorNamed:@"TableCellBackgroundColor" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil];
}

- (void)applyDefaultLabelColors;
{
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

@end

