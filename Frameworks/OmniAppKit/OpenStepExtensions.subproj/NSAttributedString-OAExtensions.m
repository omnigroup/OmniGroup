// Copyright 1997-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/NSAttributedString-OAExtensions.h>

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>
#import <OmniAppKit/OATextStorage.h> // OAAttachmentCharacter
#if OMNI_BUILDING_FOR_MAC
#import <AppKit/NSStringDrawing.h>
#endif

RCS_ID("$Id$")

#if OMNI_BUILDING_FOR_MAC
@interface OAInlineImageTextAttachmentCell : NSImageCell /* <NSTextAttachmentCell> */
@property (nonatomic,weak) OATextAttachment *attachment;
@end
#endif

@implementation NSAttributedString (OAExtensions)

+ (NSString *)attachmentString;
{
    static NSString *AttachmentString = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        unichar c = OAAttachmentCharacter;
        AttachmentString = [[NSString alloc] initWithCharacters:&c length:1];
    });
    return AttachmentString;
}

- (BOOL)containsAttribute:(NSString *)attributeName;
{
    return [self containsAttribute:attributeName inRange:NSMakeRange(0, [self length])];
}

- (BOOL)containsAttribute:(NSString *)attributeName inRange:(NSRange)range;
{
    NSUInteger position = range.location, end = NSMaxRange(range);
    
    while (position < end) {
        NSRange effectiveRange;
        if ([self attribute:attributeName atIndex:position effectiveRange:&effectiveRange])
            return YES;
        position = NSMaxRange(effectiveRange);
    }
    
    return NO;
}

- (BOOL)containsAttachments;
{
    return [self containsAttribute:OAAttachmentAttributeName];
}

- (id)attachmentAtCharacterIndex:(NSUInteger)characterIndex;
{
    return [self attribute:OAAttachmentAttributeName atIndex:characterIndex effectiveRange:NULL];
}

- (void)eachAttachmentInRange:(NSRange)range action:(void (^ NS_NOESCAPE)(NSRange attachmentRange, __kindof OATextAttachment *attachment, BOOL *stop))applier;
{
    NSString *string = [self string];
    NSString *attachmentString = [NSAttributedString attachmentString];

    NSUInteger location = range.location, end = NSMaxRange(range);
    BOOL stop = NO;
    while (location < end && !stop) {
        NSRange attachmentRange = [string rangeOfString:attachmentString options:NSLiteralSearch range:NSMakeRange(location,end-location)];
        if (attachmentRange.length == 0)
            break;

        OATextAttachment *attachment = [self attribute:OAAttachmentAttributeName atIndex:attachmentRange.location effectiveRange:NULL];

        // It is possible to have stray attachment characters without an attachment.
        if (attachment) {
            applier(attachmentRange, attachment, &stop);
        }

        location = NSMaxRange(attachmentRange);
    }
}

- (void)eachAttachment:(void (^ NS_NOESCAPE)(NSRange attachmentRange, __kindof OATextAttachment *attachment, BOOL *stop))applier;
{
    [self eachAttachmentInRange:NSMakeRange(0, [self length]) action:applier];
}

#if OMNI_BUILDING_FOR_MAC
+ (NSAttributedString *)attributedStringWithImage:(NSImage *)anImage;
{
    OAInlineImageTextAttachmentCell *imageCell = [[OAInlineImageTextAttachmentCell alloc] initImageCell:anImage];
    OATextAttachment *attach = [[OATextAttachment alloc] initWithFileWrapper:nil];
    [attach setAttachmentCell:(id <NSTextAttachmentCell>)imageCell];

    NSAttributedString *result = [self attributedStringWithAttachment:attach];
    return result;
}
#endif

#if OMNI_BUILDING_FOR_MAC
- (NSData *)rtf;
{
    return [self RTFFromRange:NSMakeRange(0, [self length]) documentAttributes:@{}];
}
#endif

