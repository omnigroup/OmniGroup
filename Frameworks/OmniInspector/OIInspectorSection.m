// Copyright 2007-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniInspector/OIInspectorSection.h>
#import <OmniAppKit/OALabelField.h>

RCS_ID("$Id$")

@implementation OIInspectorSection

- (NSView *)firstKeyView;
{
    return firstKeyView;
}

- (void)awakeFromNib;
{
    [super awakeFromNib];

    // setup toolTips for any truncated labels.
    for (NSView *subview in self.view.subviews) {
        if ([subview isKindOfClass:OALabelField.class]) {
            [(OALabelField *)subview setLabelAsToolTipIfTruncated];
        }
    }
}

@end
