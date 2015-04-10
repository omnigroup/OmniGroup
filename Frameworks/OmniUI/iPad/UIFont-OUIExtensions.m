// Copyright 2010-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/UIFont-OUIExtensions.h>
#import <OmniUI/UIFontDescriptor-OUIExtensions.h>

#import <CoreText/CoreText.h>

RCS_ID("$Id$");

@implementation UIFont (OUIExtensions)

// N.B. These were empirically determined; they may not be stable across OS releases.
static const CGFloat OUIFontMediumWeight = 0.3;
static const CGFloat OUIFontLightWeight = -0.3;

+ (UIFont *)OUI_systemFontOfSize:(CGFloat)size weight:(CGFloat)weight;
{
    // UIKit has private convenience methods which are inaccessible to us:
    //
    //    + (id) _ultraLightSystemFontOfSize:(float)arg1; (0x2c4a8bb9)
    //    + (id) _lightSystemFontOfSize:(float)arg1; (0x2c4a8a8d)
    //    + (id) _thinSystemFontOfSize:(float)arg1; (0x2c4a8961)
    //
    // So instead we do this by looking up the font with the weight we determined empirically, and falling back to the non-interface variant at runtime if necessary.
    
    static NSMutableDictionary *fontCache = nil;
    if (fontCache == nil) {
        fontCache = [[NSMutableDictionary alloc] init];
    }
    
    NSString *cacheKey = [NSString stringWithFormat:@"size=%.2f; weight=%.2f", size, weight];
    UIFont *cachedResult = fontCache[cacheKey];
    if (cachedResult != nil) {
        return cachedResult;
    }

    // To get the screen-optimized font for this weight, grab the system font, then mutate the traits to have the weight that we'd like.
    
    UIFont *systemFont = [UIFont systemFontOfSize:size];
    UIFontDescriptor *systemFontDescriptor = [systemFont fontDescriptor];
    NSMutableDictionary *traitsDictionary = [[systemFontDescriptor objectForKey:UIFontDescriptorTraitsAttribute] mutableCopy];
    
    if (traitsDictionary == nil) {
        traitsDictionary = [NSMutableDictionary dictionary];
    }
    
    traitsDictionary[UIFontWeightTrait] = @(weight);
    
    NSDictionary *fontAttributes = @{
        UIFontDescriptorFamilyAttribute: systemFont.familyName,
        UIFontDescriptorTraitsAttribute: traitsDictionary,
    };
    
    UIFontDescriptor *weightedFontDescriptor = [UIFontDescriptor fontDescriptorWithFontAttributes:fontAttributes];
    UIFont *weightedSystemFont = [UIFont fontWithDescriptor:weightedFontDescriptor size:size];
    
    if (weightedSystemFont != nil) {
        fontCache[cacheKey] = weightedSystemFont;
    }
    
    OBPOSTCONDITION(weightedSystemFont != nil);
    return weightedSystemFont;
}

+ (UIFont *)mediumSystemFontOfSize:(CGFloat)size;
{
    UIFont *mediumSystemFont = [self OUI_systemFontOfSize:size weight:OUIFontMediumWeight];
    if (mediumSystemFont != nil) {
        return mediumSystemFont;
    }
    
    OBASSERT_NOT_REACHED("Expected non-nil result from +OUI_systemFontOfSize:weight:]");
    return [UIFont fontWithName:@"HelveticaNeue-Medium" size:size];
}

+ (UIFont *)lightSystemFontOfSize:(CGFloat)size;
{
    UIFont *lightSystemFont = [self OUI_systemFontOfSize:size weight:OUIFontLightWeight];
    if (lightSystemFont != nil) {
        return lightSystemFont;
    }
    
    OBASSERT_NOT_REACHED("Expected non-nil result from +OUI_systemFontOfSize:weight:]");
    return [UIFont fontWithName:@"HelveticaNeue-Light" size:size];
}

+ (UIFont *)preferredItalicFontForTextStyle:(NSString *)style;
{
    UIFontDescriptor *descriptor = [[UIFont preferredFontForTextStyle:style] fontDescriptor];
    descriptor = [descriptor fontDescriptorWithSymbolicTraits:UIFontDescriptorTraitItalic];
    UIFont *result = [UIFont fontWithDescriptor:descriptor size:0.0];
    
    return result;
}

+ (UIFont *)preferredBoldFontForTextStyle:(NSString *)style;
{
    UIFontDescriptor *descriptor = [[UIFont preferredFontForTextStyle:style] fontDescriptor];
    descriptor = [descriptor fontDescriptorWithSymbolicTraits:UIFontDescriptorTraitBold];
    UIFont *result = [UIFont fontWithDescriptor:descriptor size:0.0];
    
    return result;
}

- (UIFont *)fontByAddingProportionalNumberAttributes;
{
    UIFontDescriptor *fontDescriptor = [self.fontDescriptor fontDescriptorByAddingProportionalNumberAttributes];
    return [UIFont fontWithDescriptor:fontDescriptor size:0];
}

- (UIFont *)fontByAddingTimeAttributes;
{
    UIFontDescriptor *fontDescriptor = [self.fontDescriptor fontDescriptorByAddingTimeAttributes];
    return [UIFont fontWithDescriptor:fontDescriptor size:0];
}

@end

