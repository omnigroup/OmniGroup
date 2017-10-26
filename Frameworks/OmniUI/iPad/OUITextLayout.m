// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUITextLayout.h>

#import <OmniFoundation/NSAttributedString-OFExtensions.h>
#import <OmniFoundation/NSMutableAttributedString-OFExtensions.h>
#import <OmniAppKit/OATextAttributes.h>
#import <OmniAppKit/OATextAttachmentCell.h>
#import <OmniAppKit/OATextStorage.h>
#import <OmniAppKit/NSAttributedString-OAExtensions.h>
#import <OmniAppKit/NSLayoutManager-OAExtensions.h>

#import <OmniQuartz/OQDrawing.h>

#include <string.h>

#import <OmniBase/OmniBase.h>

RCS_ID("$Id$");

#if 0 && defined(DEBUG)
    #define DEBUG_TEXT(format, ...) NSLog(@"TEXT: " format, ## __VA_ARGS__)
#else
    #define DEBUG_TEXT(format, ...)
#endif

@implementation OUITextLayout
{
    NSTextStorage *_textStorage;
    NSTextContainer *_textContainer;
    NSLayoutManager *_layoutManager;

    CGSize _layoutSize;
    CGSize _usedSize;
}

+ (CGFloat)defaultLineFragmentPadding;
{
    // NSTextContainer uses this by default.
    return 5;
}

+ (UIImage *)imageFromAttributedString:(NSAttributedString *)attString;
{
    // Apply superscript and other fix-ups
    NSAttributedString *transformedString = OUICreateTransformedAttributedString(attString, nil);
    if (!transformedString)
        transformedString = [attString copy];
    
    // Create an OUITextLayout
    OUITextLayout *textLayout = [[OUITextLayout alloc] initWithAttributedString:transformedString constraints:CGSizeMake(300, 300)];
    CGRect drawingBounds = (CGRect){ { 0, 0}, textLayout.usedSize };
    
    // Draw into an image context
    UIGraphicsBeginImageContextWithOptions(drawingBounds.size, NO, 0.0);
    
    [textLayout drawFlippedInContext:UIGraphicsGetCurrentContext() bounds:drawingBounds];
    
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    return image;
}

- initWithAttributedString:(NSAttributedString *)attributedString_ constraints:(CGSize)constraints;
{
    if (!(self = [self initWithAttributedString:attributedString_ constraints:constraints lineFragmentPadding:0 includeTrailingWhitespace:NO]))
        return nil;
    
    return self;
}

- initWithAttributedString:(NSAttributedString *)attributedString_ constraints:(CGSize)constraints lineFragmentPadding:(CGFloat)lineFragmentPadding includeTrailingWhitespace:(BOOL)includeTrailingWhitespace;
{
    OBPRECONDITION(attributedString_);
    
    if (!(self = [super init]))
        return nil;
    
    if (!attributedString_) {
        return nil;
    }
    
    _textStorage = [[NSTextStorage alloc] initWithAttributedString:attributedString_];

    _layoutManager = [[NSLayoutManager alloc] init];
    [_textStorage addLayoutManager:_layoutManager];
    
    _layoutSize = constraints;
    if (_layoutSize.width <= 0)
        _layoutSize.width = OUITextLayoutUnlimitedSize;
    if (_layoutSize.height <= 0)
        _layoutSize.height = OUITextLayoutUnlimitedSize;
    
    OBASSERT(includeTrailingWhitespace == NO, "Add support for includeTrailingWhitespace == YES");

    _textContainer = [[NSTextContainer alloc] initWithSize:_layoutSize];
    OBASSERT(_textContainer.lineFragmentPadding == [OUITextLayout defaultLineFragmentPadding]);
    _textContainer.lineFragmentPadding = lineFragmentPadding;
    [_layoutManager addTextContainer:_textContainer];

    DEBUG_TEXT(@"%@ textLayout using %f x %f", [attributedString_ string], _layoutSize.width, _layoutSize.height);
    
    _usedSize = CGSizeMake([_layoutManager widthOfLongestLine], [_layoutManager totalHeightUsed]);
    DEBUG_TEXT(@"%@ textLayout used size %@", [attributedString_ string], NSStringFromCGSize(_usedSize));
    
    return self;
}

- (NSString *)copyString;
{
    return [_textStorage.string copy];
}
- (NSAttributedString *)copyAttributedString;
{
    return [[NSAttributedString alloc] initWithAttributedString:_textStorage];
}

