// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIDocumentConflictResolutionTableViewCell.h"

#import <OmniUI/OUIDocumentStoreFileItem.h>
#import <OmniUI/UITableView-OUIExtensions.h>
#import <OmniQuartz/OQColor.h>
#import <OmniQuartz/OQDrawing.h>

RCS_ID("$Id$");

@interface OUIDocumentConflictResolutionTableViewCell ()
@property(nonatomic,retain) IBOutlet UIImageView *selectionImageView;
@property(nonatomic,retain) IBOutlet UIImageView *previewImageView;
@property(nonatomic,retain) IBOutlet UILabel *hostNameLabel;
@property(nonatomic,retain) IBOutlet UILabel *modificationDateLabel;

- (void)_updateSelectionImage;
@end

@implementation OUIDocumentConflictResolutionTableViewCell
{
    UIImageView *_selectionImageView;
    UIImageView *_previewImageView;
    
    UILabel *_hostNameLabel;
    UILabel *_modificationDateLabel;
    
    NSFileVersion *_fileVersion;
}

@synthesize selectionImageView = _selectionImageView;
@synthesize previewImageView = _previewImageView;
@synthesize hostNameLabel = _hostNameLabel;
@synthesize modificationDateLabel = _modificationDateLabel;

- (void)awakeFromNib;
{
    [super awakeFromNib];
    [self _updateSelectionImage];
}

- (void)dealloc;
{
    [_selectionImageView release];
    [_previewImageView release];
    [_hostNameLabel release];
    [_modificationDateLabel release];
    [_fileVersion release];
    [super dealloc];
}

- (UIImage *)previewImage;
{
    return _previewImageView.image;
}
- (void)setPreviewImage:(UIImage *)previewImage;
{
    OBPRECONDITION(_previewImageView);
    _previewImageView.image = previewImage;
}

@synthesize fileVersion = _fileVersion;
- (void)setFileVersion:(NSFileVersion *)fileVersion;
{
    if (_fileVersion == fileVersion)
        return;
    
    [_fileVersion retain];
    _fileVersion = [fileVersion retain];
    
    OBASSERT(_hostNameLabel);
    _hostNameLabel.text = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Modified on %@", @"OmniUI", OMNI_BUNDLE, @"table view cell title for file conflict resolution"), _fileVersion.localizedNameOfSavingComputer];
    
    OBASSERT(_modificationDateLabel);
    _modificationDateLabel.text = [OUIDocumentStoreFileItem displayStringForDate:_fileVersion.modificationDate];
}

#pragma mark -
#pragma mark UITableViewCell subclass

- (void)setSelected:(BOOL)selected animated:(BOOL)animated
{
    [super setSelected:selected animated:animated];

    [self _updateSelectionImage];
    
    self.backgroundColor = [OUITableViewCellBackgroundColorForCurrentState(&OUITableViewCellDefaultBackgroundColors, self) toColor];
}

-(void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated;
{
    [super setHighlighted:highlighted animated:animated];
    
    self.backgroundColor = [OUITableViewCellBackgroundColorForCurrentState(&OUITableViewCellDefaultBackgroundColors, self) toColor];
}

#pragma mark -
#pragma mark UIView subclass

- (void)layoutSubviews;
{
    [super layoutSubviews];
    
    CGRect remaining = self.bounds;
    
    // selection image
    {
        CGRect selectionImageFrame;
        CGRectDivide(remaining, &selectionImageFrame, &remaining, 70, CGRectMinXEdge);
        
        UIImage *image = _selectionImageView.image;
        OBASSERT(image);
        _selectionImageView.frame = OQCenteredIntegralRectInRect(selectionImageFrame, image.size);
    }

    // preview image
    {
        CGRect previewImageFrame;
        CGRectDivide(remaining, &previewImageFrame, &remaining, 70, CGRectMinXEdge);
        
        UIImage *image = _previewImageView.image;
        if (image) {
            _previewImageView.frame = OQCenteredIntegralRectInRect(previewImageFrame, image.size);
            _previewImageView.hidden = NO;
        } else {
            _previewImageView.hidden = YES;
        }
    }
    
    // Title/subtitle; just set their x extent
    remaining.origin.x += 8;
    remaining.size.width -= 8;
    
    _hostNameLabel.frame = OFExtentsToRect(OFExtentFromRectXRange(remaining), OFExtentFromRectYRange(_hostNameLabel.frame));
    _modificationDateLabel.frame = OFExtentsToRect(OFExtentFromRectXRange(remaining), OFExtentFromRectYRange(_modificationDateLabel.frame));
}

#pragma mark -
#pragma mark Private

- (void)_updateSelectionImage;
{
    NSString *imageName = self.selected ? @"OUITableViewSelectionDot-Selected.png" : @"OUITableViewSelectionDot-Normal.png";
    UIImage *image = [UIImage imageNamed:imageName];
    OBASSERT(image);
    
    _selectionImageView.image = image;
}

@end
