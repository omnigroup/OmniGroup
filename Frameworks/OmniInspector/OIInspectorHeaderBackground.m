// Copyright 2002-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OIInspectorHeaderBackground.h"

#import <OmniAppKit/OmniAppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniInspector/OIInspectorHeaderView.h>

RCS_ID("$Id$")

@implementation OIInspectorHeaderBackground

- (void)setHeaderView:(OIInspectorHeaderView *)header
{
    if (_headerView != header) {
        _headerView = header;
        [self setNeedsDisplay:YES];
    }
}

- (BOOL)isFlipped;
{
    return [_headerView isFlipped];
}

- (BOOL)isOpaque
{
    return YES;
}

- (void)drawRect:(NSRect)rect
{
    if (_headerView)
        [_headerView drawBackgroundImageForBounds:[self bounds] inRect:rect];
    else {
        // Fallback; not actually used
        [[NSColor redColor] set];
        NSRectFill(rect);
    }
}

@end