- (NSDictionary *)copyAttributesAtCharacterIndex:(NSUInteger)characterIndex effectiveRange:(NSRange *)outEffectiveRange;
{
    return [[_textStorage attributesAtIndex:characterIndex effectiveRange:outEffectiveRange] copy];
}

- (NSRange)effectiveRangeOfAttribute:(NSString *)attributeName atCharacterIndex:(NSUInteger)characterIndex;
{
    NSRange range;
    [_textStorage attribute:attributeName atIndex:characterIndex effectiveRange:&range];
    return range;
}

- (BOOL)contentsAreSameAsAttributedString:(NSAttributedString *)attributedString;
{
    return [_textStorage isEqualToAttributedString:attributedString];
}

- (void)eachAttachment:(void (^ NS_NOESCAPE)(NSRange, OATextAttachment *, BOOL *stop))applier;
{
    [_textStorage eachAttachment:applier];
}

- (CGSize)usedSize
{
    return _usedSize;
}

- (void)drawInContext:(CGContextRef)ctx bounds:(CGRect)bounds options:(NSUInteger)options;
{
    [self drawInContext:ctx bounds:bounds options:options extraBackgroundRangesAndColors:nil];
}
                                                                                                                                                                                    
// The size of the bounds only matters if flipping is specified; we don't clip.
- (void)drawInContext:(CGContextRef)ctx bounds:(CGRect)bounds options:(NSUInteger)options extraBackgroundRangesAndColors:(OUITextLayoutExtraBackgroundRangesAndColors)extraBackgroundRangesAndColors;
{
    NSUInteger characterLength = [_textStorage length];
    if (characterLength == 0)
        return;

    // Show where the origin is prior to our flip
#if 0 && defined(DEBUG_bungi)
    CGContextSetStrokeColorWithColor(ctx, [[UIColor redColor] CGColor]);
    CGContextMoveToPoint(ctx, bounds.origin.x, bounds.origin.y);
    CGContextAddLineToPoint(ctx, CGRectGetMidX(bounds), CGRectGetMidY(bounds));
    CGContextSetLineWidth(ctx, 1);
    CGContextStrokePath(ctx);
#endif
    
#if 0 && defined(DEBUG_bungi)
    CGContextSetFillColorWithColor(ctx, [[UIColor yellowColor] CGColor]);
    CGContextFillRect(ctx, bounds);
#endif
    
    BOOL shouldFlip = (options & OUITextLayoutDisableFlipping) == 0;
    BOOL shouldDrawForeground = (options & OUITextLayoutDisableGlyphs) == 0;
    BOOL shouldDrawBackground = (options & OUITextLayoutDisableRunBackgrounds) == 0;
    OBASSERT((options & ~(OUITextLayoutDisableFlipping|OUITextLayoutDisableGlyphs|OUITextLayoutDisableRunBackgrounds)) == 0);
    
    if (!shouldFlip) {
        CGContextSaveGState(ctx);
        OQFlipVerticallyInRect(ctx, bounds);
    }
    
    CGPoint currentPoint = bounds.origin;
    OBASSERT([_layoutManager.textContainers count] == 1);
    NSRange entireGlyphRange = [_layoutManager glyphRangeForTextContainer:_textContainer];
    
    if (shouldDrawBackground)
        [_layoutManager drawBackgroundForGlyphRange:entireGlyphRange atPoint:currentPoint];
    
    if (extraBackgroundRangesAndColors) {
        extraBackgroundRangesAndColors(ctx, ^(NSRange range, CGColorRef color){
            CGContextSetFillColorWithColor(ctx, color);
            NSRange glyphRange = [_layoutManager glyphRangeForCharacterRange:range actualCharacterRange:NULL];
            [_layoutManager enumerateEnclosingRectsForGlyphRange:glyphRange withinSelectedGlyphRange:glyphRange inTextContainer:_textContainer usingBlock:^(CGRect rect, BOOL *stop){
                CGRect deviceRect = CGContextConvertRectToDeviceSpace(ctx, rect);
                
                CGRect snappedDeviceRect;
                snappedDeviceRect.origin.x = floor(CGRectGetMinX(deviceRect));
                snappedDeviceRect.origin.y = floor(CGRectGetMinY(deviceRect));
                snappedDeviceRect.size.width = ceil(CGRectGetMaxX(deviceRect)) - snappedDeviceRect.origin.x;
                snappedDeviceRect.size.height = ceil(CGRectGetMaxY(deviceRect)) - snappedDeviceRect.origin.y;
                
                CGRect snappedUserRect = CGContextConvertRectToUserSpace(ctx, snappedDeviceRect);
                CGContextFillRect(ctx, CGRectIntegral(snappedUserRect));
            }];
        });
    }
    
    if (shouldDrawForeground)
        [_layoutManager drawGlyphsForGlyphRange:entireGlyphRange atPoint:currentPoint];
    
    if (!shouldFlip) {
        CGContextRestoreGState(ctx);
    }
}

