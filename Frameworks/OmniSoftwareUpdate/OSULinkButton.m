// Copyright 2013-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OSULinkButton.h"

#import <AvailabilityMacros.h>

RCS_ID("$Id$");

@implementation OSULinkButton

- (void)awakeFromNib;
{
    [super awakeFromNib];
    
    NSFont *font = self.font;
    if (!font)
        font = [NSFont systemFontOfSize:[NSFont systemFontSizeForControlSize:[self.cell controlSize]]];
    
    NSDictionary *attributes = @{NSFontAttributeName : font,
                                 NSForegroundColorAttributeName : [NSColor linkColor],
                                 NSUnderlineStyleAttributeName : @(NSUnderlineStyleSingle)};
    
    NSAttributedString *attributedTitle = [[NSAttributedString alloc] initWithString:self.title attributes:attributes];
    self.attributedTitle = attributedTitle;

    // I can't see us ever changing the state of these buttons, so making a whole seperate color for them when we're trying to use system colors and there's only 1 link color seems... futile.
//    attributes = @{NSFontAttributeName : font,
//                   NSForegroundColorAttributeName : [[self class] linkColor],
//                   NSUnderlineStyleAttributeName : @(NSUnderlineStyleSingle)};
//    attributedTitle = [[NSAttributedString alloc] initWithString:self.title attributes:attributes];
    self.attributedAlternateTitle = attributedTitle;

}

@end
