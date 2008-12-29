// Copyright 1997-2005, 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniAppKit/OpenStepExtensions.subproj/NSAttributedString-OAExtensions.h 103451 2008-07-29 19:10:40Z wiml $

#import <Foundation/NSAttributedString.h>
#import <Foundation/NSGeometry.h> // For NSRect

@interface NSAttributedString (OAExtensions)

+ (NSString *)attachmentString;

- (NSAttributedString *)initWithHTML:(NSString *)htmlString;
- (NSString *)htmlString;
- (NSData *)rtf;

- (NSAttributedString *)substringWithEllipsisToWidth:(CGFloat)width;

- (void)drawInRectangle:(NSRect)rectangle alignment:(int)alignment verticallyCentered:(BOOL)verticallyCenter;

- (void)drawCenteredShrinkingToFitInRect:(NSRect)rect;

@end
