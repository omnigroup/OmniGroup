// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Availability.h>

#import <Foundation/NSAttributedString.h>
#import <OmniFoundation/OFGeometry.h>
#import <OmniAppKit/OATextAttachment.h>

@interface NSAttributedString (OAExtensions)

@property(class,readonly) NSString *attachmentString;

- (BOOL)containsAttribute:(NSString *)attributeName;
- (BOOL)containsAttribute:(NSString *)attributeName inRange:(NSRange)range;

- (BOOL)containsAttachments;
- (id)attachmentAtCharacterIndex:(NSUInteger)characterIndex;

- (void)eachAttachmentInRange:(NSRange)range action:(void (^ NS_NOESCAPE)(NSRange attachmentRange, __kindof OATextAttachment *attachment, BOOL *stop))applier;
- (void)eachAttachment:(void (^ NS_NOESCAPE)(NSRange attachmentRange, __kindof OATextAttachment *attachment, BOOL *stop))applier;

#if OMNI_BUILDING_FOR_MAC
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