#if OMNI_BUILDING_FOR_MAC
// ASSUMPTION: These are for one line
- (void)drawInRectangle:(NSRect)rectangle verticallyCentered:(BOOL)verticallyCenter;
{
    if (verticallyCenter) {
        NSRect boundingRect = [self boundingRectWithSize:rectangle.size options:NSStringDrawingTruncatesLastVisibleLine | NSStringDrawingUsesLineFragmentOrigin context:nil];
        rectangle = OAInsetRectBySize(rectangle, NSMakeSize(0, (NSHeight(rectangle) - NSHeight(boundingRect)) / 2.0f));
    }
    
    [self drawWithRect:rectangle options:NSStringDrawingTruncatesLastVisibleLine | NSStringDrawingUsesLineFragmentOrigin context:nil];
}

- (void)drawInRectangle:(NSRect)rectangle alignment:(NSTextAlignment)alignment verticallyCentered:(BOOL)verticallyCenter;
{
    NSMutableParagraphStyle *pStyle = [[NSMutableParagraphStyle alloc] init];
    pStyle.alignment = alignment;
    [self drawInRectangle:rectangle paragraphStyle:pStyle verticallyCentered:verticallyCenter];
}

- (void)drawInRectangle:(NSRect)rectangle alignment:(NSTextAlignment)alignment lineBreakMode:(NSLineBreakMode)lineBreakMode verticallyCentered:(BOOL)verticallyCenter;
{
    NSMutableParagraphStyle *pStyle = [[NSMutableParagraphStyle alloc] init];
    pStyle.alignment = alignment;
    pStyle.lineBreakMode = lineBreakMode;
    [self drawInRectangle:rectangle paragraphStyle:pStyle verticallyCentered:verticallyCenter];
}

- (void)drawInRectangle:(NSRect)rectangle paragraphStyle:(NSParagraphStyle *)pStyle verticallyCentered:(BOOL)verticallyCenter;
{
#ifdef OMNI_ASSERTIONS_ON
    [self enumerateAttribute:NSParagraphStyleAttributeName inRange:NSMakeRange(0, self.length) options:0 usingBlock:^(id value, NSRange range, BOOL *stop) {
        if (value) {
            OBASSERT_NOT_REACHED("This is a convenience method for mashing a paragraph style into an attributed string and drawing it. If you are already providing paragraph styles provide all attributes as desired and call drawWithRect:options: instead");
            *stop = YES;
        }
    }];
#endif
    
    NSMutableAttributedString *mutableCopy = [self mutableCopy];
    [mutableCopy addAttribute:NSParagraphStyleAttributeName value:pStyle range:NSMakeRange(0, mutableCopy.length)];
    
    [mutableCopy drawInRectangle:rectangle verticallyCentered:verticallyCenter];
}

- (void)drawCenteredShrinkingToFitInRect:(NSRect)rect;
{
    NSSize size = [self size];
    CGFloat scale = MIN(NSWidth(rect) / size.width, NSHeight(rect) / size.height);
    if (scale >= 1.0) {
	rect.origin.y += (NSHeight(rect) - size.height) / 2.0f;
	[self drawInRect:rect];
	return;
    }
    
    NSAffineTransform *transform = [NSAffineTransform transform];
    [transform translateXBy:rect.origin.x yBy:rect.origin.y];
    [transform scaleBy:scale];
    [[NSGraphicsContext currentContext] saveGraphicsState];
    [transform concat];
    rect.origin = NSZeroPoint;
    rect.size.width /= scale;
    rect.size.height /= scale;
    [self drawInRect:rect];
    [[NSGraphicsContext currentContext] restoreGraphicsState];
}
#endif

@end


#if OMNI_BUILDING_FOR_MAC
@implementation OAInlineImageTextAttachmentCell

// Many of the NSTextAttachmentCell protocol's methods are supplied by NSCell.
// - (void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)controlView;
// - (void)highlight:(BOOL)flag withFrame:(NSRect)cellFrame inView:(NSView *)controlView;
// - (BOOL)trackMouse:(NSEvent *)theEvent inRect:(NSRect)cellFrame ofView:(NSView *)controlView untilMouseUp:(BOOL)flag;

- (BOOL)wantsToTrackMouse;
{
    return NO;
}

- (NSPoint)cellBaselineOffset;
{
    NSImage *img = [self image];
    if (img) {
        return [img alignmentRect].origin;
    } else {
        return (NSPoint){0, 0};
    }
}

- (NSSize)cellSize
{
    return [[self image] size];
}

@end
#endif


