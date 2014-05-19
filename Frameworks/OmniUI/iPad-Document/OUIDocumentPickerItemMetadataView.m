// Copyright 2010-2014 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUIDocument/OUIDocumentPickerItemMetadataView.h>

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
@end

@implementation OUIDocumentPickerItemMetadataView
{
    UIView *_topHairlineView;
    UILabel *_nameLabel;
    CGFloat _nameLabelWidth;
    UILabel *_dateLabel;
    UIImageView *_nameBadgeImageView;
    BOOL _showsImage;
    UIProgressView *_transferProgressView;
}

static CGFloat NameHeight;
static CGFloat DateHeight;

+ (void)initialize;
{
    OBINITIALIZE;
    
    // Calling -sizeThatFits: is too slow, so we make this assumption (which works out for now...)
    NameHeight = ceil([[UIFont systemFontOfSize:kOUIDocumentPickerItemViewNameLabelFontSize] lineHeight]);
    DateHeight = ceil([[UIFont systemFontOfSize:kOUIDocumentPickerItemViewNameLabelFontSize] lineHeight]);
}

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
    _nameTextField.font = [UIFont systemFontOfSize:kOUIDocumentPickerItemViewNameLabelFontSize];
    _nameTextField.textColor = OQMakeUIColor(kOUIDocumentPickerItemViewNameLabelColor);
    _nameTextField.clearButtonMode = UITextFieldViewModeWhileEditing;
    _nameTextField.autocapitalizationType = UITextAutocapitalizationTypeWords;
    _nameTextField.spellCheckingType = UITextSpellCheckingTypeNo;
    _nameTextField.returnKeyType = UIReturnKeyDone;
    [_nameTextField addTarget:self action:@selector(_nameTextFieldEditingUpdated:) forControlEvents:UIControlEventEditingDidBegin|UIControlEventEditingDidEnd|UIControlEventEditingDidEndOnExit];
    
    [self addSubview:_nameTextField];
    
    _dateLabel = [[UILabel alloc] init];
    _dateLabel.font = [UIFont systemFontOfSize:kOUIDocumentPickerItemViewDetailLabelFontSize];
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

- (NSString *)label;
{
    return _nameLabel.text;
}
- (void)setLabel:(NSString *)label;
{
    if ([NSString isEmptyString:label]) {
        if (_nameLabel) {
            [_nameLabel removeFromSuperview];
            _nameLabel = nil;
        }
    } else {
        if (!_nameLabel) {
            _nameLabel = [[UILabel alloc] init];
            _nameLabel.font = [UIFont systemFontOfSize:kOUIDocumentPickerItemViewNameLabelFontSize];
            _nameLabel.textColor = OQMakeUIColor(kOUIDocumentPickerItemViewDetailLabelColor);
            [self addSubview:_nameLabel];
            [self _updateLabelHidden]; // Unlikely we'd change the label while editing, but why not...
        }
        if (OFNOTEQUAL(_nameLabel.text, label)) {
            _nameLabel.text = label;
            _nameLabelWidth = ceil([_nameLabel sizeThatFits:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX)].width);
            
            [self layoutSubviews];
        }
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
    return CGSizeMake(size.width, kOUIDocumentPickerItemViewNameToPreviewPadding + NameHeight + kOUIDocumentPickerItemViewNameToDatePadding + DateHeight + kOUIDocumentPickerItemViewNameToPreviewPadding);
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

    // CGRectInset can return CGRectNull if the rect isn't big enough to inset (which can transiently happen when getting set up).
    {
        CGRect inset = CGRectInset(bounds, kOUIDocumentPickerItemViewNameToPreviewPadding, kOUIDocumentPickerItemViewNameToPreviewPadding);
        if (!CGRectIsNull(inset))
            bounds = inset;
    }
    
    CGFloat nameLeftEdge = CGRectGetMinX(bounds);
    
    if (_nameLabel && !_nameLabel.hidden) {
        CGSize nameLabelSize = CGSizeMake(_nameLabelWidth, NameHeight);
        CGRect nameLabelRect = CGRectMake(CGRectGetMinX(bounds), CGRectGetMinY(bounds), ceil(nameLabelSize.width), NameHeight);
        _nameLabel.frame = nameLabelRect;
        
        nameLeftEdge = CGRectGetMaxX(nameLabelRect) + 4;
    }

    // CGRectDivide can return CGRectNull if our bounds transiently aren't big enough to fit our subviews. So we do these calculations manually.
    CGRect nameRect = CGRectMake(nameLeftEdge, CGRectGetMinY(bounds), CGRectGetMaxX(bounds) - nameLeftEdge, NameHeight);
    CGRect dateRect = CGRectMake(CGRectGetMinX(bounds), CGRectGetMaxY(bounds) - DateHeight, CGRectGetWidth(bounds), DateHeight);

    OBASSERT(OUICheckValidFrame(nameRect));
    OBASSERT(OUICheckValidFrame(dateRect));

    if (_nameBadgeImageView) {
        static const CGFloat kNameToBadgePadding = 4;
        CGSize imageSize = [_nameBadgeImageView sizeThatFits:bounds.size];
        CGFloat nameRightXEdge = CGRectGetMaxX(bounds) - (kNameToBadgePadding + imageSize.width);
        
        // Always position the image view correctly, as it might be in the middle of animating in or out despite the value of _showsImage
        CGRect imageRect = CGRectMake(nameRightXEdge + kNameToBadgePadding, floor(CGRectGetMidY(bounds) - imageSize.height/2), imageSize.width, imageSize.height);
        _nameBadgeImageView.frame = imageRect;
        
        if (_showsImage)
            nameRect.size.width = nameRightXEdge - CGRectGetMinX(nameRect);
    }

    _nameTextField.frame = nameRect;
    _dateLabel.frame = dateRect;
}

#pragma mark - Private

- (void)_nameTextFieldEditingUpdated:(id)sender;
{
    [self _updateLabelHidden];
}

- (void)_updateLabelHidden;
{
    BOOL hidden = [_nameTextField isFirstResponder];
    if (hidden ^ _nameLabel.hidden)
        [self setNeedsLayout];
    _nameLabel.hidden = hidden;
}

@end


