// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>

#import <CoreText/CTFramesetter.h>
#import <CoreText/CTFont.h>

extern const CGFloat OUITextLayoutUnlimitedSize;

typedef BOOL (^OUITextLayoutSpanBackgroundFilter)(NSRange spanRange, CGColorRef spanColor);

typedef enum {
    // All are 'negative' so that options=0 means "do the normal thing"
    OUITextLayoutDisableRunBackgrounds = (1 << 0),
    OUITextLayoutDisableGlyphs = (1 << 1),
    OUITextLayoutDisableFlipping = (1 << 2),
} OUITextLayoutDrawingOptions;

@interface OUITextLayout : OFObject
{
@private
    NSAttributedString *_attributedString;
    CTFrameRef _frame;
    CGSize _layoutSize;
    CGRect _usedSize;
}

+ (NSDictionary *)defaultLinkTextAttributes;

- initWithAttributedString:(NSAttributedString *)attributedString constraints:(CGSize)constraints;

@property(readonly,nonatomic) NSAttributedString *attributedString;
@property(readonly,nonatomic) CGSize usedSize;

- (void)drawInContext:(CGContextRef)ctx bounds:(CGRect)bounds options:(NSUInteger)options filter:(OUITextLayoutSpanBackgroundFilter)filter;

- (void)drawInContext:(CGContextRef)ctx; // Draws at (0,0) in the current coordinate system. Text draws upside down normally and with the last line that the origin.
- (void)drawFlippedInContext:(CGContextRef)ctx bounds:(CGRect)bounds; // Draws like you'd expect text to be drawn -- with the text stuck to the top of the given bounds and right side up.
- (CGFloat)topTextInsetToCenterFirstLineAtY:(CGFloat)centerFirstLineAtY forEdgeInsets:(UIEdgeInsets)edgeInsets;
- (CGFloat)firstLineAscent;

@end

extern CGRect OUITextLayoutMeasureFrame(CTFrameRef frame, BOOL includeTrailingWhitespace, BOOL widthIsConstrained);
extern CGPoint OUITextLayoutOrigin(CGRect typographicFrame, UIEdgeInsets textInset, // in text coordinates
                                   CGRect bounds, // view rect we want to draw in
                                   CGFloat scale); // scale factor from text to view
extern CGFloat OUITopTextInsetToCenterFirstLineAtY(CTFrameRef frame, CGFloat centerFirstLineAtY, UIEdgeInsets minimumInset);
extern CGFloat OUIFirstLineAscent(CTFrameRef frame);

extern void OUITextLayoutDrawFrame(CGContextRef ctx, CTFrameRef frame, CGRect bounds, CGPoint layoutOrigin);

BOOL OUITextLayoutDrawRunBackgrounds(CGContextRef ctx, CTFrameRef drawnFrame, NSAttributedString *immutableContent,
                                     CGPoint layoutOrigin, CGFloat leftEdge, CGFloat rightEdge,
                                     OUITextLayoutSpanBackgroundFilter filter);
extern void OUITextLayoutFixupParagraphStyles(NSMutableAttributedString *content);

extern CTFontRef OUIGlobalDefaultFont(void);

extern NSAttributedString *OUICreateTransformedAttributedString(NSAttributedString *source, NSDictionary *linkAttributes);

// Given attributes to apply, this makes a new set of attributes that don't have entries that shouldn't be applied to the extra newline that CoreText needs. Not really applicable outside OmniUI, so this should eventually be made private.
extern NSDictionary *OUITextLayoutCopyExtraNewlineAttributes(NSDictionary *attributes);

void OUIGetSuperSubScriptPositions(CTFontRef font, CGRect *supersub);

