// Copyright 2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

RCS_ID("$Id$")

#import <OmniAppKit/OAColorSpaceManager.h>

@implementation OAColorSpaceHelper
@end

// Looked into using [colorSpace localizedName] as the identifier.
// There are multiple specs for icc profile data.  The one Apple is using is an older spec that does not have localized descriptions, which explains why 'localizedString' is the same no matter which language preference is set.  The newer spec only has localized descriptions, which may explain why there is no 'nonLocalizedName'.  Also, localizedName could be nil.
// One oddity, the icc desc for my monitor is 'Display', but the localizedName is 'PN-K321'
// The newer spec also has a profileID, which is an md5 of the profile data.  Seems like md5 or something similar is the intended way to compare specs.

@implementation OAColorSpaceManager

- (id)init;
{
    if (self = [super init]) {
        self.colorSpaceList = [NSMutableArray array];
    }
    
    return self;
}

- (void)loadPropertyListRepresentations:(NSArray *)array;
{
    [self.colorSpaceList removeAllObjects];
    for(NSDictionary *dict in array) {
        NSString *sha1 = [dict objectForKey:@"space"];
        NSData *data = [dict objectForKey:@"data"];
        if (sha1 && data) {
            NSColorSpace *colorSpace = [[NSColorSpace alloc] initWithICCProfileData:data];
            if (colorSpace) {
                OAColorSpaceHelper *helper = [[OAColorSpaceHelper alloc] init];
                helper.sha1 = sha1;
                helper.colorSpace = colorSpace;
                [self.colorSpaceList addObject:helper];
            }
        }
    }
}

- (NSArray *)propertyListRepresentations;
{
    NSMutableArray *array = [NSMutableArray array];
    for(OAColorSpaceHelper *helper in self.colorSpaceList) {
        NSMutableDictionary *dict = [NSMutableDictionary dictionary];
        [dict setObject:helper.sha1 forKey:@"space"];
        [dict setObject:[helper.colorSpace ICCProfileData] forKey:@"data"];
        [array addObject:dict];
    }
    return array;
}

+ (NSString *)nameForColorSpace:(NSColorSpace *)colorSpace;
{
    if ([colorSpace isEqual:[NSColorSpace deviceGrayColorSpace]])
        return @"dg";
    if ([colorSpace isEqual:[NSColorSpace genericGamma22GrayColorSpace]])
        return @"gg22";
    if ([colorSpace isEqual:[NSColorSpace deviceRGBColorSpace]])
        return @"drgb";
    if ([colorSpace isEqual:[NSColorSpace adobeRGB1998ColorSpace]])
        return @"argb";
    if ([colorSpace isEqual:[NSColorSpace sRGBColorSpace]])
        return @"srgb";
    if ([colorSpace isEqual:[NSColorSpace deviceCMYKColorSpace]])
        return @"dcmyk";
    
    // Don't really need these as generic colors are written without the colorspace name
    if ([colorSpace isEqual:[NSColorSpace genericGrayColorSpace]])
        return @"gg";
    if ([colorSpace isEqual:[NSColorSpace genericCMYKColorSpace]])
        return @"gcmyk";
    if ([colorSpace isEqual:[NSColorSpace genericRGBColorSpace]])
        return @"grgb";

    return nil;
}

- (NSString *)nameForColorSpace:(NSColorSpace *)colorSpace;
{
    NSString *name = [[self class] nameForColorSpace:colorSpace];
    
    if (name)
        return name;
    
    for(OAColorSpaceHelper *helper in self.colorSpaceList) {
        if (helper.colorSpace == colorSpace)
            return helper.sha1;
    }
    
    OAColorSpaceHelper *helper = [OAColorSpaceHelper new];
    helper.colorSpace = colorSpace;
    helper.sha1 = [[[colorSpace ICCProfileData] sha1Signature] unadornedLowercaseHexString];
    [self.colorSpaceList addObject:helper];
    return helper.sha1;
}

+ (BOOL)isColorSpaceGeneric:(NSColorSpace *)colorSpace;
{
    return ([colorSpace isEqual:[NSColorSpace genericRGBColorSpace]] ||
            [colorSpace isEqual:[NSColorSpace genericGrayColorSpace]] ||
            [colorSpace isEqual:[NSColorSpace genericCMYKColorSpace]]);
}


+ (NSColorSpace *)colorSpaceForName:(NSString *)string;
{
    static NSMutableDictionary *defaultSpaces = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        defaultSpaces = [[NSMutableDictionary alloc] init];
        [defaultSpaces setObject:[NSColorSpace deviceGrayColorSpace]            forKey:@"dg"];
        [defaultSpaces setObject:[NSColorSpace genericGamma22GrayColorSpace]    forKey:@"gg22"];
        [defaultSpaces setObject:[NSColorSpace deviceCMYKColorSpace]            forKey:@"dcmyk"];
        [defaultSpaces setObject:[NSColorSpace deviceRGBColorSpace]             forKey:@"drgb"];
        [defaultSpaces setObject:[NSColorSpace adobeRGB1998ColorSpace]          forKey:@"argb"];
        [defaultSpaces setObject:[NSColorSpace sRGBColorSpace]                  forKey:@"srgb"];
        [defaultSpaces setObject:[NSColorSpace genericGrayColorSpace]           forKey:@"gg"];
        [defaultSpaces setObject:[NSColorSpace genericRGBColorSpace]            forKey:@"grgb"];
        [defaultSpaces setObject:[NSColorSpace genericCMYKColorSpace]           forKey:@"gcmyk"];
        // Could also check all known colorspaces for a localizedName that matches
    });

    return [defaultSpaces objectForKey:string];
}

- (NSColorSpace *)colorSpaceForName:(NSString *)name;
{
    NSColorSpace *space = [[self class] colorSpaceForName:name];
    if (space)
        return space;
    // TODO: If this list ends up getting large, consider merging it with the class 'defaultSpaces' dictionary.
    // The expectation is that this will be short/empty for normal usage.
    for (OAColorSpaceHelper *helper in self.colorSpaceList) {
        if ([helper.sha1 isEqualToString:name])
            return helper.colorSpace;
    }
    return nil;
}

@end
