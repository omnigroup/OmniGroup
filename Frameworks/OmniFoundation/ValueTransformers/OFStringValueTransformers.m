// Copyright 2013-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFStringValueTransformers.h"

RCS_ID("$Id$");

@implementation OFUppercaseStringTransformer

+ (Class)transformedValueClass;
{
    return [NSString class];
}

+ (BOOL)allowsReverseTransformation;
{
    return NO;
}

- (id)transformedValue:(id)value;
{
    if ([value isKindOfClass:[NSString class]]) {
        if ([value respondsToSelector:@selector(uppercaseStringWithLocale:)]) {
            return [value uppercaseStringWithLocale:[NSLocale currentLocale]];
        }
        
        // Backwards compatibility path for prior to 10.8 or iOS 6
        
        CFLocaleRef locale = CFLocaleCopyCurrent();
        CFMutableStringRef string = CFStringCreateMutableCopy(kCFAllocatorDefault, 0, (CFStringRef)value);
        CFStringUppercase(string, locale);
        
        value = [NSString stringWithString:(__bridge NSString *)string];
        
        CFRelease(locale);
        CFRelease(string);
    }
    
    return value;
}

@end

#pragma mark -

@implementation OFLowercaseStringTransformer

+ (Class)transformedValueClass;
{
    return [NSString class];
}

+ (BOOL)allowsReverseTransformation;
{
    return NO;
}

- (id)transformedValue:(id)value;
{
    if ([value isKindOfClass:[NSString class]]) {
        if ([value respondsToSelector:@selector(lowercaseStringWithLocale:)]) {
            return [value lowercaseStringWithLocale:[NSLocale currentLocale]];
        }

        // Backwards compatibility path for prior to 10.8 or iOS 6

        CFLocaleRef locale = CFLocaleCopyCurrent();
        CFMutableStringRef string = CFStringCreateMutableCopy(kCFAllocatorDefault, 0, (CFStringRef)value);
        CFStringLowercase(string, locale);
        
        value = [NSString stringWithString:(__bridge NSString *)string];
        
        CFRelease(locale);
        CFRelease(string);
    }
    
    return value;
}

@end

#pragma mark -

NSString * const OFUppercaseStringTransformerName = @"OFUppercaseStringTransformer";
NSString * const OFLowercaseStringTransformerName = @"OFLowercaseStringTransformer";
