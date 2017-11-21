// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUIDocument/OUIDocumentPickerItemMetadataView.h>

@import OmniUI;
#import <OmniUIDocument/OUIDocumentPickerScrollView.h>
#import <OmniUIDocument/OmniUIDocumentAppearance.h>

#import "OUIDocumentParameters.h"

RCS_ID("$Id$");

@implementation OUIDocumentNameTextField

- (CGRect)clearButtonRectForBounds:(CGRect)bounds;
{
    // We have padding to the right of this text field, so jam the clear button all the way to the right edge
    CGRect rect =  [super clearButtonRectForBounds:bounds];
    
    if (self.useLargerClearButton) {
        rect = CGRectInset(rect, floorf(-(0.5 * rect.size.width)), floorf(-(0.5 * rect.size.height)));
    }

    rect.origin.x = CGRectGetMaxX(bounds) - CGRectGetWidth(rect);
    rect.origin.y = floor(CGRectGetMidY(bounds) - CGRectGetHeight(rect) / 2);
    
    return rect;
}

@end

@interface OUIDocumentPickerItemMetadataView ()

@property (nonatomic, readonly) UILabel *dateLabel;
@property (nonatomic, readonly) UIImageView *nameBadgeImageView;
@property (nonatomic, readonly) UIView *topHairlineView;

@property (nonatomic) UIView *startSnap; // for animating to/from large size when renaming
@property (nonatomic) UIView *endSnap; // for animating to/from large size when renaming

@property (nonatomic, readonly) CGFloat topPadding;
@property (nonatomic, readonly) CGFloat bottomPadding;
@property (nonatomic, readonly) CGFloat leftPadding;
@property (nonatomic, readonly) CGFloat rightPadding;
@property (nonatomic, readonly) CGFloat nameLabelFontSize;
@property (nonatomic, readonly) CGFloat detailLabelFontSize;
@property (nonatomic, readonly) CGFloat nameHeight;
@property (nonatomic, readonly) CGFloat dateHeight;
@property (nonatomic, readonly) CGFloat nameToPreviewPadding;

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
    _nameTextField.font = [UIFont systemFontOfSize:self.nameLabelFontSize];
    _nameTextField.textColor = OAMakeUIColor(kOUIDocumentPickerItemViewNameLabelColor);
    _nameTextField.clearButtonMode = UITextFieldViewModeWhileEditing;
    _nameTextField.autocapitalizationType = UITextAutocapitalizationTypeWords;
    _nameTextField.spellCheckingType = UITextSpellCheckingTypeNo;
    _nameTextField.returnKeyType = UIReturnKeyDone;
    
    _dateLabel.font = [UIFont systemFontOfSize:self.detailLabelFontSize];
    _dateLabel.textColor = OAMakeUIColor(kOUIDocumentPickerItemViewDetailLabelColor);

    _showsImage = NO;

    self.backgroundColor = [[self class] defaultBackgroundColor];
}

- initWithFrame:(CGRect)frame;
{
    if (!(self = [super initWithFrame:frame]))
        return nil;

    [self commonInit];
    
    return self;
}

- (void)_setFrameIfNeeded:(CGRect)frame view:(UIView *)view
{
    if (!CGRectEqualToRect(view.frame, frame)) {
        view.frame = frame;
    }
}


- (void)createSubviews
{
    _topHairlineView = [[UIView alloc] init];
    _topHairlineView.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_topHairlineView];

    _nameTextField = [[OUIDocumentNameTextField alloc] init];
    _nameTextField.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_nameTextField];

    _dateLabel = [[UILabel alloc] init];
    _dateLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_dateLabel];

    [self setNeedsLayout];
}

- (void)_ensureNameBadgeImageView
{
    if (!_nameBadgeImageView) {
        _nameBadgeImageView = [[UIImageView alloc] init];
        _nameBadgeImageView.translatesAutoresizingMaskIntoConstraints = NO;
        _nameBadgeImageView.contentMode = UIViewContentModeScaleAspectFit;
        _nameBadgeImageView.alpha = 0;
        _nameBadgeImageView.hidden = YES;

        [self addSubview:_nameBadgeImageView];
        [self setNeedsLayout];
    }
}

