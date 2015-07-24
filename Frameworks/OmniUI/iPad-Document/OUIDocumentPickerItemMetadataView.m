// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUIDocument/OUIDocumentPickerItemMetadataView.h>

#import <OmniUIDocument/OUIDocumentPickerScrollView.h>
#import <OmniUI/UIView-OUIExtensions.h>

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
- (void)_updateLabelSizes;
- (CGFloat)_nameLabelFontSize;
- (CGFloat)_detailLabelFontSize;
- (CGFloat)_nameHeight;
- (CGFloat)_dateHeight;
@end

@implementation OUIDocumentPickerItemMetadataView
{
    UIView *_topHairlineView;
    CGFloat _nameLabelWidth;
    UILabel *_dateLabel;
    UIImageView *_nameBadgeImageView;
    BOOL _showsImage;
    UIProgressView *_transferProgressView;
}

//static CGFloat NameHeight;
//static CGFloat DateHeight;

//+ (void)initialize;
//{
//    OBINITIALIZE;
//    
//    // Calling -sizeThatFits: is too slow, so we make this assumption (which works out for now...)
//    // not checking the isSmallItem method here, assuming large, but hopefully it'll adjust properly later.
//    NameHeight = ceil([[UIFont systemFontOfSize:kOUIDocumentPickerItemViewNameLabelFontSize] lineHeight]);
//    DateHeight = ceil([[UIFont systemFontOfSize:kOUIDocumentPickerItemViewNameLabelFontSize] lineHeight]);
//}

+ (UIColor *)defaultBackgroundColor;
{
    return OQMakeUIColor(kOUIDocumentPickerItemMetadataViewBackgroundColor);
}

- initWithFrame:(CGRect)frame;
{
    if (!(self = [super initWithFrame:frame]))
        return nil;
    
    self.opaque = NO;

    _topHairlineView = [[UIView alloc] init];
    _topHairlineView.backgroundColor = [UIColor colorWithWhite:0.85 alpha:1.0];
    _topHairlineView.opaque = NO;
    [self addSubview:_topHairlineView];

    _nameTextField = [[OUIDocumentNameTextField alloc] init];
    _nameTextField.textAlignment = NSTextAlignmentLeft;
    //_nameTextField.lineBreakMode = NSLineBreakByTruncatingTail;
    _nameTextField.font = [UIFont systemFontOfSize:[self _nameLabelFontSize]];
    _nameTextField.textColor = OQMakeUIColor(kOUIDocumentPickerItemViewNameLabelColor);
    _nameTextField.clearButtonMode = UITextFieldViewModeWhileEditing;
    _nameTextField.autocapitalizationType = UITextAutocapitalizationTypeWords;
    _nameTextField.spellCheckingType = UITextSpellCheckingTypeNo;
    _nameTextField.returnKeyType = UIReturnKeyDone;
    
    [self addSubview:_nameTextField];
    
    _dateLabel = [[UILabel alloc] init];
    _dateLabel.font = [UIFont systemFontOfSize:[self _detailLabelFontSize]];
    _dateLabel.textColor = OQMakeUIColor(kOUIDocumentPickerItemViewDetailLabelColor);
    [self addSubview:_dateLabel];
    
    _nameBadgeImageView = [[UIImageView alloc] init];
    _nameBadgeImageView.alpha = 0;
    _nameBadgeImageView.hidden = YES;
    [self insertSubview:_nameBadgeImageView aboveSubview:_nameTextField];
    _showsImage = NO;

    self.backgroundColor = [[self class] defaultBackgroundColor];
    self.opaque = NO;
    
    return self;
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
    return _transferProgressView != nil;
}
- (void)setShowsProgress:(BOOL)showsProgress;
{
    if (showsProgress) {
        if (_transferProgressView)
            return;
        _transferProgressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleBar];
        [self addSubview:self->_transferProgressView];
    } else {
        if (_transferProgressView) {
            [_transferProgressView removeFromSuperview];
            _transferProgressView = nil;
        }
    }
    
    [self setNeedsLayout];
}

- (double)progress;
{
    if (_transferProgressView)
        return _transferProgressView.progress;
    return 0.0;
}
- (void)setProgress:(double)progress;
{
    OBPRECONDITION(_transferProgressView || progress == 0.0 || progress == 1.0);
    
    _transferProgressView.progress = progress;
}

#pragma mark - UIView subclass

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event;
{
    // Direct all taps to the editable label and prepare to begin editing
    UIView *hitView = [super hitTest:point withEvent:event];
    if (hitView) {
        if ([hitView isDescendantOfView:_nameTextField]) {
            // Editing control inside the text field
            return hitView;
        }
        return _nameTextField;
    }
    
    return nil;
}

