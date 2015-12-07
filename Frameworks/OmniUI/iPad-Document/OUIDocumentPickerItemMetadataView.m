// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUIDocument/OUIDocumentPickerItemMetadataView.h>

#import <OmniUIDocument/OUIDocumentPickerScrollView.h>
#import <OmniUI/UIView-OUIExtensions.h>
#import <OmniUIDocument/OmniUIDocumentAppearance.h>

#import "OUIDocumentParameters.h"

RCS_ID("$Id$");

@interface OUIDocumentNameTextField : UITextField
@end

@implementation OUIDocumentNameTextField

- (CGRect)clearButtonRectForBounds:(CGRect)bounds;
{
    // We have padding to the right of this text field, so jam the clear button all the way to the right edge
    CGRect rect =  [super clearButtonRectForBounds:bounds];
    
    rect.origin.x = CGRectGetMaxX(bounds) - CGRectGetWidth(rect);
    rect.origin.y = floor(CGRectGetMidY(bounds) - CGRectGetHeight(rect) / 2);
    
    return rect;
}

@end

@interface OUIDocumentPickerItemMetadataView ()
@property (nonatomic) BOOL needsConstraintsForAnimation;
- (CGFloat)_nameLabelFontSize;
- (CGFloat)_detailLabelFontSize;
- (CGFloat)_nameHeight;
- (CGFloat)_dateHeight;
@end

@implementation OUIDocumentPickerItemMetadataView
{
    CGFloat _nameLabelWidth;
    BOOL _showsImage;
}

+ (UIColor *)defaultBackgroundColor;
{
    return OAMakeUIColor(kOUIDocumentPickerItemMetadataViewBackgroundColor);
}

+ (UIColor *)defaultEditingBackgroundColor
{
    return OAMakeUIColor(kOUIDocumentPickerItemMetadataViewEditingBackgroundColor);
}

- (void)commonInit
{
    self.opaque = NO;
    [self createSubviews];
    
    _topHairlineView.backgroundColor = [UIColor colorWithWhite:0.85 alpha:1.0];
    _topHairlineView.opaque = NO;
    
    _nameTextField.textAlignment = NSTextAlignmentLeft;
    //_nameTextField.lineBreakMode = NSLineBreakByTruncatingTail;
    _nameTextField.font = [UIFont systemFontOfSize:[self _nameLabelFontSize]];
    _nameTextField.textColor = OAMakeUIColor(kOUIDocumentPickerItemViewNameLabelColor);
    _nameTextField.clearButtonMode = UITextFieldViewModeWhileEditing;
    _nameTextField.autocapitalizationType = UITextAutocapitalizationTypeWords;
    _nameTextField.spellCheckingType = UITextSpellCheckingTypeNo;
    _nameTextField.returnKeyType = UIReturnKeyDone;
    
    _dateLabel.font = [UIFont systemFontOfSize:[self _detailLabelFontSize]];
    _dateLabel.textColor = OAMakeUIColor(kOUIDocumentPickerItemViewDetailLabelColor);
    
    _nameBadgeImageView.alpha = 0;
    _nameBadgeImageView.hidden = YES;
    
    _showsImage = NO;

    self.backgroundColor = [[self class] defaultBackgroundColor];
    self.opaque = NO;
}

- initWithFrame:(CGRect)frame;
{
    if (!(self = [super initWithFrame:frame]))
        return nil;

    [self commonInit];
    
    return self;
}

