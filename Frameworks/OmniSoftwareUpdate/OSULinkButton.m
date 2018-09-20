// Copyright 2013-2018 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OSULinkButton.h"

#import <AvailabilityMacros.h>

RCS_ID("$Id$");

@implementation OSULinkButton

+ (NSColor *)linkColor;
{
#if defined(MAC_OS_X_VERSION_10_14)
    // +linkColor is marked available back to 10.10, but was only introduced in the 10.14 headers. Use it if we're building in an SDK that knows about 10.14, but don't require that the app's min version be 10.14.
    return [NSColor linkColor];
#else
    return [NSColor colorWithHue:218.0/360.0 saturation:0.95 brightness:0.96 alpha:1.0];
#endif
}

- (void)awakeFromNib;
{
    [super awakeFromNib];
    
    NSFont *font = self.font;
    if (!font)
        font = [NSFont systemFontOfSize:[NSFont systemFontSizeForControlSize:[self.cell controlSize]]];
    
    NSDictionary *attributes = @{NSFontAttributeName : font,
                                 NSForegroundColorAttributeName : [[self class] linkColor],
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
