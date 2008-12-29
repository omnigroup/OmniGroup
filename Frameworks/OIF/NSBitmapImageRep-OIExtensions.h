// Copyright 1999-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <AppKit/NSBitmapImageRep.h>

@interface NSBitmapImageRep (OIExtensions)

#if 0
/* Low-efficiency methods for extracting single pixels from an NSBitmapImageRep */

/* slow, but general */
- (NSColor *)colorOfPixel:(unsigned)x :(unsigned)y;

/* faster, but forces extra restrictions on image content */
- (void)getRGBA:(unsigned int *)c forPixelAtX:(unsigned)x y:(unsigned)y scaledToBPS:(int)bps;

/* Another possibility would be:
- (NSDictionary *)componentsOfPixelsForRow:(int)row colorSpaceName:(NSString *)foo scaledToBPS:(int)bps;

where the dictionary would have keys "red", "cyan", "saturation", "alpha", whatever, and values which are NSDatas containing a zillion ints, or possibly a special wrapper object which wraps array(s) of integers efficiently. This would be fast *and* not suck too much. */

#endif

@end
