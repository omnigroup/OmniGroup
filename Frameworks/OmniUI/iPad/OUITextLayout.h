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

- (void)drawInContext:(CGContextRef)ctx;

@end

extern CGRect OUITextLayoutMeasureFrame(CTFrameRef frame, BOOL includeTrailingWhitespace);
extern void OUITextLayoutFixupParagraphStyles(NSMutableAttributedString *content);

extern CTFontRef OUIGlobalDefaultFont(void);

extern NSAttributedString *OUICreateTransformedAttributedString(NSAttributedString *source, NSDictionary *linkAttributes);