- (void)createSubviews
{
    NSMutableArray *constraints = [NSMutableArray array];
    
    // top hairline
    _topHairlineView = [[UIView alloc] init];
    [self addSubview:_topHairlineView];
    [constraints addObject:[_topHairlineView.topAnchor constraintEqualToAnchor:self.topAnchor]];
    [constraints addObjectsFromArray:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[_topHairlineView]|"
                                                                             options:kNilOptions
                                                                             metrics:nil
                                                                               views:NSDictionaryOfVariableBindings(_topHairlineView)]];
    [constraints addObject:[NSLayoutConstraint constraintWithItem:_topHairlineView
                                                        attribute:NSLayoutAttributeHeight
                                                        relatedBy:NSLayoutRelationEqual
                                                           toItem:nil
                                                        attribute:NSLayoutAttributeNotAnAttribute
                                                       multiplier:1.0f
                                                         constant:1.0 / [self contentScaleFactor]]];
    
    // labels and status image
    UIView *labels = [[UIView alloc] init];
    _nameTextField = [[OUIDocumentNameTextField alloc] init];
    [_nameTextField setContentHuggingPriority:10 forAxis:UILayoutConstraintAxisHorizontal];
    _dateLabel = [[UILabel alloc] init];
    [_dateLabel setContentHuggingPriority:10 forAxis:UILayoutConstraintAxisHorizontal];
    [labels addSubview:_nameTextField];
    [labels addSubview:_dateLabel];
    
    NSLayoutConstraint *nameShouldBeProportionalHeight = [NSLayoutConstraint constraintWithItem:_nameTextField
                                                                                      attribute:NSLayoutAttributeHeight
                                                                                      relatedBy:NSLayoutRelationEqual
                                                                                         toItem:labels
                                                                                      attribute:NSLayoutAttributeHeight
                                                                                     multiplier:3.0/5.0
                                                                                                 constant:0.0f];
    [constraints addObject:nameShouldBeProportionalHeight];
     
    NSLayoutConstraint *nameToDateVertical = [NSLayoutConstraint constraintWithItem:_dateLabel
                                                                          attribute:NSLayoutAttributeTop
                                                                          relatedBy:NSLayoutRelationEqual
                                                                             toItem:_nameTextField
                                                                          attribute:NSLayoutAttributeBottom
                                                                         multiplier:1.0f
                                                                           constant:kOUIDocumentPickerItemViewNameToDatePadding];
    [constraints addObject:nameToDateVertical];
    
    self.topAndBottomPadding = @[[_nameTextField.topAnchor constraintEqualToAnchor:_nameTextField.superview.topAnchor],
                                 [_dateLabel.superview.bottomAnchor constraintEqualToAnchor:_dateLabel.bottomAnchor]];
    for (NSLayoutConstraint *constraint in self.topAndBottomPadding) {
        constraint.constant = [self topAndBottomPaddingAmount];
    }
    
    [constraints addObjectsFromArray:self.topAndBottomPadding];
    
    [constraints addObjectsFromArray:@[
                                       [_nameTextField.leadingAnchor constraintEqualToAnchor:_nameTextField.superview.leadingAnchor],
                                       [_nameTextField.trailingAnchor constraintEqualToAnchor:_nameTextField.superview.trailingAnchor],
                                       [_dateLabel.leadingAnchor constraintEqualToAnchor:_dateLabel.superview.leadingAnchor],
                                       [_dateLabel.trailingAnchor constraintEqualToAnchor:_dateLabel.superview.trailingAnchor]
                                       ]];
    
    _nameBadgeImageView = [[UIImageView alloc] init];
    
    // put these things in a stack view because then when we hide the statusImage, the labels will automatically grow to fill the space
    UIStackView *horizontalStackView = [[UIStackView alloc] initWithArrangedSubviews:@[labels, _nameBadgeImageView]];
    
    horizontalStackView.axis = UILayoutConstraintAxisHorizontal;
    
    
    [self addSubview:horizontalStackView];
    self.padding = [NSLayoutConstraint constraintWithItem:horizontalStackView
                                                attribute:NSLayoutAttributeLeading
                                                relatedBy:NSLayoutRelationEqual
                                                   toItem:horizontalStackView.superview
                                                attribute:NSLayoutAttributeLeading
                                               multiplier:1.0f
                                                 constant:8];
    [constraints addObject:self.padding];
    [constraints addObject:[NSLayoutConstraint constraintWithItem:horizontalStackView
                                                        attribute:NSLayoutAttributeTrailing
                                                        relatedBy:NSLayoutRelationEqual
                                                           toItem:horizontalStackView.superview
                                                        attribute:NSLayoutAttributeTrailing
                                                       multiplier:1.0f
                                                         constant:-8]];
    [constraints addObjectsFromArray:@[
                                       [horizontalStackView.topAnchor constraintEqualToAnchor:horizontalStackView.superview.topAnchor],
                                       [horizontalStackView.bottomAnchor constraintEqualToAnchor:horizontalStackView.superview.bottomAnchor]
                                       ]];
    
    [NSLayoutConstraint activateConstraints:constraints];
}

- (NSString *)name;
{
    return _nameTextField.text;
}

