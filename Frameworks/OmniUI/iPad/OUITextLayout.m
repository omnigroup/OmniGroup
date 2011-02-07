// Copyright 2010-2011 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUITextLayout.h>

#import <OmniFoundation/NSAttributedString-OFExtensions.h>
#import <OmniFoundation/NSMutableAttributedString-OFExtensions.h>
#import <OmniAppKit/OATextAttributes.h>
#import <OmniAppKit/OATextAttachment.h>
#import <OmniAppKit/OATextAttachmentCell.h>
#import <OmniAppKit/OATextStorage.h>

#import <OmniQuartz/OQDrawing.h>
#import <CoreText/CoreText.h>

#include <string.h>

#import <OmniBase/OmniBase.h>

RCS_ID("$Id$");

#if 0 && defined(DEBUG)
    #define DEBUG_TEXT(format, ...) NSLog(@"TEXT: " format, ## __VA_ARGS__)
#else
    #define DEBUG_TEXT(format, ...)
#endif

// Lowering this from 1e6 to 1e5 seems to help some pixel shifting when switching between drawing with OUITextLayout and OUIEditableFrame.
// This may be a spurious coverup for other issues, but its also possible that larger values cause intermediate floats in transform calculations become too large and lose precision.
// <bug://bugs/68432> (Text shifty/jumpy when editing under a scale)
const CGFloat OUITextLayoutUnlimitedSize = 100000;

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
    OBPRECONDITION(attributedString_);

    if (!(self = [super init]))
        return nil;
    
    _attributedString = [attributedString_ copy];
    CFAttributedStringRef attributedString = (CFAttributedStringRef)_attributedString;
    
    if (!attributedString) {
        [self release];
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
    CFRelease(paddedString);

    CFDictionaryRef frameAttributes = NULL;

    _layoutSize = constraints;
    if (_layoutSize.width <= 0)
        _layoutSize.width = OUITextLayoutUnlimitedSize;
    if (_layoutSize.height <= 0)
        _layoutSize.height = OUITextLayoutUnlimitedSize;
    
    BOOL widthIsConstrained = _layoutSize.width != OUITextLayoutUnlimitedSize;
    
    CGMutablePathRef path = CGPathCreateMutable();
    CGPathAddRect(path, NULL/*transform*/, CGRectMake(0, 0, _layoutSize.width, _layoutSize.height));
    //NSLog(@"%@ textLayout using %f x %f", [attributedString_ string], _layoutSize.width, _layoutSize.height);
    
    /* Many CoreText APIs accept a zero-length range to mean "until the end" */
    _frame = CTFramesetterCreateFrame(framesetter, (CFRange){0, 0}, path, frameAttributes);
    CFRelease(path);
    
    _usedSize = OUITextLayoutMeasureFrame(_frame, NO, widthIsConstrained);
    
    if (!widthIsConstrained) {
        path = CGPathCreateMutable();
        CGPathAddRect(path, NULL, CGRectMake(0, 0, _usedSize.size.width, _layoutSize.height));
        
        CFRelease(_frame);
        _frame = CTFramesetterCreateFrame(framesetter, (CFRange){0, 0}, path, NULL);
        CFRelease(path);
    }
    
    CFRelease(framesetter);
    
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
        CGContextTranslateCTM(ctx, bounds.origin.x, bounds.origin.y);
        OQFlipVerticallyInRect(ctx, CGRectMake(0, 0, bounds.size.width, bounds.size.height));
        
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
        
        DEBUG_TEXT(@"line:%ld range:{%ld, %ld} image bounds:%@ origin:%@", lineIndex, lineRange.location, lineRange.length, NSStringFromCGRect(imageBounds), NSStringFromCGPoint(origins[lineIndex]));
        DEBUG_TEXT(@"  width:%f ascent:%f descent:%f leading:%f", width, ascent, descent, leading);
        
        minY = MIN(minY, CGRectGetMinY(imageBounds));
        maxY = MAX(maxY, CGRectGetMaxY(imageBounds));
    }
    
    DEBUG_TEXT(@" delta Y for all lines %f", maxY - minY);
    
    free(origins);
}
#endif

