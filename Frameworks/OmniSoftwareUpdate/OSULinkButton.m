// Copyright 2013-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OSULinkButton.h"

RCS_ID("$Id$");

@implementation OSULinkButton

- (void)awakeFromNib;
{
    [super awakeFromNib];
    
    NSFont *font = self.font;
    if (!font)
        font = [NSFont systemFontOfSize:[NSFont systemFontSizeForControlSize:[self.cell controlSize]]];
    
    NSDictionary *attributes = @{NSFontAttributeName : font,
                                 NSForegroundColorAttributeName : [NSColor colorWithHue:218.0/360.0 saturation:0.95 brightness:0.96 alpha:1.0],
                                 NSUnderlineStyleAttributeName : @(NSUnderlineStyleSingle)};
    
    NSAttributedString *attributedTitle = [[NSAttributedString alloc] initWithString:self.title attributes:attributes];
    self.attributedTitle = attributedTitle;
    
    attributes = @{NSFontAttributeName : font,
                   NSForegroundColorAttributeName : [NSColor colorWithHue:218.0/360.0 saturation:0.95 brightness:0.80 alpha:1.0],
                   NSUnderlineStyleAttributeName : @(NSUnderlineStyleSingle)};
    attributedTitle = [[NSAttributedString alloc] initWithString:self.title attributes:attributes];
    self.attributedAlternateTitle = attributedTitle;
    
}

@end