- (void)setName:(NSString *)name;
{
    _nameTextField.text = name;
}

- (UIImage *)nameBadgeImage;
{
    return _nameBadgeImageView.image;
}
- (void)setNameBadgeImage:(UIImage *)nameBadgeImage;
{
    _nameBadgeImageView.image = nameBadgeImage;
    self.showsImage = (nameBadgeImage != nil);
}

- (BOOL)showsImage;
{
    return _showsImage;
}

- (void)setShowsImage:(BOOL)flag;
{
    if (flag != _showsImage) {
        _showsImage = flag;
        if (_showsImage) {
            [UIView performWithoutAnimation:^{
                _nameBadgeImageView.alpha = 0;
                _nameBadgeImageView.hidden = NO;
            }];
            [UIView animateWithDuration:0.25f animations:^{
                _nameBadgeImageView.alpha = 1;
            }];
        } else {
            [UIView animateWithDuration:0.25f animations:^{
                _nameBadgeImageView.alpha = 0;
            } completion:^(BOOL finished) {
                if (finished) {
                    _nameBadgeImageView.hidden = YES;
                }
            }];
        }
        
        [self setNeedsLayout];
    }
}

- (void)setDoubleSizeFonts:(BOOL)doubleSizeFonts
{
    if (doubleSizeFonts != _doubleSizeFonts) {
        _doubleSizeFonts = doubleSizeFonts;
        self.nameHeightConstraint.constant = doubleSizeFonts ? [self _nameHeight] * 2 : [self _nameHeight];
        self.dateHeightConstraint.constant = doubleSizeFonts ? [self _dateHeight] * 2: [self _dateHeight];
        self.padding.constant = doubleSizeFonts ? self.padding.constant * 2 : self.padding.constant / 2;
        for (NSLayoutConstraint *constraint in self.topAndBottomPadding) {
            constraint.constant = doubleSizeFonts ? [self topAndBottomPaddingAmount] * 2 : [self topAndBottomPaddingAmount];
        }
        [self _resetLabelFontSizes];
    }
}

- (CGFloat)topAndBottomPaddingAmount
{
    return self.isSmallSize ? kOUIDocumentPickerItemViewNameToTopPaddingSmallSize : kOUIDocumentPickerItemViewNameToTopPaddingLargeSize;
}

- (NSString *)dateString;
{
    return _dateLabel.text;
}
- (void)setDateString:(NSString *)dateString;
{
    _dateLabel.text = dateString;
}

- (BOOL)showsProgress;
{
    return !self.transferProgressView.hidden;
}
- (void)setShowsProgress:(BOOL)showsProgress;
{
    self.transferProgressView.hidden = !showsProgress;
}

- (double)progress;
{
    if (self.showsProgress)
        return self.transferProgressView.progress;
    return 0.0;
}
- (void)setProgress:(double)progress;
{
    OBPRECONDITION(self.transferProgressView || progress == 0.0 || progress == 1.0);
    
    self.transferProgressView.progress = progress;
}

#pragma mark - Scaling Animation Support
- (BOOL)isEditing
{
    return self.nameTextField.isFirstResponder;
}

- (UIView*)viewForScalingStartFrame:(CGRect)startFrame endFrame:(CGRect)endFrame
{
    if (!CGRectEqualToRect(startFrame, self.frame)) {
        self.frame = startFrame;
    }
    self.startSnap = [self snapshotViewAfterScreenUpdates:NO];
    self.startSnap.contentMode = UIViewContentModeScaleAspectFit;
    
    self.frame = endFrame;
    self.doubleSizeFonts = endFrame.size.width > startFrame.size.width;
    [self setNeedsLayout];
    [self layoutIfNeeded];
    self.endSnap = [self snapshotViewAfterScreenUpdates:YES];
    self.endSnap.alpha = 0.0f;
    self.endSnap.frame = [self rectByScalingRect:self.endSnap.frame toHeight:self.startSnap.frame.size.height];
    self.endSnap.contentMode = UIViewContentModeScaleAspectFit;
    
    UIView *containingView = [[UIView alloc] initWithFrame:startFrame];
    
    [containingView addSubview:self.endSnap];
    [containingView addSubview:self.startSnap];
    
    containingView.clipsToBounds = YES;
    return containingView;
}