- (void)_ensureTransferProgressView
{
    if (!_transferProgressView) {
        _transferProgressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleBar];
        _transferProgressView.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_transferProgressView];
        [self setNeedsLayout];
    }
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
    if (nameBadgeImage) {
        [self _ensureNameBadgeImageView];
    }
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
        if (flag) {
            [self _ensureNameBadgeImageView];
        }
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
        [self _resetLabelFontSizes];
        [self setNeedsLayout];
    }
    self.nameTextField.useLargerClearButton = doubleSizeFonts;
}

- (NSString *)dateString;
{
    return _dateLabel.text;
}

- (void)setDateString:(NSString *)dateString;
{
    if (!OFISEQUAL(_dateLabel.text, dateString)) {
        _dateLabel.text = dateString;
        [self invalidateIntrinsicContentSize];
        [self setNeedsLayout];
    }
}

- (BOOL)showsProgress;
{
    return _transferProgressView && !_transferProgressView.hidden;
}

- (void)setShowsProgress:(BOOL)showsProgress;
{
    if (showsProgress) {
        [self _ensureTransferProgressView];
    }
    _transferProgressView.hidden = !showsProgress;
}

- (float)progress;
{
    if (self.showsProgress) {
        return _transferProgressView.progress;
    }
    return 0.0;
}

- (void)setProgress:(float)progress;
{
    OBPRECONDITION(_transferProgressView || progress == 0.0 || progress == 1.0);
    if (progress > 0.0) {
        [self _ensureTransferProgressView];
        _transferProgressView.progress = progress;
    }
}

#pragma mark - Scaling Animation Support

- (BOOL)isEditing
{
    return self.nameTextField.isFirstResponder;
}

- (UIView *)viewForScalingStartFrame:(CGRect)startFrame endFrame:(CGRect)endFrame
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
    self.endSnap.alpha = 0.6f;
    self.startSnap.frame = [self rectByScalingRect:self.startSnap.frame toHeight:height];
    self.endSnap.frame = [self rectByScalingRect:self.endSnap.frame toHeight:height];
}

#pragma mark - UIView subclass

- (void)layoutSubviews
{
    [super layoutSubviews];

    CGRect bounds = self.bounds;
    CGFloat width = CGRectGetWidth(bounds);
    if (width < 1.0) {
        return;
    }

    CGFloat height = CGRectGetHeight(bounds);
    if (height < 1.0) {
        height = self.intrinsicContentSize.height;
    }

    CGFloat minX = CGRectGetMinX(bounds);
    CGFloat maxX = CGRectGetMaxX(bounds);
    CGFloat minY = CGRectGetMinY(bounds);
    CGFloat maxY = CGRectGetMaxY(bounds);
    CGFloat topPadding = self.topPadding;
    CGFloat bottomPadding = self.bottomPadding;
    CGFloat rightPadding = self.rightPadding;
    CGFloat leftPadding = self.leftPadding;

    // Top hairline
    CGRect hairlineFrame = CGRectMake(minX, minY, width, 1.0 / self.contentScaleFactor);
    [self _setFrameIfNeeded:hairlineFrame view:_topHairlineView];

    // Progress view
    if (_transferProgressView) {
        CGFloat progressHeight = CGRectGetHeight(_transferProgressView.bounds);
        CGRect progressFrame = CGRectMake(minX, -0.5, width, progressHeight);
        [self _setFrameIfNeeded:progressFrame view:_transferProgressView];
    }

    CGFloat maxXForLabels = maxX - rightPadding;

    // Image view
    BOOL imageViewIsHidden = !_nameBadgeImageView || _nameBadgeImageView.isHidden || _nameBadgeImageView.image == nil;
    if (!imageViewIsHidden) {
        CGFloat maxImageHeight = (height - topPadding) - bottomPadding;
        CGSize imageSize = _nameBadgeImageView.image.size;
        if (imageSize.height > maxImageHeight) {
            CGFloat multiplier = maxImageHeight / imageSize.height;
            imageSize.height = imageSize.height * multiplier;
            imageSize.width = imageSize.width * multiplier;
        }
        CGFloat imageOriginX = (maxX - rightPadding) - imageSize.width;
        CGRect imageFrame = CGRectMake(imageOriginX, topPadding, imageSize.width, imageSize.height);
        [self _setFrameIfNeeded:imageFrame view:_nameBadgeImageView];
        maxXForLabels = CGRectGetMinX(imageFrame) - rightPadding;
    }

    // Date
    BOOL showDate = ![NSString isEmptyString:self.dateString];
    CGFloat textWidth = maxXForLabels - leftPadding;
    if (showDate) {
        CGFloat dateHeight = self.dateHeight;
        CGFloat dateOriginY = (maxY - bottomPadding) - dateHeight;
        CGRect dateFrame = CGRectMake(leftPadding, dateOriginY, textWidth, dateHeight);
        [self _setFrameIfNeeded:dateFrame view:self.dateLabel];
    }

    // Name
    CGRect nameFrame = CGRectMake(leftPadding, topPadding, textWidth, self.nameHeight);
    [self _setFrameIfNeeded:nameFrame view:_nameTextField];
}

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
    if ([NSString isEmptyString:self.dateString]) {
        return CGSizeMake(size.width, self.topPadding + self.nameHeight + self.bottomPadding);
    }
    return CGSizeMake(size.width, self.topPadding + self.nameHeight + kOUIDocumentPickerItemViewNameToDatePadding + self.dateHeight + self.bottomPadding);
}

