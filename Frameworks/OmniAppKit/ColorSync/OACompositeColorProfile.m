// Copyright 2003-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OACompositeColorProfile.h>
#import <OmniAppKit/OAColorProfile.h>
#import <OmniAppKit/NSColor-ColorSyncExtensions.h>
#import <AppKit/AppKit.h>
#import <OmniAppKit/OAFeatures.h>
#import <OmniBase/assertions.h>
#import <OmniBase/rcsid.h>

RCS_ID("$Id$");

@implementation OACompositeColorProfile

- initWithProfiles:(NSArray *)someProfiles;
{
    if (!(self = [super init]))
        return nil;
    
    profiles = [someProfiles copy];
    
    return self;
}

- (void)dealloc;
{
    [profiles release];
    [super dealloc];
}

- (NSString *)description;
{
    return [profiles description];
}

#pragma mark OAColorProfile subclass

- (BOOL)_hasRGBSpace;
{
    return [[profiles objectAtIndex:0] _hasRGBSpace];
}

- (BOOL)_hasCMYKSpace;
{
    return [[profiles objectAtIndex:0] _hasCMYKSpace];
}

- (BOOL)_hasGraySpace;
{
    return [[profiles objectAtIndex:0] _hasGraySpace];
}

- (ColorSyncTransformRef)_colorWorldForOutput:(OAColorProfile *)aProfile componentSelector:(SEL)componentSelector;
{
    ColorSyncTransformRef result;
    NSUInteger profileIndex, profileCount = [profiles count];
    NSMutableArray *profileSet = [NSMutableArray arrayWithCapacity:(profileCount + 1) * 2];
    
    for (profileIndex = 0; profileIndex <= profileCount; profileIndex++) {
        OAColorProfile *profile = ( profileIndex < profileCount ) ? [profiles objectAtIndex:profileIndex] : aProfile;
        NSMutableDictionary *to = [[NSMutableDictionary alloc] initWithCapacity:3];
        NSMutableDictionary *from = [[NSMutableDictionary alloc] initWithCapacity:3];
        
        [to setObject:[profile performSelector:componentSelector] forKey:(NSString*)kColorSyncProfile];
        [to setObject:(NSString*)kColorSyncRenderingIntentUseProfileHeader forKey:(NSString*)kColorSyncRenderingIntent];
        [to setObject:(NSString*)kColorSyncTransformPCSToDevice forKey:(NSString*)kColorSyncTransformTag];
        [from setObject:[profile performSelector:componentSelector] forKey:(NSString*)kColorSyncProfile];
        [from setObject:(NSString*)kColorSyncRenderingIntentUseProfileHeader forKey:(NSString*)kColorSyncRenderingIntent];
        [from setObject:(NSString*)kColorSyncTransformDeviceToPCS forKey:(NSString*)kColorSyncTransformTag];
        [profileSet addObject:to];
        [profileSet addObject:from];
        [to release];
        [from release];
    }

    result = ColorSyncTransformCreate((CFArrayRef)profileSet, NULL);
    return (ColorSyncTransformRef)CFAutorelease(result);
}

- (ColorSyncTransformRef)_rgbConversionWorldForOutput:(OAColorProfile *)aProfile;
{
    ColorSyncTransformRef *colorWorld = [self _cachedRGBColorWorldForOutput:aProfile];

    if (!*colorWorld)  
        *colorWorld = [self _colorWorldForOutput:aProfile componentSelector:@selector(_rgbProfile)];
    return *colorWorld;
}

- (ColorSyncTransformRef)_cmykConversionWorldForOutput:(OAColorProfile *)aProfile;
{
    ColorSyncTransformRef *colorWorld = [self _cachedCMYKColorWorldForOutput:aProfile];

    if (!*colorWorld)  
        *colorWorld = [self _colorWorldForOutput:aProfile componentSelector:@selector(_cmykProfile)];
    return *colorWorld;
}

- (ColorSyncTransformRef)_grayConversionWorldForOutput:(OAColorProfile *)aProfile;
{
    ColorSyncTransformRef *colorWorld = [self _cachedGrayColorWorldForOutput:aProfile];

    if (!*colorWorld)  
        *colorWorld = [self _colorWorldForOutput:aProfile componentSelector:@selector(_grayProfile)];
    return *colorWorld;
}

#pragma mark NSCopying

- (id)copyWithZone:(NSZone *)zone;
{
    OBPRECONDITION(!isMutable); // Superclass does something funky otherwise.
    return [self retain];
}

@end
