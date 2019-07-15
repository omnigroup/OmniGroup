// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/NSPasteboard-OAExtensions.h>

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

RCS_ID("$Id$")

@implementation NSPasteboard (OAExtensions)

- (NSParagraphStyle *)paragraphStyleForType:(NSString *)type;
{
    NSAttributedString *attributedString = [[NSAttributedString alloc] initWithRTF:[self dataForType:type] documentAttributes:NULL];
    if ([attributedString length] == 0)
        return nil;
    return [attributedString attribute:NSParagraphStyleAttributeName atIndex:0 effectiveRange:NULL];
}

- (BOOL)setParagraphStyle:(NSParagraphStyle *)paragraphStyle forType:(NSString *)type;
{
    if (paragraphStyle == nil)
        return NO;
    NSDictionary *attributes = [NSDictionary dictionaryWithObject:paragraphStyle forKey:NSParagraphStyleAttributeName];
    NSMutableAttributedString *attributedString = [[NSMutableAttributedString alloc] initWithString:@" " attributes:attributes];
    return [self setData:[attributedString RTFFromRange:NSMakeRange(0,[attributedString length]) documentAttributes:@{}] forType:type];
}

- (NSString *)firstAvailableTypeFromSet:(NSSet <NSString *> *)types;
{
    for (NSString *type in self.types) {
        if ([types containsObject:type]) {
            return type;
        }
    }
    return nil;
}

@end

static NSArray <NSString *> *_replaceType(NSArray <NSString *> *types, NSString *oldType, NSString *newType)
{
    NSUInteger oldTypeIndex = [types indexOfObject:oldType];
    if (oldTypeIndex == NSNotFound) {
        return types;
    }

    NSMutableArray *updatedTypes = [types mutableCopy];

    // The old type can be in the array multiple times, if we are concatenating types from different sources together.
    while (oldTypeIndex != NSNotFound) {
        [updatedTypes replaceObjectAtIndex:oldTypeIndex withObject:newType];
        oldTypeIndex = [updatedTypes indexOfObject:oldType];
    }

    return updatedTypes;
}

// <bug:///131680> / Radar 27531947 — If we tell the system, via -validRequestorForSendType:returnType: that we handle the newer UTI-based types, it will ask us to write the *older* types in -writeSelectionToPasteboard:types:. The list of types is non-exhaustive here and may need to be extended as callers of this care about them.

NSArray <NSString *> *OAFixRequestedPasteboardTypes(NSArray <NSString *> *types)
{
    // This function is specifically for avoiding the deprecated types.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

    types = _replaceType(types, NSStringPboardType, NSPasteboardTypeString);
    types = _replaceType(types, NSRTFPboardType, NSPasteboardTypeRTF);
    types = _replaceType(types, NSRTFDPboardType, NSPasteboardTypeRTFD);

    // We should end up with only UTI-based types in the array.
#ifdef OMNI_ASSERTIONS_ON
    static dispatch_once_t onceToken;
    static NSCharacterSet *NonUTICharacterSet;

    dispatch_once(&onceToken, ^{
        NSMutableCharacterSet *utiCharacterSet = [NSMutableCharacterSet characterSetWithCharactersInString:@"-"];
        [utiCharacterSet addCharactersInRange:NSMakeRange('a', 26)];
        [utiCharacterSet addCharactersInRange:NSMakeRange('A', 26)];
        [utiCharacterSet addCharactersInRange:NSMakeRange('0', 10)];
        NonUTICharacterSet = [utiCharacterSet invertedSet];
    });
    for (NSString *type in types) {
        NSArray *components = [type componentsSeparatedByString:@"."];
        for (NSString *component in components) {
            OBASSERT([component length] > 0);
            OBASSERT([component rangeOfCharacterFromSet:NonUTICharacterSet].location == NSNotFound, "type is \"%@\"", type);
        }
    }
#endif

    return types;
#pragma clang diagnostic pop
}
