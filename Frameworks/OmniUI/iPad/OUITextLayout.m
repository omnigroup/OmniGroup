// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUITextLayout.h>

#import <OmniFoundation/NSAttributedString-OFExtensions.h>
#import <OmniFoundation/NSMutableAttributedString-OFExtensions.h>
#import <OmniAppKit/OATextAttributes.h>
#import <OmniQuartz/OQDrawing.h>

#include <string.h>

#import <OmniBase/OmniBase.h>

RCS_ID("$Id$");

@implementation OUITextLayout

+ (NSDictionary *)defaultLinkTextAttributes;
{
    static NSDictionary *attributes = nil;
    
    if (!attributes)
        attributes = [[NSDictionary alloc] initWithObjectsAndKeys:(id)[[UIColor blueColor] CGColor], OAForegroundColorAttributeName,
                      [NSNumber numberWithUnsignedInt:kCTUnderlineStyleSingle], OAUnderlineStyleAttributeName, nil];
    
    return attributes;
}

CTFontRef OUIGlobalDefaultFont(void)
{
    static CTFontRef globalFont = NULL;
    if (!globalFont)
        globalFont = CTFontCreateWithName(CFSTR("Helvetica"), 12, NULL);
    return globalFont;
}

- initWithAttributedString:(NSAttributedString *)attributedString_ constraints:(CGSize)constraints;
{
    _attributedString = [attributedString_ copy];
    CFAttributedStringRef attributedString = (CFAttributedStringRef)_attributedString;
    
    OBPRECONDITION(attributedString);
    if (!attributedString) {
        _usedSize = CGRectZero;
        return nil;
    }
    
    
    CFIndex baseStringLength = CFAttributedStringGetLength(attributedString);
    CFMutableAttributedStringRef paddedString = CFAttributedStringCreateMutableCopy(kCFAllocatorDefault, 1+baseStringLength, attributedString);
    CFDictionaryRef attrs = NULL;
    if (baseStringLength > 0) {
        attrs = CFAttributedStringGetAttributes(paddedString, baseStringLength-1, NULL);
        CFRetain(attrs);
    } else {
        CFTypeRef attrKeys[1] = { kCTFontAttributeName };
        CFTypeRef attrValues[1] = { OUIGlobalDefaultFont() };
        attrs = CFDictionaryCreate(kCFAllocatorDefault, attrKeys, attrValues, 1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    }
    CFAttributedStringRef addend = CFAttributedStringCreate(kCFAllocatorDefault, CFSTR("\n"), attrs);
    CFRelease(attrs);
    CFAttributedStringReplaceAttributedString(paddedString, (CFRange){ baseStringLength, 0}, addend);
    CFRelease(addend);
    
    CTFramesetterRef framesetter = CTFramesetterCreateWithAttributedString(paddedString);
    
    CFDictionaryRef frameAttributes = NULL;

    _layoutSize = constraints;
    if (_layoutSize.width <= 0)
        _layoutSize.width = 100000;
    if (_layoutSize.height <= 0)
        _layoutSize.height = 100000;
    
    CGMutablePathRef path = CGPathCreateMutable();
    CGPathAddRect(path, NULL/*transform*/, CGRectMake(0, 0, _layoutSize.width, _layoutSize.height));
    
    /* Many CoreText APIs accept a zero-length range to mean "until the end" */
    _frame = CTFramesetterCreateFrame(framesetter, (CFRange){0, 0}, path, frameAttributes);
    CFRelease(path);
    CFRelease(framesetter);
    CFRelease(paddedString);
    
    _usedSize = OUITextLayoutMeasureFrame(_frame, NO);
    
    return self;
}

- (void)dealloc;
{
    [_attributedString release];
    if (_frame)
        CFRelease(_frame);

    [super dealloc];
}

@synthesize attributedString = _attributedString;

- (CGSize)usedSize
{
    return _usedSize.size;
}

- (void)drawInContext:(CGContextRef)ctx;
{
    CGRect bounds;
    bounds.origin = CGPointZero;
    bounds.size = _usedSize.size;
    
    CGPoint layoutOrigin = OUITextLayoutOrigin(_usedSize, UIEdgeInsetsZero, bounds, 1.0f);
    
    OUITextLayoutDrawFrame(ctx, _frame, bounds, layoutOrigin);
}

- (void)drawFlippedInContext:(CGContextRef)ctx bounds:(CGRect)bounds;
{
    CGContextSaveGState(ctx);
    {
        OQFlipVerticallyInRect(ctx, bounds);
        
        CGContextTranslateCTM(ctx, 0, CGRectGetHeight(bounds) - _usedSize.size.height);
        
        [self drawInContext:ctx];
    }
    CGContextRestoreGState(ctx);
}

#if 0
static void _logLines(CGContextRef ctx, CTFrameRef frame)
{
    CFArrayRef lines = CTFrameGetLines(frame);
    CFIndex lineCount = CFArrayGetCount(lines);
    
    CGFloat minY = CGFLOAT_MAX, maxY = 0;
    CGPoint *origins = malloc(sizeof(*origins) * lineCount);
    CTFrameGetLineOrigins(frame, CFRangeMake(0, lineCount), origins);
    
    for (CFIndex lineIndex = 0; lineIndex < lineCount; lineIndex++) {
        CTLineRef line = CFArrayGetValueAtIndex(lines, lineIndex);
        CGRect imageBounds = CTLineGetImageBounds(line, ctx);
        
        CGFloat ascent, descent, leading;
        double width = CTLineGetTypographicBounds(line, &ascent, &descent, &leading);
        
        CFRange lineRange = CTLineGetStringRange(line);
        
        NSLog(@"line:%d range:{%d, %d} image bounds:%@ origin:%@", lineIndex, lineRange.location, lineRange.length, NSStringFromRect(imageBounds), NSStringFromPoint(origins[lineIndex]));
        NSLog(@"  width:%f ascent:%f descent:%f leading:%f", width, ascent, descent, leading);
        
        minY = MIN(minY, CGRectGetMinY(imageBounds));
        maxY = MAX(maxY, CGRectGetMaxY(imageBounds));
    }
    
    NSLog(@" delta Y for all lines %f", maxY - minY);
    
    free(origins);
}
#endif

// CTFramesetterSuggestFrameSizeWithConstraints seems to be useless. It doesn't return a size that will avoid wrapping in the real frame setter. Also, it doesn't include the descender of the bottom line.
CGRect OUITextLayoutMeasureFrame(CTFrameRef frame, BOOL includeTrailingWhitespace)
{
    CFArrayRef lines = CTFrameGetLines(frame);
    CFIndex lineCount = CFArrayGetCount(lines);
    
    if (lineCount > 0) {
        CGPoint lineOrigins[lineCount];
        CTFrameGetLineOrigins(frame, CFRangeMake(0, lineCount), lineOrigins);
        
        CGFloat minX, maxX, minY, maxY;
        CGFloat ascent, descent;
        double width;
        
        CTLineRef line = CFArrayGetValueAtIndex(lines, 0);
        minX = lineOrigins[0].x;
        width = CTLineGetTypographicBounds(line, &ascent, &descent, NULL);
        maxX = minX + ( includeTrailingWhitespace? width : width - CTLineGetTrailingWhitespaceWidth(line));
        maxY = lineOrigins[0].y + ascent;
        minY = lineOrigins[0].y - descent;
        
        for (CFIndex lineIndex = 1; lineIndex < lineCount; lineIndex++) {
            CTLineRef line = CFArrayGetValueAtIndex(lines, lineIndex);
            width = CTLineGetTypographicBounds(line, &ascent, &descent, NULL);
            CGPoint lineOrigin = lineOrigins[lineIndex];
            if (lineOrigin.x < minX)
                minX = lineOrigin.x;
            if (lineOrigin.x + width > maxX) {
                if (!includeTrailingWhitespace)
                    width -= CTLineGetTrailingWhitespaceWidth(line);
                CGFloat thisMaxX = lineOrigin.x + width;
                if (thisMaxX > maxX)
                    maxX = thisMaxX;
            }
            
            if (lineOrigins[lineIndex].y + ascent > maxY)
                maxY = lineOrigins[lineIndex].y + ascent;
            if (lineOrigins[lineIndex].y - descent < minY)
                minY = lineOrigins[lineIndex].y - descent;
        }

        return (CGRect){
            { minX, minY },
            { MAX(0, maxX - minX), MAX(0, maxY - minY) }
        };
    } else {
        return CGRectNull;
    }
}

CGPoint OUITextLayoutOrigin(CGRect typographicFrame, UIEdgeInsets textInset, // in text coordinates
                            CGRect bounds, // view rect we want to draw in
                            CGFloat scale) // scale factor from text to view
{
    // We don't offset the layoutOrigin for a non-zero bounds origin.
    OBASSERT(CGPointEqualToPoint(bounds.origin, CGPointZero));
    
    CGPoint layoutOrigin;
    
    // And compute the layout origin, pinning the text to the *top* of the view
    layoutOrigin.x = - typographicFrame.origin.x;
    layoutOrigin.y = CGRectGetMaxY(bounds) / scale - CGRectGetMaxY(typographicFrame);
    layoutOrigin.x += textInset.left;
    layoutOrigin.y -= textInset.top;
    
    // Lessens jumpiness when transitioning between a OUITextLayout for display and OUIEditableFrame for editing. But, it seems weird to be rounding in text space instead of view space. Maybe works out since we end up having to draw at pixel-side for UIKit backing store anyway. Still some room for improvement here.
//    layoutOrigin.x = floor(layoutOrigin.x);
//    layoutOrigin.y = floor(layoutOrigin.y);
    
    return layoutOrigin;
}

void OUITextLayoutDrawFrame(CGContextRef ctx, CTFrameRef frame, CGRect bounds, CGPoint layoutOrigin)
{
    CGContextSetTextPosition(ctx, 0, 0);
    CGContextSetTextMatrix(ctx, CGAffineTransformIdentity);
    
    CGContextTranslateCTM(ctx, layoutOrigin.x, layoutOrigin.y);
        
    CTFrameDraw(frame, ctx);

    CGContextTranslateCTM(ctx, -layoutOrigin.x, -layoutOrigin.y);
}

/* Fix up paragraph styles. We want any paragraph to have only one paragraph style associated with it. */
void OUITextLayoutFixupParagraphStyles(NSMutableAttributedString *content)
{
    NSUInteger contentLength = [content length];
    NSUInteger cursor = 0;
    NSString *paragraphStyle = (id)kCTParagraphStyleAttributeName;
    
    while (cursor < contentLength) {
        NSRange styleRange;
        [content attribute:paragraphStyle atIndex:cursor longestEffectiveRange:&styleRange inRange:(NSRange){cursor, contentLength-cursor}];
        if ((styleRange.location + styleRange.length) >= contentLength)
            break;
        NSUInteger paragraphStart, paragraphEnd, paragraphContentsEnd;
        [[content string] getParagraphStart:&paragraphStart end:&paragraphEnd contentsEnd:&paragraphContentsEnd forRange:(NSRange){styleRange.location + styleRange.length - 1, 1}];
        if (paragraphEnd > styleRange.location + styleRange.length) {
            /* The containing paragraph extends past the end of this run of paragraph styles, so we'll need to fix things up */
            
            /*
             Two heuristics.
             One: If the paragraph end has a style, apply it to the whole paragraph. This imitates the behavior of many text editors (including TextEdit) where the paragraph style behaves as if it's attached to the end-of-paragraph character.
             Two: Otherwise, use the last (non-nil) paragraph style in the range. (Not sure if this is best, but it's easy. Maybe we should do a majority-rules kind of thing? But most of the time, whoever modifies the paragraph should ensure that the styles are reasonably handled by heuristic one.)
             If these both fail, we'll fall through to the default styles case, below.
             */
            
            NSRange paragraphRange = (NSRange){paragraphStart, paragraphEnd-paragraphStart};
            NSRange eolStyleRange;
            id eolStyle, applyStyle;
            if (paragraphContentsEnd > paragraphEnd) {
                eolStyle = [content attribute:paragraphStyle atIndex:paragraphContentsEnd longestEffectiveRange:&eolStyleRange inRange:paragraphRange];
            } else {
                /* This is a little obtuse, but if there's no EOL marker, we can just get the style of the last character, and we end up implementing heuristic two */
                eolStyle = [content attribute:paragraphStyle atIndex:paragraphContentsEnd-1 longestEffectiveRange:&eolStyleRange inRange:paragraphRange];
            }
            
            if (eolStyle) {
                applyStyle = eolStyle;
            } else {
                /* Since we got nil, and asked for the longest effective range, we know the character right before the returned effective range must have a non-nil style */
                applyStyle = [content attribute:paragraphStyle atIndex:eolStyleRange.location - 1 effectiveRange:NULL];
            }
            
            /* Apply this to the whole paragraph */
            [content addAttribute:paragraphStyle value:applyStyle range:paragraphRange];
            cursor = paragraphEnd;
        } else {
            /* No fixup needed: the style boundary is also a paragraph boundary. */
            cursor = styleRange.location + styleRange.length;
        }
    }
}

static NSAttributedString *_applyTransformedAttributes(NSMutableAttributedString *source, NSDictionary *attributes, NSRange matchRange, NSRange effectiveAttributeRange, BOOL *isEditing, void *context)
{
    NSDictionary *linkAttributes = context;
    
    if ([attributes objectForKey:OALinkAttributeName]) {
        if (!*isEditing) {
            [source beginEditing];
            *isEditing = YES;
        }
        [source addAttributes:linkAttributes range:effectiveAttributeRange];
    }
    
    // We made only attribute changes (if any at all).
    return nil;
}

// Later, we may have a callout for a delegate to extent the transformation.
// Returns nil if no transformation is done, instead of returning [soure copy].
NSAttributedString *OUICreateTransformedAttributedString(NSAttributedString *source, NSDictionary *linkAttributes)
{
    if ([linkAttributes count] == 0 || ![source hasAttribute:OALinkAttributeName])
        return nil; // No transform needed!
    
    NSMutableAttributedString *transformed = [source mutableCopy];
    
    [transformed mutateRanges:_applyTransformedAttributes matchingString:nil context:linkAttributes];
    
    NSAttributedString *immutableResult = [transformed copy];
    [transformed release];

    return immutableResult;
}

@end