- (CGRect)rectByScalingRect:(CGRect)rect toHeight:(CGFloat)height
{
    CGFloat aspectRatio = rect.size.width / rect.size.height;
    rect.size.height = height;
    rect.size.width = height * aspectRatio;
    return rect;
}

- (void)animationsToPerformAlongsideScalingToHeight:(CGFloat)height
{
    self.startSnap.alpha = 0.0f;
    self.endSnap.alpha = 1.0f;
    self.startSnap.frame = [self rectByScalingRect:self.startSnap.frame toHeight:height];
    self.endSnap.frame = [self rectByScalingRect:self.endSnap.frame toHeight:height];
}

#pragma mark - UIView subclass

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event;
{
    UIView *hit = [super hitTest:point withEvent:event];
    if (!self.nameTextField.isFirstResponder && hit) {
        // don't pass touches through to subviews unless an editing session is in progress (in which case touches need to be able to reach the clear button and move the cursor position)
        // the tap gesture recognizer will programmatically begin editing on the text field
        hit = self;
    }
    return hit;
}

// Our callers only obey the height we specify, so we don't compute a width for our ideal layout (which is expensive).
- (CGSize)sizeThatFits:(CGSize)size;
{
    return CGSizeMake(size.width, [self _nameToPreviewPadding] + [self _nameHeight] + kOUIDocumentPickerItemViewNameToDatePadding + [self _dateHeight] + [self _nameToPreviewPadding]);
}

- (void)setIsSmallSize:(BOOL)isSmallSize;
{
    _isSmallSize = isSmallSize;

    [self _resetLabelFontSizes];
    
    self.padding.constant = [self _nameToPreviewPadding];
    self.nameToDatePadding.constant = kOUIDocumentPickerItemViewNameToDatePadding;
    self.nameHeightConstraint.constant = [self _nameHeight];
    self.dateHeightConstraint.constant = [self _dateHeight];
    for (NSLayoutConstraint *constraint in self.topAndBottomPadding) {
        constraint.constant = isSmallSize ? kOUIDocumentPickerItemViewNameToTopPaddingSmallSize : kOUIDocumentPickerItemViewNameToTopPaddingLargeSize;
    }
}

#pragma mark - Private


- (void)_resetLabelFontSizes;
{
    _nameTextField.font = [UIFont systemFontOfSize:[self _nameLabelFontSize]];
    _dateLabel.font = [UIFont systemFontOfSize:[self _detailLabelFontSize]];
}

- (CGFloat)_nameLabelFontSize;
{
    CGFloat fontSize;
    if (self.isSmallSize) {
        fontSize = kOUIDocumentPickerItemViewNameLabelSmallFontSize;
    } else {
        fontSize = kOUIDocumentPickerItemViewNameLabelFontSize;
    }
    
    if (self.doubleSizeFonts) {
        fontSize = fontSize * 2;
        fontSize = fmax(fontSize, [[OmniUIDocumentAppearance appearance] floatForKeyPath:@"maxFontSizeForRenameSession"]);
    }
    
    return fontSize;
}

- (CGFloat)_detailLabelFontSize;
{
    CGFloat fontSize;
    if (self.isSmallSize) {
        fontSize = kOUIDocumentPickerItemViewDetailLabelSmallFontSize;
    } else {
        fontSize = kOUIDocumentPickerItemViewDetailLabelFontSize;
    }
    
    if (self.doubleSizeFonts) {
        fontSize = fontSize * 2;
    }
    
    return fontSize;
}

- (CGFloat)_nameToPreviewPadding;
{
    if (self.isSmallSize) {
        return kOUIDocumentPickerItemSmallViewNameToPreviewPadding;
    } else {
        return kOUIDocumentPickerItemViewNameToPreviewPadding;
    }
}

- (CGFloat)_nameHeight;
{
    if (self.doubleSizeFonts) {
        return MAX(ceil([[UIFont systemFontOfSize:[self _nameLabelFontSize]] lineHeight]), 32.0);
    } else {
        return MAX(ceil([[UIFont systemFontOfSize:[self _nameLabelFontSize]] lineHeight]), 16.0);
    }
}

- (CGFloat)_dateHeight;
{
    return ceil([[UIFont systemFontOfSize:[self _detailLabelFontSize]] lineHeight]);
}

@end


