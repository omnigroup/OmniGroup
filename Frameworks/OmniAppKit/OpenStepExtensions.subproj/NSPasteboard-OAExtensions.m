// Copyright 1997-2016 Omni Development, Inc. All rights reserved.
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

@end

static NSArray <NSString *> *_replaceType(NSArray <NSString *> *types, NSString *oldType, NSString *newType)
{
    NSUInteger oldTypeIndex = [types indexOfObject:oldType];
    if (oldTypeIndex == NSNotFound) {
        return types;
    }

    NSMutableArray *updatedTypes = [types mutableCopy];
    [updatedTypes removeObjectAtIndex:oldTypeIndex];

    // Might already contain the new type
    if ([types indexOfObject:newType] == NSNotFound) {
        // Ordering doesn't matter in any calls as of the time of writing, but we have the info, so preserve the precedence of the remaining type.
        [updatedTypes insertObject:newType atIndex:oldTypeIndex];
    }

    return updatedTypes;
}

// <bug:///131680> / Radar 27531947 — If we tell the system, via -validRequestorForSendType:returnType: that we handle the newer UTI-based types, it will ask us to write the *older* types in -writeSelectionToPasteboard:types:. The list of types is non-exhaustive here and may need to be extended as callers of this care about them.

NSArray <NSString *> *OAFixRequestedPasteboardTypes(NSArray <NSString *> *types)
{
    types = _replaceType(types, NSStringPboardType, NSPasteboardTypeString);
    types = _replaceType(types, NSRTFPboardType, NSPasteboardTypeRTF);

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
            OBASSERT([component rangeOfCharacterFromSet:NonUTICharacterSet].location == NSNotFound);
        }
    }
#endif

    return types;
}
