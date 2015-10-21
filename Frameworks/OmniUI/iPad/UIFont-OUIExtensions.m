// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
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

+ (UIFont *)mediumSystemFontOfSize:(CGFloat)size;
{
    return [UIFont systemFontOfSize:size weight:UIFontWeightMedium];
}

+ (UIFont *)lightSystemFontOfSize:(CGFloat)size;
{
    return [UIFont systemFontOfSize:size weight:UIFontWeightLight];
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

- (UIFont *)fontByAddingMonospacedNumberAttributes;
{
    UIFontDescriptor *fontDescriptor = [self.fontDescriptor fontDescriptorByAddingMonospacedNumberAttributes];
    return [UIFont fontWithDescriptor:fontDescriptor size:0];
}

- (UIFont *)fontByAddingTimeAttributes;
{
    UIFontDescriptor *fontDescriptor = [self.fontDescriptor fontDescriptorByAddingTimeAttributes];
    return [UIFont fontWithDescriptor:fontDescriptor size:0];
}

@end

