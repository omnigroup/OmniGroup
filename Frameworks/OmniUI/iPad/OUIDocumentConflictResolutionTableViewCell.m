// Copyright 2010-2012 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIDocumentConflictResolutionTableViewCell.h"

#import <OmniFileStore/OFSDocumentStoreFileItem.h>
#import <OmniUI/UITableView-OUIExtensions.h>
#import <OmniUI/OUIDocumentPreview.h>
//#import <OmniQuartz/OQColor.h>
#import <OmniQuartz/OQDrawing.h>

RCS_ID("$Id$");

@interface OUIDocumentConflictResolutionTableViewCell ()
- (void)_updateBackgroundColor;
- (void)_updateSelectionImage;
@end

@implementation OUIDocumentConflictResolutionTableViewCell
{
    UIImageView *_selectionImageView;
    UIImageView *_previewImageView;
    UILabel *_hostNameLabel;
    UILabel *_modificationDateLabel;
    BOOL _previewHasChanged;
}

@synthesize preview = _preview;
@synthesize fileVersion = _fileVersion;

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier;
{
    if (!(self = [super initWithStyle:style reuseIdentifier:reuseIdentifier]))
        return nil;
    
    self.selectionStyle = UITableViewCellSelectionStyleNone;
    
    UIView *contentView = self.contentView;
    
    _selectionImageView = [[UIImageView alloc] init];
    [contentView addSubview:_selectionImageView];
    
    _previewImageView = [[UIImageView alloc] init];
    [contentView addSubview:_previewImageView];
    
    _hostNameLabel = [[UILabel alloc] init];
    _hostNameLabel.font = [UIFont boldSystemFontOfSize:16];
    [contentView addSubview:_hostNameLabel];
    
    _modificationDateLabel = [[UILabel alloc] init];
    _modificationDateLabel.font = [UIFont systemFontOfSize:14];
    _modificationDateLabel.textColor = [UIColor grayColor];
    [contentView addSubview:_modificationDateLabel];
    
    [self _updateSelectionImage];
    
    return self;
}

- (void)dealloc;
{
    [_selectionImageView release];
    [_previewImageView release];
    [_hostNameLabel release];
    [_modificationDateLabel release];
    [_preview release];
    [_fileVersion release];
    [super dealloc];
}

- (void)setPreview:(OUIDocumentPreview *)preview;
{
    if (_preview == preview)
        return;
    
    [_preview release];
    _preview = [preview retain];
    
    _previewHasChanged = YES;
    [self setNeedsLayout];
}

- (void)setFileVersion:(NSFileVersion *)fileVersion;
{
    if (_fileVersion == fileVersion)
        return;
    
    [_fileVersion retain];
    _fileVersion = [fileVersion retain];
    
    OBASSERT(_hostNameLabel);
    _hostNameLabel.text = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Modified on %@", @"OmniUI", OMNI_BUNDLE, @"table view cell title for file conflict resolution"), _fileVersion.localizedNameOfSavingComputer];
    
    OBASSERT(_modificationDateLabel);
    _modificationDateLabel.text = [OFSDocumentStoreFileItem displayStringForDate:_fileVersion.modificationDate];
}

@synthesize landscape = _landscape;
- (void)setLandscape:(BOOL)landscape;
{
    if (_landscape == landscape)
        return;
    
    _landscape = landscape;
    
    [self setNeedsLayout];
}

#pragma mark -
#pragma mark UITableViewCell subclass

- (void)setSelected:(BOOL)selected animated:(BOOL)animated
{
    [super setSelected:selected animated:animated];

    [self _updateSelectionImage];
    [self _updateBackgroundColor];
}

