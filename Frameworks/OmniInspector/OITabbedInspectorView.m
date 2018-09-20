// Copyright 2016-2018 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OITabbedInspectorView.h"

#import <OmniInspector/OIAppearance.h>

RCS_ID("$Id$");

@implementation OITabbedInspectorView

- (void)drawRect:(NSRect)r;
{
    NSColor *backgroundColor = [NSColor controlColor];
    [backgroundColor set];
    NSRectFill(r);
}

- (void)awakeFromNib;
{
    self.blendingMode = NSVisualEffectBlendingModeWithinWindow;
#if defined(MAC_OS_X_VERSION_10_14)
    if(@available(macOS 10.14, *)) {
        self.material = NSVisualEffectMaterialWindowBackground;
    }
#endif
}

@end
