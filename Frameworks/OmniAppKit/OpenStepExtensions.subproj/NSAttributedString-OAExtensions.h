// Copyright 1997-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Availability.h>

// Availability macros don't work reliably when module headers are implicitly built, so use ours as a backup.
#if (defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE) || OMNI_BUILDING_FOR_IOS
    #import <UIKit/NSAttributedString.h>
    #import <CoreGraphics/CGGeometry.h>
#else
    #import <AppKit/NSAttributedString.h>
    #import <Foundation/NSGeometry.h>
#endif

#import <OmniAppKit/OATextAttachment.h>

@interface NSAttributedString (OAExtensions)

+ (NSString *)attachmentString;

- (BOOL)containsAttribute:(NSString *)attributeName;
- (BOOL)containsAttribute:(NSString *)attributeName inRange:(NSRange)range;

- (BOOL)containsAttachments;
- (id)attachmentAtCharacterIndex:(NSUInteger)characterIndex;

- (void)eachAttachment:(void (^)(OATextAttachment *, BOOL *stop))applier;

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
+ (NSAttributedString *)attributedStringWithImage:(NSImage *)anImage;

- (NSData *)rtf;

// The following three methods are for single line string rendering
- (void)drawInRectangle:(NSRect)rectangle verticallyCentered:(BOOL)verticallyCenter;
// These next two are conveniences for adding paragraph style attributes and make a mutableCopy of self
- (void)drawInRectangle:(NSRect)rectangle alignment:(NSTextAlignment)alignment verticallyCentered:(BOOL)verticallyCenter;
- (void)drawInRectangle:(NSRect)rectangle alignment:(NSTextAlignment)alignment lineBreakMode:(NSLineBreakMode)lineBreakMode verticallyCentered:(BOOL)verticallyCenter;

- (void)drawCenteredShrinkingToFitInRect:(CGRect)rect;
#endif

@end
