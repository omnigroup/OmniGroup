// Copyright 2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OITabbedInspectorView.h"

RCS_ID("$Id$");

@implementation OITabbedInspectorView

- (void)drawRect:(NSRect)r;
{
    [[NSColor colorWithWhite:0.96 alpha:1.0] setFill];
    NSRectFill(r);
}

@end
