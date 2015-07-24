// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIUndoButton.h>

RCS_ID("$Id$");

@implementation OUIUndoButton

static id _commonInit(OUIUndoButton *self)
{
    UIImage *image = [UIImage imageNamed:@"OUIToolbarUndo" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil];
    OBASSERT(image);
    [self setImage:image forState:UIControlStateNormal];

    return self;
}

- initWithFrame:(CGRect)frame;
{
    if (!(self = [super initWithFrame:frame]))
        return nil;
    return _commonInit(self);
}

- initWithCoder:(NSCoder *)coder;
{
    if (!(self = [super initWithCoder:coder]))
        return nil;
    return _commonInit(self);
}

#pragma mark - Accessibility
- (NSString *)accessibilityLabel
{
    return NSLocalizedStringFromTableInBundle(@"Undo", @"OmniUI", OMNI_BUNDLE, @"Undo button title");
}
@end
