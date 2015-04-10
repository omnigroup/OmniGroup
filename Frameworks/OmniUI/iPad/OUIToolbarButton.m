// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIToolbarButton.h>

//#import "OUIParameters.h"

RCS_ID("$Id$");

@implementation OUIToolbarButton
{
    CGFloat _maxWidth;
}

- (void)setPossibleTitles:(NSSet *)possibleTitles;
{
    if (OFISEQUAL(_possibleTitles, possibleTitles))
        return;
    
    _possibleTitles = [possibleTitles copy];
    
    CGRect oldFrame = self.frame;
    NSString *oldTitle = [[self titleForState:UIControlStateNormal] copy];
    UIImage *oldImage = self.imageView.image;
    
    OBASSERT([NSString isEmptyString:oldTitle] || [possibleTitles member:oldTitle]);
    
    CGFloat maxWidth = 0;
    self.imageView.image = nil;
    for (NSString *title in possibleTitles) {
        [self setTitle:title forState:UIControlStateNormal];
        [self sizeToFit];
        maxWidth = MAX(maxWidth, self.frame.size.width);
    }
    
    _maxWidth = maxWidth;
    
    [self setTitle:oldTitle forState:UIControlStateNormal];
    self.imageView.image = oldImage;
    [self sizeToFit];
    self.frame = (CGRect){oldFrame.origin, self.frame.size};
}

#pragma mark - UIView subclass

- (void)sizeToFit;
{
    [super sizeToFit];
    
    CGRect frame = self.frame;
    frame.size.height = 30; // Standard Bar Button Items are 30px high.
    self.frame = frame;
}

- (CGSize)sizeThatFits:(CGSize)size;
{
    CGSize fits = [super sizeThatFits:size];

    if (_possibleTitles && _maxWidth > 0) // only do this if we aren't in the middle of initializing it!
        fits.width = _maxWidth;

    if (self.imageView.image) {
        CGSize imageSize = [self.imageView.image size];
        fits.width += imageSize.width;
    }
    
    return fits;
}

@end