// CTFramesetterSuggestFrameSizeWithConstraints seems to be useless. It doesn't return a size that will avoid wrapping in the real frame setter. Also, it doesn't include the descender of the bottom line.
CGRect OUITextLayoutMeasureFrame(CTFrameRef frame, BOOL includeTrailingWhitespace, BOOL widthIsConstrained)
{
    CFArrayRef lines = CTFrameGetLines(frame);
    CFIndex lineCount = CFArrayGetCount(lines);
    
    if (lineCount == 0)
        return CGRectNull;

    CGPoint lineOrigins[lineCount];
    CTFrameGetLineOrigins(frame, CFRangeMake(0, lineCount), lineOrigins);
        
    CGFloat minX = CGFLOAT_MAX, minY = CGFLOAT_MAX;
    CGFloat maxX = CGFLOAT_MIN, maxY = CGFLOAT_MIN;
    
    for (CFIndex lineIndex = 0; lineIndex < lineCount; lineIndex++) {
        CTLineRef line = CFArrayGetValueAtIndex(lines, lineIndex);
        
        CGFloat ascent, descent;
        double width = CTLineGetTypographicBounds(line, &ascent, &descent, NULL);
        
        CGPoint lineOrigin = lineOrigins[lineIndex];
        
        DEBUG_TEXT(@"line %ld: origin:%@ ascent:%f descent:%f width:%f whitespace:%f", lineIndex, NSStringFromCGPoint(lineOrigin), ascent, descent, width, CTLineGetTrailingWhitespaceWidth(line));
        
        minX = MIN(minX, widthIsConstrained ? lineOrigin.x : 0);
        
        if (!includeTrailingWhitespace)
            width -= CTLineGetTrailingWhitespaceWidth(line);
        CGFloat thisMaxX = widthIsConstrained ? lineOrigin.x + width : width;
        maxX = MAX(maxX, thisMaxX);
        
        minY = MIN(minY, lineOrigins[lineIndex].y - descent);
        maxY = MAX(maxY, lineOrigins[lineIndex].y + ascent);
        
        DEBUG_TEXT(@"  x:%f..%f y:%f..%f", minX, maxX, minY, maxY);
    }
    
    CGRect result = CGRectMake(minX, minY, MAX(0, maxX - minX), MAX(0, maxY - minY));
    DEBUG_TEXT(@"measured frame: %@", NSStringFromCGRect(result));
    return result;
}

