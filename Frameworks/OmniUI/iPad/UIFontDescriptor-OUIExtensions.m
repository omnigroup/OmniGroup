// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniUI/UIFontDescriptor-OUIExtensions.h>
#import <CoreText/CoreText.h>

@implementation UIFontDescriptor (OUIExtensions)

- (UIFontDescriptor *)fontDescriptorByAddingProportionalNumberAttributes;
{
    NSArray *fontFeatureSettings = @[
        @{
            UIFontFeatureTypeIdentifierKey: @(kNumberSpacingType),
            UIFontFeatureSelectorIdentifierKey: @(kProportionalNumbersSelector),
        },
    ];

    NSDictionary *attributes = @{
        UIFontDescriptorFeatureSettingsAttribute: fontFeatureSettings
    };
    
   return [self fontDescriptorByAddingAttributes:attributes];
}

- (UIFontDescriptor *)fontDescriptorByAddingMonospacedNumberAttributes
{
    NSArray *fontFeatureSettings = @[
        @{
            UIFontFeatureTypeIdentifierKey: @(kNumberSpacingType),
            UIFontFeatureSelectorIdentifierKey: @(kMonospacedNumbersSelector),
        },
    ];
    
    NSDictionary *attributes = @{
        UIFontDescriptorFeatureSettingsAttribute: fontFeatureSettings
    };
    
    return [self fontDescriptorByAddingAttributes:attributes];
}

- (UIFontDescriptor *)fontDescriptorByAddingTimeAttributes;
{
    NSArray *fontFeatureSettings = @[
        @{
            UIFontFeatureTypeIdentifierKey: @(kNumberSpacingType),
            UIFontFeatureSelectorIdentifierKey: @(kProportionalNumbersSelector),
        },
        @{
            UIFontFeatureTypeIdentifierKey: @(kCharacterAlternativesType),
            UIFontFeatureSelectorIdentifierKey: @(1),
        },
    ];

    NSDictionary *attributes = @{
        UIFontDescriptorFeatureSettingsAttribute: fontFeatureSettings
    };
    
    return [self fontDescriptorByAddingAttributes:attributes];
}

@end
