// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUITextLayout.h>
#import <Foundation/NSAttributedString.h>
#import <CoreText/CTStringAttributes.h>

#include <string.h>

#import <OmniBase/OmniBase.h>

RCS_ID("$Id$");

#if 0
typedef struct {
    CGPoint origin;
    double width;
    CGFloat ascent, descent, leading;
} LineMeasurements;

static LineMeasurements _lineMeasurements(CTFrameRef frame, CFArrayRef lines, NSUInteger lineIndex)
{
    LineMeasurements m;
    memset(&m, 0, sizeof(m));
    
    CTLineRef line = CFArrayGetValueAtIndex(lines, lineIndex);
    m.width = CTLineGetTypographicBounds(line, &m.ascent, &m.descent, &m.leading);
    CTFrameGetLineOrigins(frame, CFRangeMake(lineIndex, 1), &m.origin);
    
    return m;
}
#endif

@implementation OUITextLayout

CTFontRef OUIGlobalDefaultFont(void)
{
    CTFontRef globalFont = NULL;
    if (!globalFont)
        globalFont = CTFontCreateWithName(CFSTR("Helvetica"), 12, NULL);
    return globalFont;
}

#if 0
// CTFramesetterSuggestFrameSizeWithConstraints seems to be useless. It doesn't return a size that will avoid wrapping in the real frame setter. Also, it doesn't include the descender of the bottom line.
CGSize OUITextLayoutMeasureSize(CTFrameRef frame)
{
    // Now, calculate the union of the line rects. Assuming top->bottom layout here.
    CFArrayRef lines = CTFrameGetLines(frame);
    CFIndex lineCount = CFArrayGetCount(lines);
    
    CGSize usedSize = CGSizeZero;
    if (lineCount > 0) {
        LineMeasurements firstMeasure, lastMeasure;
        memset(&firstMeasure, 0, sizeof(firstMeasure));
        memset(&lastMeasure, 0, sizeof(lastMeasure));
        
        CGFloat minX = CGFLOAT_MAX;
        double maxWidth = 0;
        
        for (CFIndex lineIndex = 0; lineIndex < lineCount; lineIndex++) {
            LineMeasurements m = _lineMeasurements(frame, lines, lineIndex);
            
            //            CFRange range = CTLineGetStringRange(CFArrayGetValueAtIndex(lines, lineIndex));
            //            NSLog(@"line %d (range %@):", lineIndex, NSStringFromRange(*(NSRange *)&range));
            //            NSLog(@"  origin: %@", NSStringFromPoint(m.origin));
            //            NSLog(@"  width: %f", m.width);
            //            NSLog(@"  ascent: %f", m.ascent);
            //            NSLog(@"  descent: %f", m.descent);
            //            NSLog(@"  leading: %f", m.leading);
            
            if (lineIndex == 0)
                firstMeasure = m;
            else if (lineIndex == lineCount - 1)
                lastMeasure = m;
            
            minX = MIN(minX, m.origin.x);
            maxWidth = MAX(maxWidth, m.width);
        }
        
        // CoreText draws at the max end of the space we gave it, going toward the min end.
        //        NSLog(@"minX:%f maxWidth:%f", minX, maxWidth);
        
        CGFloat height;
        if (lineCount == 1) {
            height = firstMeasure.ascent + firstMeasure.descent;
        } else {
            height = firstMeasure.ascent + (firstMeasure.origin.y - lastMeasure.origin.y) + lastMeasure.descent;
        }
        
        usedSize = CGSizeMake(maxWidth, height);
    }

    //NSLog(@"measured size = %@", NSStringFromSize(usedSize));
    return usedSize;
}
#endif

- initWithAttributedString:(CFAttributedStringRef)attributedString constraints:(CGSize)constraints;
{
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
    if (_frame)
        CFRelease(_frame);

    [super dealloc];
}

- (CGSize)usedSize
{
    return _usedSize.size;
}