// Our callers only obey the height we specify, so we don't compute a width for our ideal layout (which is expensive).
- (CGSize)sizeThatFits:(CGSize)size;
{
    return CGSizeMake(size.width, [self _nameToPreviewPadding] + [self _nameHeight] + kOUIDocumentPickerItemViewNameToDatePadding + [self _dateHeight] + [self _nameToPreviewPadding]);
}

- (void)layoutSubviews;
{
    CGRect bounds = self.bounds;
    
    CGFloat hairlineHeight = 1.0 / [self contentScaleFactor];
    CGRect topHairLine, rest;
    CGRectDivide(bounds, &topHairLine, &rest, hairlineHeight, CGRectMinYEdge);
    _topHairlineView.frame = topHairLine;
    
    if (_transferProgressView) {
        CGRect progressFrame = topHairLine;
        progressFrame.size.height = [_transferProgressView sizeThatFits:progressFrame.size].height;
        progressFrame.origin.y += hairlineHeight;
        _transferProgressView.frame = progressFrame;
    }

    CGFloat nameToPreviewPadding = [self _nameToPreviewPadding];
    // CGRectInset can return CGRectNull if the rect isn't big enough to inset (which can transiently happen when getting set up).
    {
        CGRect inset = CGRectInset(bounds, nameToPreviewPadding, nameToPreviewPadding);
        if (!CGRectIsNull(inset))
            bounds = inset;
    }
    
    CGFloat nameLeftEdge = CGRectGetMinX(bounds);
    

    // we don't want our words snugged way up on the left edge of the view, if the initial view inset doesn't create enough space, lets add a bit more. Effectively makes the left padding from the edge of the view at LEAST 4 points.
    if (nameToPreviewPadding < 4)
        nameLeftEdge += 4 - nameToPreviewPadding;

    // CGRectDivide can return CGRectNull if our bounds transiently aren't big enough to fit our subviews. So we do these calculations manually.
    CGRect nameRect = CGRectMake(nameLeftEdge, CGRectGetMinY(bounds), CGRectGetMaxX(bounds) - nameLeftEdge, [self _nameHeight]);
    CGRect dateRect = CGRectMake(nameLeftEdge, CGRectGetMaxY(bounds) - [self _dateHeight], CGRectGetWidth(bounds), [self _dateHeight]);

    OBASSERT(OUICheckValidFrame(nameRect));
    OBASSERT(OUICheckValidFrame(dateRect));

    if (_nameBadgeImageView && _nameBadgeImageView.image) {
        static const CGFloat kNameToBadgePadding = 4;
        CGSize imageSize = [_nameBadgeImageView sizeThatFits:bounds.size];

        CGFloat nameRightXEdge = CGRectGetMaxX(bounds) - (kNameToBadgePadding + imageSize.width);
        
        // Always position the image view correctly, as it might be in the middle of animating in or out despite the value of _showsImage
        CGRect imageRect = CGRectMake(nameRightXEdge + kNameToBadgePadding, floor(CGRectGetMidY(bounds) - imageSize.height/2), imageSize.width, imageSize.height);

        if (self.isSmallSize) {
            imageRect = CGRectInset(imageRect, 4, 4);
        }

        _nameBadgeImageView.frame = imageRect;
        
        if (_showsImage)
            nameRect.size.width = nameRightXEdge - CGRectGetMinX(nameRect);
    }

    _nameTextField.frame = nameRect;
    _dateLabel.frame = dateRect;
}

- (void)setIsSmallSize:(BOOL)isSmallSize;
{
    _isSmallSize = isSmallSize;

    [self _updateLabelSizes];
}

#pragma mark - Private


- (void)_updateLabelSizes;
{
    _nameTextField.font = [UIFont systemFontOfSize:[self _nameLabelFontSize]];
    _dateLabel.font = [UIFont systemFontOfSize:[self _detailLabelFontSize]];
}

- (CGFloat)_nameLabelFontSize;
{
    if (self.isSmallSize) {
        return kOUIDocumentPickerItemViewNameLabelSmallFontSize;
    } else {
        return kOUIDocumentPickerItemViewNameLabelFontSize;
    }
}

- (CGFloat)_detailLabelFontSize;
{
    if (self.isSmallSize) {
        return kOUIDocumentPickerItemViewDetailLabelSmallFontSize;
    } else {
        return kOUIDocumentPickerItemViewDetailLabelFontSize;
    }
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
    return MAX(ceil([[UIFont systemFontOfSize:[self _nameLabelFontSize]] lineHeight]), 16.0);
}

- (CGFloat)_dateHeight;
{
    return ceil([[UIFont systemFontOfSize:[self _detailLabelFontSize]] lineHeight]);
}

@end


