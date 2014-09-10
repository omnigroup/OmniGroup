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

+ (UIFont *)mediumSystemFontOfSize:(CGFloat)size;
{
    // TODO: Is should be possible, and is preferable, to get the system font, then apply attributes which contain UIFontWeightTrait to get the desired weight.
    // I cannot get this to work at this time; we'll revisit it later.
    
    return [UIFont fontWithName:@"HelveticaNeue-Medium" size:size];
}

+ (UIFont *)lightSystemFontOfSize:(CGFloat)size;
{
    // TODO: Is should be possible, and is preferable, to get the system font, then apply attributes which contain UIFontWeightTrait to get the desired weight.
    // I cannot get this to work at this time; we'll revisit it later.
    
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

