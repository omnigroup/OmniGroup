// Copyright 2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "TextLayoutView.h"

#import <OmniUI/OUITextLayout.h>

RCS_ID("$Id$");

@implementation TextLayoutView

- (void)dealloc;
{
    [_text release];
    [_textLayout release];
    [super dealloc];
}

- (void)drawRect:(CGRect)rect;
{
    CGRect bounds = self.bounds;
    
    [[UIColor whiteColor] set];
    UIRectFill(bounds);
    
    NSLog(@"_textLayout = %@", _textLayout);
    
    [_textLayout drawFlippedInContext:UIGraphicsGetCurrentContext() bounds:bounds];
}

@synthesize text = _text;
- (void)setText:(NSAttributedString *)text;
{
    if (OFISEQUAL(_text, text))
        return;
    
    [_text release];
    _text = [text copy];

    // Assumes our size will be set first and will never change. Just a test case...
    [_textLayout release];
    _textLayout = [[OUITextLayout alloc] initWithAttributedString:_text constraints:CGSizeMake(self.bounds.size.width, 0)];
    [self setNeedsDisplay];
}

@end
