// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>

#import <OmniAppKit/OATextAttachment.h>

#define OUITextLayoutUnlimitedSize (CGFLOAT_MAX)

typedef void (^OUITextLayoutExtraBackgroundRangesAndColors)(CGContextRef ctx, void (^rangeAndColor)(NSRange range, CGColorRef color));

typedef enum {
    // All are 'negative' so that options=0 means "do the normal thing"
    OUITextLayoutDisableRunBackgrounds = (1 << 0),
    OUITextLayoutDisableGlyphs = (1 << 1),
    OUITextLayoutDisableFlipping = (1 << 2),
} OUITextLayoutDrawingOptions;

@interface OUITextLayout : NSObject

+ (CGFloat)defaultLineFragmentPadding;

+ (UIImage *)imageFromAttributedString:(NSAttributedString *)attString;

- initWithAttributedString:(NSAttributedString *)attributedString constraints:(CGSize)constraints;
- initWithAttributedString:(NSAttributedString *)attributedString_ constraints:(CGSize)constraints lineFragmentPadding:(CGFloat)lineFragmentPadding includeTrailingWhitespace:(BOOL)includeTrailingWhitespace;

- (NSString *)copyString NS_RETURNS_RETAINED;
- (NSAttributedString *)copyAttributedString NS_RETURNS_RETAINED;
- (NSDictionary *)copyAttributesAtCharacterIndex:(NSUInteger)characterIndex effectiveRange:(NSRange *)outEffectiveRange NS_RETURNS_RETAINED;
- (NSRange)effectiveRangeOfAttribute:(NSString *)attributeName atCharacterIndex:(NSUInteger)characterIndex;

- (BOOL)contentsAreSameAsAttributedString:(NSAttributedString *)attributedString;
- (void)eachAttachment:(void (^ NS_NOESCAPE)(NSRange, OATextAttachment *, BOOL *stop))applier;

@property(readonly,nonatomic) CGSize usedSize;

- (void)drawInContext:(CGContextRef)ctx bounds:(CGRect)bounds options:(NSUInteger)options;
- (void)drawInContext:(CGContextRef)ctx bounds:(CGRect)bounds options:(NSUInteger)options extraBackgroundRangesAndColors:(OUITextLayoutExtraBackgroundRangesAndColors)extraBackgroundRangesAndColors;

- (void)drawInContext:(CGContextRef)ctx; // Draws at (0,0) in the current coordinate system. Text draws upside down normally and with the last line that the origin.
- (void)drawFlippedInContext:(CGContextRef)ctx bounds:(CGRect)bounds; // Draws like you'd expect text to be drawn -- with the text stuck to the top of the given bounds and right side up.
- (CGFloat)firstLineAscent;

- (CGRect)firstRectForRange:(NSRange)range;

// Intended for link/attachment hit testing, not for selection (since this doesn't handle ligatures/partial glyph fractions).
- (NSUInteger)hitCharacterIndexForPoint:(CGPoint)pt;

- (void)fitToText;

- (NSLayoutManager *)layoutManager;

@end

extern NSAttributedString *OUICreateTransformedAttributedString(NSAttributedString *source, NSDictionary *linkAttributes) NS_RETURNS_RETAINED;