-(void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated;
{
    [super setHighlighted:highlighted animated:animated];
    [self _updateBackgroundColor];
}

#pragma mark -
#pragma mark UIView subclass

- (void)layoutSubviews;
{
    [super layoutSubviews];
    
    CGRect bounds = self.contentView.bounds;
    OBASSERT(CGPointEqualToPoint(bounds.origin, CGPointZero));
    
    const CGFloat kTitleLeftX = 159;
    const CGFloat kSelectionImageViewCenterX = 35;
    
    
    // selection image
    CGFloat previewFrameLeftX;
    {
        UIImage *image = _selectionImageView.image;
        OBASSERT(image);
        CGSize imageSize = image.size;
        
        CGRect selectionImageFrame = CGRectMake(floor(kSelectionImageViewCenterX - imageSize.width/2), floor((bounds.size.height - imageSize.height)/2), imageSize.width, imageSize.height);
        
        selectionImageFrame.origin.y -= 2; // shadow offset makes the image taller than it would be otherwise
        
        _selectionImageView.frame = selectionImageFrame;
        previewFrameLeftX = CGRectGetMaxX(selectionImageFrame);
    }

    // preview image
    {
        OBASSERT(_preview); // ... even if it is a placeholder (might want to add a spinning indicator in that case, though).

        const CGFloat kPreviewVerticalPadding = _landscape ? 16 : 7;

        CGRect previewImageFrame = CGRectMake(previewFrameLeftX, kPreviewVerticalPadding, kTitleLeftX - previewFrameLeftX, bounds.size.height - 2*kPreviewVerticalPadding);

        CGSize previewSize = _preview.size;
        CGRect previewImageViewFrame = OQLargestCenteredIntegralRectInRectWithAspectRatioAsSize(previewImageFrame, previewSize);
        CGFloat scale = [[UIScreen mainScreen] scale];
        
        if (_previewHasChanged && !CGSizeEqualToSize(previewImageViewFrame.size, _previewImageView.frame.size)) {
            // Build a high quality scaled image of this size, but only if we have to.
            CGImageRef originalImage = _preview.image;
            if (originalImage == NULL) {
                _previewImageView.image = nil;
            } else {
                CGSize scaledImageSize = previewImageViewFrame.size;
                
                scaledImageSize.width *= scale;
                scaledImageSize.height *= scale;
                
                CGImageRef scaledImage = OQCreateImageWithSize(originalImage, scaledImageSize, kCGInterpolationHigh);
                _previewImageView.image = scaledImage ? [UIImage imageWithCGImage:scaledImage] : nil;
                CGImageRelease(scaledImage);
            }
        }
        _previewImageView.frame = previewImageViewFrame;

        CALayer *previewImageLayer = _previewImageView.layer;
        previewImageLayer.shadowColor = [[UIColor blackColor] CGColor];
        previewImageLayer.shadowOffset = CGSizeMake(0, 1);
        previewImageLayer.shadowRadius = 3;
        previewImageLayer.shadowOpacity = 0.4;
        previewImageLayer.contentsScale = scale;
        
        CGPathRef shadowPath = CGPathCreateWithRect(previewImageLayer.bounds, NULL);
        previewImageLayer.shadowPath = shadowPath;
        CFRelease(shadowPath);
        
        //previewImageLayer.borderColor = [[UIColor redColor] CGColor];
        //previewImageLayer.borderWidth = 1;
    }
    
    // Title/subtitle; vertically center them w/in their total height (with some padding between).
    OFExtent titleXExtent = OFExtentMake(kTitleLeftX, CGRectGetMaxX(bounds) - kTitleLeftX);
    
    [_hostNameLabel sizeToFit];
    [_modificationDateLabel sizeToFit];

    const CGFloat kNameToDatePadding = 0;
    CGFloat usedHeight = CGRectGetHeight(_hostNameLabel.frame) + kNameToDatePadding + CGRectGetHeight(_modificationDateLabel.frame);
    CGFloat topPadding = ceil((CGRectGetHeight(bounds) - usedHeight)/2);
    
    _hostNameLabel.frame = CGRectMake(titleXExtent.location, topPadding, titleXExtent.length, _hostNameLabel.frame.size.height);
    _modificationDateLabel.frame = CGRectMake(titleXExtent.location, CGRectGetMaxY(_hostNameLabel.frame) + kNameToDatePadding, titleXExtent.length, _modificationDateLabel.frame.size.height);
}

#pragma mark -
#pragma mark Private

- (void)_updateBackgroundColor;
{
    UIColor *backgroundColor = [OUITableViewCellBackgroundColorForCurrentState(&OUITableViewCellDefaultBackgroundColors, self) toColor];
    self.backgroundColor = backgroundColor;
    _hostNameLabel.backgroundColor = backgroundColor;
    _modificationDateLabel.backgroundColor = backgroundColor;
}

- (void)_updateSelectionImage;
{
    NSString *imageName = self.selected ? @"OUITableViewSelectionDot-Selected.png" : @"OUITableViewSelectionDot-Normal.png";
    UIImage *image = [UIImage imageNamed:imageName];
    OBASSERT(image);
    
    _selectionImageView.image = image;
}

@end
