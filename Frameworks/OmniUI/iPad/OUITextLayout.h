// Copyright 2010 The Omni Group.  All rights reserved.
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

- (void)drawInContext:(CGContextRef)ctx; // Draws at (0,0) in the current coordinate system. Text draws upside down normally and with the last line that the origin.
- (void)drawFlippedInContext:(CGContextRef)ctx bounds:(CGRect)bounds; // Draws like you'd expect text to be drawn -- with the text stuck to the top of the given bounds and right side up.

@end

extern CGRect OUITextLayoutMeasureFrame(CTFrameRef frame, BOOL includeTrailingWhitespace);
extern CGPoint OUITextLayoutOrigin(CGRect typographicFrame, UIEdgeInsets textInset, // in text coordinates
                                   CGRect bounds, // view rect we want to draw in
                                   CGFloat scale); // scale factor from text to view
extern void OUITextLayoutDrawFrame(CGContextRef ctx, CTFrameRef frame, CGRect bounds, CGPoint layoutOrigin);
extern void OUITextLayoutFixupParagraphStyles(NSMutableAttributedString *content);

extern CTFontRef OUIGlobalDefaultFont(void);

extern NSAttributedString *OUICreateTransformedAttributedString(NSAttributedString *source, NSDictionary *linkAttributes);