- (NSLayoutManager *)layoutManager
{
    return _layoutManager;
}

- (void)drawInContext:(CGContextRef)ctx;
{
    CGRect bounds;
    bounds.origin = CGPointZero;
    bounds.size = _usedSize;
        
    [self drawInContext:ctx bounds:bounds options:OUITextLayoutDisableFlipping];
}

- (void)drawFlippedInContext:(CGContextRef)ctx bounds:(CGRect)bounds;
{
    [self drawInContext:ctx bounds:bounds options:0/*flipped, background and glyphs*/];
}

- (CGRect)firstRectForRange:(NSRange)range;
{
    NSRange glyphRange = [_layoutManager glyphRangeForCharacterRange:range actualCharacterRange:NULL];
    if (glyphRange.location == NSNotFound)
        return CGRectNull;
    
    return [_layoutManager boundingRectForGlyphRange:glyphRange inTextContainer:_textContainer];
}

// Intended for link/attachment hit testing, not for selection (since this doesn't handle ligatures/partial glyph fractions).
- (NSUInteger)hitCharacterIndexForPoint:(CGPoint)pt;
{
    if ([_layoutManager numberOfGlyphs] == 0)
        return NSNotFound;
    
    NSUInteger hitGlyph = [_layoutManager glyphIndexForPoint:pt inTextContainer:_textContainer];
    OBASSERT(hitGlyph != NSNotFound, "Documentation says the nearest glyph will be returned");

    return [_layoutManager characterIndexForGlyphAtIndex:hitGlyph];
}

/*
 Later, we may have a callout for a delegate to extend the transformation. For now this applies some hard coded transforms to support features that CoreText doesn't have natively.

 - If a non-empty linkAttributes dictionary is passed in, any link attribute ranges will have those attributes added.
 - Any ranges that have an underline applied and have the OAUnderlineByWordMask set will have the underline attribute removed on whitespace in those ranges.
 - OAAttachmentAttributeName ranges get converted to kCTRunDelegateAttributeName with a CTRunDelegateRef value.
 - Any runs with a kCTSuperscript attribute will be replaced with an attachment that draws the super(or sub)scripted text. (Note that this will interfere with cursor positioning and line breaking, so don't expect to be able to edit super/subscripted text.)
 
 Returns nil if no transformation is done, instead of returning [soure copy].
 */
NSAttributedString *OUICreateTransformedAttributedString(NSAttributedString *source, NSDictionary *linkAttributes)
{
    // <bug:///94057> (Emulate superscript/subscript with formula from Apple)
    return [source copy];
#if 0
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
        
        NSNumber *superscript = [attributes objectForKey:(id)kCTSuperscriptAttributeName];
        if (superscript && [superscript intValue]) {
            needsTransform = YES;
            break;
        }
        
        location = NSMaxRange(effectiveRange);
    }
    
    if (!needsTransform)
        return nil; // No transform needed!
    
    NSMutableAttributedString *transformed = [source mutableCopy];
    BOOL didEdit = NO;
    
    if (allowLinkTransform)
        didEdit |= [transformed mutateRanges:_transformLink matchingString:nil context:linkAttributes];
    didEdit |= [transformed mutateRanges:_transformUnderline matchingString:nil context:NULL];
    didEdit |= [transformed mutateRanges:_transformAttachment matchingString:nil context:NULL];
    didEdit |= [transformed mutateRanges:_transformAbscript matchingString:nil context:NULL];
    
    NSAttributedString *immutableResult = nil;
    if (didEdit) {
        // Should only happen if we had an underline attribute with by-word set, but it already didn't cover any whitespace.
        immutableResult = [transformed copy];
    }

    [transformed release];

    return immutableResult;
#endif
}

- (void)fitToText;
{
    _usedSize = CGSizeMake([_layoutManager widthOfLongestLine], [_layoutManager totalHeightUsed]);
    [_textContainer setSize:_usedSize];
}

@end