CGPoint OUITextLayoutOrigin(CGRect typographicFrame, UIEdgeInsets textInset, // in text coordinates
                            CGRect bounds, // view rect we want to draw in
                            CGFloat scale) // scale factor from text to view
{
    // We don't offset the layoutOrigin for a non-zero bounds origin.
    OBASSERT(CGPointEqualToPoint(bounds.origin, CGPointZero));
    
    CGPoint layoutOrigin;
    
    // And compute the layout origin, pinning the text to the *top* of the view
    layoutOrigin.x = textInset.left;
    layoutOrigin.y = CGRectGetMaxY(bounds) / scale - CGRectGetMaxY(typographicFrame);
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

    // TODO: Instead of passing in the string, add a function to build an array of CTRunRefs that actually have an attachment and cache that? OTOH, maybe we should just avoid drawing if this is slow!
    CFArrayRef lines = CTFrameGetLines(frame);
    CFIndex lineIndex = CFArrayGetCount(lines);
    while (lineIndex--) {
        CTLineRef line = CFArrayGetValueAtIndex(lines, lineIndex);
        CFArrayRef runs = CTLineGetGlyphRuns(line);
        CFIndex runIndex = CFArrayGetCount(runs);
        while (runIndex--) {
            CTRunRef run = CFArrayGetValueAtIndex(runs, runIndex);
            CFRange range = CTRunGetStringRange(run);

            //NSLog(@"line %p run %p range %ld/%ld", line, run, range.location, range.length);
            
            if (range.length != 1)
                continue;
            
            CFDictionaryRef attributes = CTRunGetAttributes(run);
            if (!attributes)
                continue;
            
            CTRunDelegateRef runDelegate = CFDictionaryGetValue(attributes, kCTRunDelegateAttributeName);
            //NSLog(@"  runDelegate %p", runDelegate);
            //NSLog(@"  attributes %@", attributes);
            
            if (runDelegate) {
                OATextAttachment *attachment = (OATextAttachment *)CTRunDelegateGetRefCon(runDelegate);
                OBASSERT([attachment isKindOfClass:[OATextAttachment class]]);
                
                OATextAttachmentCell *cell = attachment.attachmentCell;
                OBASSERT(cell);
                OBASSERT(CTRunGetGlyphCount(run) == 1);
                
                CGFloat ascent, descent, leading;
                double width = CTRunGetTypographicBounds(run, CFRangeMake(0, 0), &ascent, &descent, &leading);
                //NSLog(@"  typo width:%f ascent:%f descent:%f leading:%f", width, ascent, descent, leading);

                const CGPoint *positions = CTRunGetPositionsPtr(run);
                //NSLog(@"  glyph position %@", NSStringFromCGPoint(positions[0]));

                CGPoint lineOrigin;
                CTFrameGetLineOrigins(frame, CFRangeMake(lineIndex, 1), &lineOrigin);
                //NSLog(@"  lineOrigin %@", NSStringFromCGPoint(lineOrigin));
		
		CGPoint baselineOffset = [cell cellBaselineOffset];
                
                // The glyph positions returned from CTRunGetPositions() are relative to the line origin.
                CGRect cellFrame = CGRectMake(lineOrigin.x + positions[0].x + baselineOffset.x, lineOrigin.y + positions[0].y + baselineOffset.y, width, ascent + descent);
                
                UIGraphicsPushContext(ctx);
                [cell drawWithFrame:cellFrame inView:nil];
                UIGraphicsPopContext();
            }
        }
    }
    
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

static NSAttributedString *_transformLink(NSMutableAttributedString *source, NSDictionary *attributes, NSRange matchRange, NSRange effectiveAttributeRange, BOOL *isEditing, void *context)
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

static NSAttributedString *_transformUnderline(NSMutableAttributedString *source, NSDictionary *attributes, NSRange matchRange, NSRange effectiveAttributeRange, BOOL *isEditing, void *context)
{
    NSCharacterSet *whitespaceCharacterSet = [NSCharacterSet whitespaceCharacterSet];
    NSNumber *underlineStyle = [attributes objectForKey:OAUnderlineStyleAttributeName];
    if (!underlineStyle || ([underlineStyle unsignedIntegerValue] & OAUnderlineByWordMask) == 0)
        return nil;
    
    NSUInteger location = matchRange.location, end = NSMaxRange(matchRange);
    while (location < end) {
        NSRange remainingSearchRange = NSMakeRange(location, end - location);
        NSRange whitespaceRange = [[source string] rangeOfCharacterFromSet:whitespaceCharacterSet options:0 range:remainingSearchRange];
        if (whitespaceRange.length == 0)
            break;

        if (!*isEditing) {
            [source beginEditing];
            *isEditing = YES;
        }
        [source removeAttribute:OAUnderlineStyleAttributeName range:whitespaceRange];
        location = NSMaxRange(whitespaceRange);
    }

    // We made only attribute changes (if any at all).
    return nil;
}

static void _runDelegateDealloc(void *refCon)
{
    OATextAttachment *attachment = refCon;
    OBASSERT([attachment isKindOfClass:[OATextAttachment class]]);

    [attachment release];
}

static CGFloat _runDelegateGetAscent(void *refCon)
{
    OATextAttachment *attachment = refCon;
    OBASSERT([attachment isKindOfClass:[OATextAttachment class]]);

    id <OATextAttachmentCell> cell = attachment.attachmentCell;
    OBASSERT(cell);
    
    return cell ? MAX(0, cell.cellSize.height + [cell cellBaselineOffset].y) : 0.0;
}

static CGFloat _runDelegateGetDescent(void *refCon)
{
    OATextAttachment *attachment = refCon;
    OBASSERT([attachment isKindOfClass:[OATextAttachment class]]);

    id <OATextAttachmentCell> cell = attachment.attachmentCell;
    OBASSERT(cell);
    
    return cell ? MAX(0, -1 * [cell cellBaselineOffset].y) : 0.0;
}

static CGFloat _runDelegateGetWidth(void *refCon)
{
    OATextAttachment *attachment = refCon;
    OBASSERT([attachment isKindOfClass:[OATextAttachment class]]);
    
    id <OATextAttachmentCell> cell = attachment.attachmentCell;
    OBASSERT(cell);
    
    return cell ? cell.cellSize.width : 0.0;
}

static NSAttributedString *_transformAttachment(NSMutableAttributedString *source, NSDictionary *attributes, NSRange matchRange, NSRange effectiveAttributeRange, BOOL *isEditing, void *context)
{
    OATextAttachment *attachment = [attributes objectForKey:OAAttachmentAttributeName];
    if (!attachment)
        return nil;

    OBASSERT(matchRange.length == 1); // Terrible news if we have a single attachment that spans more than one character!
    
    CTRunDelegateCallbacks callbacks = {
        .version = kCTRunDelegateCurrentVersion,
        .dealloc = _runDelegateDealloc,
        .getAscent = _runDelegateGetAscent,
        .getDescent = _runDelegateGetDescent,
        .getWidth = _runDelegateGetWidth
    };
    
    objc_msgSend(attachment, @selector(retain)); // will be released by the callbacks.dealloc
    CTRunDelegateRef runDelegate = CTRunDelegateCreate(&callbacks, attachment);
    
    if (!*isEditing) {
        [source beginEditing];
        *isEditing = YES;
    }

    [source addAttribute:(id)kCTRunDelegateAttributeName value:(id)runDelegate range:matchRange];
    CFRelease(runDelegate);

    // We made only attribute changes
    return nil;
}

/*
 Later, we may have a callout for a delegate to extend the transformation. For now this applies some hard coded transforms to support features that CoreText doesn't have natively.

 - If a non-empty linkAttributes dictionary is passed in, any link attribute ranges will have those attributes added.
 - Any ranges that have an underline applied and have the OAUnderlineByWordMask set will have the underline attribute removed on whitespace in those ranges.
 - OAAttachmentAttributeName ranges get converted to kCTRunDelegateAttributeName with a CTRunDelegateRef value.
 
 Returns nil if no transformation is done, instead of returning [soure copy].
 */
NSAttributedString *OUICreateTransformedAttributedString(NSAttributedString *source, NSDictionary *linkAttributes)
{
    BOOL allowLinkTransform = ([linkAttributes count] > 0);
    BOOL needsTransform = NO;

    NSUInteger location = 0, length = [source length];
    while (location < length) {
        NSRange effectiveRange;
        NSDictionary *attributes = [source attributesAtIndex:location effectiveRange:&effectiveRange];
        
        if (allowLinkTransform && [attributes objectForKey:OALinkAttributeName]) {
            needsTransform = YES;
            break;
        }
        if ([attributes objectForKey:OAAttachmentAttributeName]) {
            needsTransform = YES;
            break;
        }
        
        NSNumber *underlineStyle = [attributes objectForKey:OAUnderlineStyleAttributeName];
        if (underlineStyle && ([underlineStyle unsignedIntegerValue] & OAUnderlineByWordMask)) {
            NSRange whitespaceRange = [[source string] rangeOfCharacterFromSet:[NSCharacterSet whitespaceCharacterSet] options:0 range:effectiveRange];
            if (whitespaceRange.length > 0) {
                needsTransform = YES;
                break;
            }
        }
        
        location = NSMaxRange(effectiveRange);
    }
    
    if (!needsTransform)
        return nil; // No transform needed!
    
    NSMutableAttributedString *transformed = [source mutableCopy];
    BOOL didEdit = NO;
    
    if (allowLinkTransform)
        didEdit |= [transformed mutateRanges:_transformLink matchingString:nil context:linkAttributes];
    didEdit |= [transformed mutateRanges:_transformUnderline matchingString:nil context:nil];
    didEdit |= [transformed mutateRanges:_transformAttachment matchingString:nil context:nil];
    
    NSAttributedString *immutableResult = nil;
    if (didEdit) {
        // Should only happen if we had an underline attribute with by-word set, but it already didn't cover any whitespace.
        immutableResult = [transformed copy];
    }

    [transformed release];

    return immutableResult;
}

@end