- (void)drawInContext:(CGContextRef)ctx;
{
    CGContextTranslateCTM(ctx, - _usedSize.origin.x, - _usedSize.origin.y);
    CGContextSetTextPosition(ctx, 0, 0);
    CGContextSetTextMatrix(ctx, CGAffineTransformIdentity);
    CTFrameDraw(_frame, ctx);
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

#if 0
/* This returns the location, in rendering space, of the origin of the layout space */
CGPoint OUITextLayoutFrameOrigin(CTFrameRef frame)
{
    CFArrayRef lines = CTFrameGetLines(frame);
    CFIndex lineCount = CFArrayGetCount(lines);

    // CoreText draws way off at the max Y range of the allowed size we gave it.  Need to shift back.
    if (lineCount > 0) {
        CGPoint lineOrigins[lineCount];
        CTFrameGetLineOrigins(frame, CFRangeMake(0, lineCount), lineOrigins);
        
        CGFloat lastLineYValue = 0;
        CGFloat minXValue = 0;
        for (CFIndex index = 0; index < lineCount; index++) {
            CGPoint lineOrigin = lineOrigins[index];
            if (index == 0 || lineOrigin.x < minXValue)
                minXValue = lineOrigin.x;
            
            if (index == (lineCount-1))
                lastLineYValue = lineOrigin.y;
        }
        //NSLog(@"last line origin = %@", NSStringFromPoint(lastLineOrigin));
        
        CTLineRef line = CFArrayGetValueAtIndex(lines, lineCount - 1);
        CGFloat ascent, descent, leading;
        /*double width =*/ CTLineGetTypographicBounds(line, &ascent, &descent, &leading);
        
        return (CGPoint){ -minXValue, -lastLineYValue + descent };
    } else {
        return (CGPoint){ 0, 0 };
    }
}

void OUITextLayoutDrawFrame(CGContextRef ctx, CTFrameRef frame)
{
    //_logLines(ctx, frame);
    

    // Drawing text advances the text position and that is NOT saved/restored with the gstate. Reset it each time we draw text to the origin of the coordinate system we just set up.
    CGContextSetTextPosition(ctx, 0, 0);
    
    CFArrayRef lines = CTFrameGetLines(frame);
    CFIndex lineCount = CFArrayGetCount(lines);
    
#if 0
    CGFloat minY = CGFLOAT_MAX, maxY = 0;
    CGPoint *origins = malloc(sizeof(*origins) * lineCount);
    CTFrameGetLineOrigins(frame, CFRangeMake(0, lineCount), origins);
    
    for (CFIndex lineIndex = 0; lineIndex < lineCount; lineIndex++) {
        CTLineRef line = CFArrayGetValueAtIndex(lines, lineIndex);
        CGRect imageBounds = CTLineGetImageBounds(line, ctx);
        
        CGFloat ascent, descent, leading;
        double width = CTLineGetTypographicBounds(line, &ascent, &descent, &leading);
        
        NSLog(@"line:%d image bounds:%@ origin:%@", lineIndex, NSStringFromRect(imageBounds), NSStringFromPoint(origins[lineIndex]));
        NSLog(@"  width:%f ascent:%f descent:%f leading:%f", width, ascent, descent, leading);
        
        minY = MIN(minY, CGRectGetMinY(imageBounds));
        maxY = MAX(maxY, CGRectGetMaxY(imageBounds));
    }
    
    NSLog(@" delta Y for all lines %f", maxY - minY);
    
    free(origins);
#endif
    
    // CoreText draws way off at the max Y range of the allowed size we gave it.  Need to shift back.
    if (lineCount > 0) {
        CGPoint lineOrigins[lineCount];
        CTFrameGetLineOrigins(frame, CFRangeMake(0, lineCount), lineOrigins);
        
        CGFloat lastLineYValue = 0;
        CGFloat minXValue = 0;        
        for (CFIndex index = 0; index < lineCount; index++) {
            CGPoint lineOrigin = lineOrigins[index];
            if (index == 0 || lineOrigin.x < minXValue)
                minXValue = lineOrigin.x;
                
            if (index == (lineCount-1))
                lastLineYValue = lineOrigin.y;
        }
        
        CTLineRef line = CFArrayGetValueAtIndex(lines, lineCount - 1);
        CGFloat ascent, descent, leading;
        /*double width =*/ CTLineGetTypographicBounds(line, &ascent, &descent, &leading);
        
        CGContextTranslateCTM(ctx, -minXValue, -lastLineYValue + descent);
    }
    
    CGContextSetTextMatrix(ctx, CGAffineTransformIdentity);
    CTFrameDraw(frame, ctx);
}
#endif

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

@end

