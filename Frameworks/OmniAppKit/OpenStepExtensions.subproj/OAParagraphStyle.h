// Copyright 2003-2011 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE

#import <CoreGraphics/CGGeometry.h>

@class NSArray;

enum {
    OALeftTextAlignment		= 0,    // Visually left aligned
    OARightTextAlignment	= 1,    // Visually right aligned
    OACenterTextAlignment	= 2,    // Visually centered
    OAJustifiedTextAlignment	= 3,    // Fully-justified. The last line in a paragraph is natural-aligned.
    OANaturalTextAlignment	= 4,     // Indicates the default alignment for script
    
    OATextAlignmentMAX          = OANaturalTextAlignment
};
typedef NSUInteger OATextAlignment;

enum {
    OAWritingDirectionNatural       = -1,   // Determines direction using the Unicode Bidi Algorithm rules P2 and P3
    OAWritingDirectionLeftToRight   = 0,    // Left to right writing direction
    OAWritingDirectionRightToLeft   = 1     // Right to left writing direction
};
typedef NSInteger OAWritingDirection;

enum {
    OALeftTabStopType = 0,
    OARightTabStopType,
    OACenterTabStopType,
    OADecimalTabStopType
};
typedef NSUInteger OATextTabType;

@interface OATextTab : OFObject
{
@private
    OATextAlignment _alignment;
    CGFloat _location;
    NSDictionary *_options;
}
- (id)initWithTextAlignment:(OATextAlignment)alignment location:(CGFloat)location options:(NSDictionary *)options;
- (NSDictionary *)options;
- (id)initWithType:(OATextTabType)type location:(CGFloat)location;
- (CGFloat)location;
- (OATextTabType)tabStopType;
@end

@interface OAParagraphStyle : OFObject <NSCopying, NSMutableCopying>
{
@protected
    struct {
        CGFloat lineSpacing;
        CGFloat paragraphSpacing;
        OATextAlignment alignment;
        
        CGFloat headIndent;
        CGFloat tailIndent;
        CGFloat firstLineHeadIndent;
        
        CGFloat minimumLineHeight;
        CGFloat maximumLineHeight;
        
        OAWritingDirection baseWritingDirection;
        CGFloat lineHeightMultiple;
        CGFloat paragraphSpacingBefore;
        CGFloat defaultTabInterval;
    } _scalar;

    NSArray *_tabStops;
}

+ (OAParagraphStyle *)defaultParagraphStyle;

- initWithCTParagraphStyle:(CFTypeRef)ctStyle;

- (CGFloat)lineSpacing;
- (CGFloat)paragraphSpacing;
- (OATextAlignment)alignment;

- (CGFloat)headIndent;
- (CGFloat)tailIndent;
- (CGFloat)firstLineHeadIndent;
- (NSArray *)tabStops;

- (CGFloat)minimumLineHeight;
- (CGFloat)maximumLineHeight;

- (OAWritingDirection)baseWritingDirection;

- (CGFloat)lineHeightMultiple;
- (CGFloat)paragraphSpacingBefore;
- (CGFloat)defaultTabInterval;

- (CFTypeRef)copyCTParagraphStyle;

@end

@interface OAMutableParagraphStyle : OAParagraphStyle
- initWithParagraphStyle:(OAParagraphStyle *)original;

- (void)setLineSpacing:(CGFloat)aFloat;
- (void)setParagraphSpacing:(CGFloat)aFloat;
- (void)setAlignment:(OATextAlignment)alignment;
- (void)setFirstLineHeadIndent:(CGFloat)aFloat;
- (void)setHeadIndent:(CGFloat)aFloat;
- (void)setTailIndent:(CGFloat)aFloat;
- (void)setMinimumLineHeight:(CGFloat)aFloat;
- (void)setMaximumLineHeight:(CGFloat)aFloat;
- (void)setBaseWritingDirection:(OAWritingDirection)writingDirection;
- (void)setLineHeightMultiple:(CGFloat)aFloat;
- (void)setParagraphSpacingBefore:(CGFloat)aFloat;
- (void)setDefaultTabInterval:(CGFloat)aFloat;
- (void)setTabStops:(NSArray *)tabStops;
@end

#else // Map our symbols to the Mac version

#import <AppKit/NSParagraphStyle.h>
#define OAParagraphStyle NSParagraphStyle
#define OAMutableParagraphStyle NSMutableParagraphStyle

#define OALeftTextAlignment NSLeftTextAlignment
#define OARightTextAlignment NSRightTextAlignment
#define OACenterTextAlignment NSCenterTextAlignment
#define OAJustifiedTextAlignment NSJustifiedTextAlignment
#define OANaturalTextAlignment NSNaturalTextAlignment
#define OATextAlignment NSTextAlignment

#define OAWritingDirectionNatural NSWritingDirectionNatural
#define OAWritingDirectionLeftToRight NSWritingDirectionLeftToRight
#define OAWritingDirectionRightToLeft NSWritingDirectionRightToLeft
#define OAWritingDirection NSWritingDirection

#define OATextTab NSTextTab
#define OATextTabType NSTextTabType
#define OALeftTabStopType NSLeftTabStopType
#define OARightTabStopType NSRightTabStopType
#define OACenterTabStopType NSCenterTabStopType
#define OADecimalTabStopType NSDecimalTabStopType

#endif
