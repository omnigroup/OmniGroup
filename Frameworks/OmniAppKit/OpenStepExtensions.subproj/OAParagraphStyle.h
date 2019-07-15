// Copyright 2003-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Availability.h>

#if OMNI_BUILDING_FOR_IOS
    #import <UIKit/NSParagraphStyle.h>
#elif OMNI_BUILDING_FOR_MAC
    #import <AppKit/NSParagraphStyle.h>
#endif

#if OMNI_BUILDING_FOR_IOS || OMNI_BUILDING_FOR_MAC
    // Map names to the built-in types.
    #define OATextTabType NSTextTabType

    #define OATextAlignment NSTextAlignment
    #define OATextAlignmentLeft NSTextAlignmentLeft
    #define OATextAlignmentCenter NSTextAlignmentCenter
    #define OATextAlignmentRight NSTextAlignmentRight
    #define OATextAlignmentJustified NSTextAlignmentJustified
    #define OATextAlignmentNatural NSTextAlignmentNatural

    #define OAWritingDirection NSWritingDirection
    #define OAWritingDirectionNatural NSWritingDirectionNatural
    #define OAWritingDirectionLeftToRight NSWritingDirectionLeftToRight
    #define OAWritingDirectionRightToLeft NSWritingDirectionRightToLeft

    #define OALineBreakByWordWrapping OALineBreakByWordWrapping
    #define OALineBreakByCharWrapping OALineBreakByCharWrapping
    #define OALineBreakByClipping OALineBreakByClipping
    #define OALineBreakByTruncatingHead OALineBreakByTruncatingHead
    #define OALineBreakByTruncatingTail OALineBreakByTruncatingTail
    #define OALineBreakByTruncatingMiddle OALineBreakByTruncatingMiddle

    #define OAParagraphStyle NSParagraphStyle
    #define OAMutableParagraphStyle NSMutableParagraphStyle

    #define OATextTab NSTextTab
    #define OALeftTabStopType NSLeftTabStopType
    #define OARightTabStopType NSRightTabStopType
    #define OACenterTabStopType NSCenterTabStopType
    #define OADecimalTabStopType NSDecimalTabStopType

#else

// Define our own

@import OmniFoundation;

@class NSArray;

typedef NS_ENUM(NSUInteger, OATextAlignment) {
    OATextAlignmentLeft      = 0,
    OATextAlignmentCenter    = 1,
    OATextAlignmentRight     = 2,
    OATextAlignmentJustified = 3,
    OATextAlignmentNatural   = 4
};

typedef NS_ENUM(NSInteger, OAWritingDirection) {
    OAWritingDirectionNatural       = -1,
    OAWritingDirectionLeftToRight   = 0,
    OAWritingDirectionRightToLeft   = 1
};

enum {
    OALeftTabStopType = 0,
    OARightTabStopType,
    OACenterTabStopType,
    OADecimalTabStopType
};
typedef NSUInteger OATextTabType;

typedef NS_ENUM(NSUInteger, OALineBreakMode) {
    OALineBreakByWordWrapping = 0,
    OALineBreakByCharWrapping,
    OALineBreakByClipping,
    OALineBreakByTruncatingHead,
    OALineBreakByTruncatingTail,
    OALineBreakByTruncatingMiddle,
};

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
- (OATextAlignment)alignment;
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

        OALineBreakMode lineBreakMode;
    } _scalar;

    NSArray *_tabStops;
}

+ (OAParagraphStyle *)defaultParagraphStyle;

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

- (OALineBreakMode)lineBreakMode;

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


#endif
