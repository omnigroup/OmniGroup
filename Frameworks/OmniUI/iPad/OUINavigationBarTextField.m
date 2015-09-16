// Copyright 2014-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUINavigationBarTextField.h>

#import <OmniAppKit/OAAppearance.h>

RCS_ID("$Id$");

@implementation OUINavigationBarTextField

static void _commonInit(OUINavigationBarTextField *self)
{
    static UIImage *resizableImage;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        UIImage *background = [UIImage imageNamed:@"OUINavigationBarTextFieldBackground" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil];
        resizableImage = [background resizableImageWithCapInsets:[[OAAppearance appearance] navigationBarTextFieldBackgroundImageInsets]];
    });
    
    self.background = resizableImage;
}

- (id)initWithCoder:(NSCoder *)aDecoder;
{
    if ((self = [super initWithCoder:aDecoder]))
        _commonInit(self);
    
    return self;
}

- (instancetype)initWithFrame:(CGRect)frame;
{
    if ((self = [super initWithFrame:frame]))
        _commonInit(self);
    
    return self;
}

- (CGSize)sizeThatFits:(CGSize)size;
{
    // UINavigationBar will call use with a size.width that reflects the available space in the nav bar. We'd like to fill all of that space.
    return size;
}

- (void)sizeToFit;
{
    [super sizeToFit];
    
    CGRect bounds = self.bounds;
    bounds.size.height = self.font.lineHeight * [[OAAppearance appearance] navigationBarTextFieldLineHeightMultiplier];
    self.bounds = bounds;
}

@end
