// Copyright 1997-2005, 2007-2009 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSAttributedString.h>
#import <Foundation/NSGeometry.h> // For NSRect

@class NSImage;

@interface NSAttributedString (OAExtensions)

+ (NSString *)attachmentString;

+ (NSAttributedString *)attributedStringWithImage:(NSImage *)anImage;

- (NSAttributedString *)initWithHTML:(NSString *)htmlString;
- (NSString *)htmlString;
- (NSData *)rtf;

- (NSAttributedString *)substringWithEllipsisToWidth:(CGFloat)width;

- (void)drawInRectangle:(NSRect)rectangle alignment:(int)alignment verticallyCentered:(BOOL)verticallyCenter;

- (void)drawCenteredShrinkingToFitInRect:(NSRect)rect;

@end
