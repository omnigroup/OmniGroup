// Copyright 2000-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <AppKit/NSFontManager.h>

@interface NSFontManager (OAExtensions)
- (NSFont *)closestFontWithFamily:(NSString *)family traits:(NSFontTraitMask)traits size:(float)size;
- (NSFont *)closestFontWithFamily:(NSString *)family traits:(NSFontTraitMask)traits weight:(int)weight size:(float)size;
@end