- (CGSize)intrinsicContentSize
{
    CGSize size = [self sizeThatFits:CGSizeMake(CGRectGetWidth(self.bounds), CGFLOAT_MAX)];
    return CGSizeMake(UIViewNoIntrinsicMetric, size.height);
}

- (void)setIsSmallSize:(BOOL)isSmallSize;
{
    if (_isSmallSize == isSmallSize) {
        return;
    }

    _isSmallSize = isSmallSize;
    [self _resetLabelFontSizes];
    [self setNeedsLayout];
}

#pragma mark - Private

- (void)_resetLabelFontSizes;
{
    _nameTextField.font = [UIFont systemFontOfSize:self.nameLabelFontSize];
    _dateLabel.font = [UIFont systemFontOfSize:self.detailLabelFontSize];
}

#pragma mark - Layout

- (CGFloat)nameLabelFontSize;
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

- (CGFloat)detailLabelFontSize;
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

- (CGFloat)leftPadding
{
    return self.doubleSizeFonts ? self.nameToPreviewPadding * 2 : self.nameToPreviewPadding;
}

- (CGFloat)rightPadding
{
    return self.doubleSizeFonts ? self.nameToPreviewPadding * 2 : self.nameToPreviewPadding;
}

- (CGFloat)_verticalPaddingAmount
{
    return self.isSmallSize ? kOUIDocumentPickerItemViewNameToTopPaddingSmallSize : kOUIDocumentPickerItemViewNameToTopPaddingLargeSize;
}

- (CGFloat)topPadding
{
    return self.doubleSizeFonts ? [self _verticalPaddingAmount] * 2 : [self _verticalPaddingAmount];
}

- (CGFloat)_bottomPaddingAmount
{
    return [self _verticalPaddingAmount] / kOUIDocumentPickerItemViewTopToBottomPaddingRatio;
}

- (CGFloat)bottomPadding
{
    return self.doubleSizeFonts ? [self _bottomPaddingAmount] * 2 : [self _bottomPaddingAmount];
}

- (CGFloat)nameToPreviewPadding;
{
    if (self.isSmallSize) {
        return kOUIDocumentPickerItemSmallViewNameToPreviewPadding;
    } else {
        return kOUIDocumentPickerItemViewNameToPreviewPadding;
    }
}

- (CGFloat)nameHeight;
{
    if (self.doubleSizeFonts) {
        return MAX(ceil([UIFont systemFontOfSize:self.nameLabelFontSize].lineHeight), 32.0);
    } else {
        return MAX(ceil([UIFont systemFontOfSize:self.nameLabelFontSize].lineHeight), 16.0);
    }
}

- (CGFloat)dateHeight;
{
    return ceil([UIFont systemFontOfSize:self.detailLabelFontSize].lineHeight);
}

@end


