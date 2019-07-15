// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <UIKit/NSTextStorage.h>
#import <OmniUI/NSTextStorage-OUIExtensions.h>

NS_ASSUME_NONNULL_BEGIN

extern NSDictionary *OUICopyScaledTextAttributes(NSDictionary *textAttributes, CGFloat scale) NS_RETURNS_RETAINED;

@interface OUIScalingTextStorage : NSTextStorage

+ (NSMutableAttributedString *)copyAttributedStringByScalingAttributedString:(NSAttributedString *)attributedString byScale:(CGFloat)scale;

- initWithUnderlyingTextStorage:(NSTextStorage *)textStorage scale:(CGFloat)scale;

@property(nonatomic,assign) CGFloat scale;

@end

@interface NSAttributedString (OUIScalingTextStorageExtensions)
+ (NSAttributedString *)newScaledAttributedStringWithString:(NSString *)string attributes:(NSDictionary *)attributes scale:(CGFloat)scale;
@end

NS_ASSUME_NONNULL_END
