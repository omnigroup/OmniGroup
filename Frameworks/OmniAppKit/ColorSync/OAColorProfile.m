// Copyright 2002-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OAColorProfile.h"

#import "NSColor-ColorSyncExtensions.h"
#import <Cocoa/Cocoa.h>
#import <OmniBase/rcsid.h>
#import <OmniBase/OBUtilities.h>
#import <OmniFoundation/OmniFoundation.h>
#import <OmniBase/assertions.h>
#import <OmniAppKit/OAFeatures.h>
#import "OAColorProfile-Deprecated.h"

RCS_ID("$Id$");

@interface OAColorProfile (Private)
+ (void)_deviceNotification:(NSNotification *)notification;
- initDefaultDocumentProfile;
- initDefaultProofProfile;
- initDefaultDisplayProfile;

- (NSString *)_getProfileName:(void *)aProfile;

- (void *)_anyProfile;
- (void)_updateConversionCacheForOutput:(OAColorProfile *)outputProfile;
#if OA_USE_COLOR_MANAGER
- (NSData *)_dataForRawProfile:(CMProfileRef)rawProfile;
- (BOOL)_addProfile:(CMProfileRef)cmProfile toPropertyList:(NSMutableDictionary *)dict keyStem:(NSString *)spaceName;
#endif
- (void)_profileLoadError:(int)errorCode defaultColorSpace:(NSColorSpace *)colorSpace;

@end

NSString * const OADefaultDocumentColorProfileDidChangeNotification = @"OADefaultDocumentColorProfileDidChangeNotification";
NSString * const OAColorProofingDevicesDidChangeNotification = @"OAColorProofingDevicesDidChangeNotification";

@implementation OAColorProfile

#if OA_USE_COLOR_MANAGER
static BOOL resetProfileLists = YES;
#endif
static NSMutableDictionary *rgbProfileDictionary = nil;
static NSMutableDictionary *cmykProfileDictionary = nil;
static NSMutableDictionary *grayProfileDictionary = nil;
#if OA_USE_COLOR_MANAGER
static BOOL resetDeviceList = YES;
#endif
static NSMutableDictionary *deviceProfileDictionary = nil;
static NSMutableDictionary *deviceNameDictionary = nil;
static OAColorProfile *currentColorProfile = nil;
static NSView *focusedViewForCurrentColorProfile = nil;

#if OA_USE_COLOR_MANAGER
static OAColorProfile *lastInProfile = nil;
static OAColorProfile *lastOutProfile = nil;
static CMWorldRef rgbColorWorld = NULL;
static CMWorldRef cmykColorWorld = NULL;
static CMWorldRef grayColorWorld = NULL;
#endif

+ (void)initialize;
{
// The notification isn't available on 10.1
#ifdef kCMDeviceRegisteredNotification
    [[NSDistributedNotificationCenter defaultCenter] addObserver:self selector:@selector(_deviceNotification:) name:(NSString *)kCMDeviceRegisteredNotification object:nil];
    [[NSDistributedNotificationCenter defaultCenter] addObserver:self selector:@selector(_deviceNotification:) name:(NSString *)kCMDeviceUnregisteredNotification object:nil];
    [[NSDistributedNotificationCenter defaultCenter] addObserver:self selector:@selector(_deviceNotification:) name:(NSString *)kCMDefaultDeviceProfileNotification object:nil];
    [[NSDistributedNotificationCenter defaultCenter] addObserver:self selector:@selector(_deviceNotification:) name:(NSString *)kCMDeviceProfilesNotification object:nil];
#endif
}
        
+ (OAColorProfile *)defaultDocumentProfile;
{
    static OAColorProfile *colorProfile = nil;

    if (!colorProfile)
        colorProfile = [[self alloc] initDefaultDocumentProfile];
    return colorProfile;
}

+ (OAColorProfile *)defaultProofProfile;
{
    static OAColorProfile *colorProfile = nil;

    if (!colorProfile)
        colorProfile = [[self alloc] initDefaultProofProfile];
    return colorProfile;
}

+ (OAColorProfile *)defaultDisplayProfile;
{
    static OAColorProfile *colorProfile = nil;

    if (!colorProfile)
        colorProfile = [[self alloc] initDefaultDisplayProfile];
    return colorProfile;
}

+ (OAColorProfile *)workingCMYKProfile;
{
#if OA_USE_COLOR_MANAGER
    OAColorProfile *result = [[self alloc] init];
    
    result->cmykProfile = [[self defaultDocumentProfile] _cmykProfile];
    CMCloneProfileRef((CMProfileRef)result->cmykProfile);
    return [result autorelease];
#else
    OBFinishPorting;
#endif
}

+ (OAColorProfile *)currentProfile;
{
    if (currentColorProfile != nil) {
        if ([NSView focusView] == focusedViewForCurrentColorProfile)
            return currentColorProfile;
        else
            currentColorProfile = nil;
    }
    return nil;
}

#if OA_USE_COLOR_MANAGER
static OSErr deviceListIterator(const CMDeviceInfo *deviceInfo, const NCMDeviceProfileInfo *profileInfo, void *refCon)
{
    CMProfileRef cmProfile;
    CMAppleProfileHeader header;
    OAColorProfile *profile;
    CMError err;
    NSString *deviceName, *profileName;
    
    if (resetDeviceList) {
        [deviceProfileDictionary release];
        [deviceNameDictionary release];
        deviceProfileDictionary = [[NSMutableDictionary alloc] init];
        deviceNameDictionary = [[NSMutableDictionary alloc] init];
        resetDeviceList = NO;
    }
    
    if (deviceInfo->deviceClass != cmPrinterDeviceClass && deviceInfo->deviceClass != cmProofDeviceClass)
        return 0;
    
    err = CMOpenProfile(&cmProfile, &profileInfo->profileLoc);
    if (err != noErr)
        return 0;
    
    err = CMGetProfileHeader(cmProfile, &header);
    if (err != noErr) {
        CMCloseProfile(cmProfile);
        return 0;
    }
    
    profile = [[OAColorProfile alloc] init];
    switch(header.cm2.dataColorSpace) {
        case cmRGBData:
            profile->rgbProfile = cmProfile;
            break;
        case cmCMYKData:
            profile->cmykProfile = cmProfile;
            break;
        case cmGrayData:
            profile->grayProfile = cmProfile;
            break;
        default:
            CMCloseProfile(cmProfile);
            [profile release];
            return 0;
    }
    
    if (deviceInfo->deviceName) {
        NSDictionary *nameDictionary = (NSDictionary *)*(deviceInfo->deviceName);
        NSArray *languages = [NSBundle preferredLocalizationsFromArray:[nameDictionary allKeys]];
        
        if ([languages count])
            deviceName = [nameDictionary objectForKey:[languages objectAtIndex:0]];
        else if ([nameDictionary count])
            deviceName = [[nameDictionary allValues] lastObject]; // any random language, if none match
        else
            deviceName = nil;
    } else
        deviceName = nil;
    
    profileName = [profile _getProfileName:cmProfile];
    if (deviceName != nil) {
        deviceName = [[deviceName componentsSeparatedByString:@"_"] componentsJoinedByString:@" "];
        if (![deviceName isEqualToString:profileName])
            profileName = [NSString stringWithFormat:@"%@: %@", deviceName, profileName];
    }    
    [deviceProfileDictionary setObject:profile forKey:profileName];
    if (deviceName)
        [deviceNameDictionary setObject:profile forKey:deviceName];
    [profile release];
    return 0;
}
#endif

+ (NSArray *)proofingDeviceProfileNames;
{
#if OA_USE_COLOR_MANAGER
    static UInt32 seed = 0;
    
    resetDeviceList = YES;
    CMIterateDeviceProfiles(deviceListIterator, &seed, NULL, cmIterateCurrentDeviceProfiles, NULL);
    return [deviceProfileDictionary allKeys];
#else
    OBFinishPorting;
#endif
}

+ (OAColorProfile *)proofProfileForDeviceProfileName:(NSString *)deviceProfileName;
{
    return [[[deviceProfileDictionary objectForKey:deviceProfileName] copy] autorelease];
}

+ (OAColorProfile *)proofProfileForPrintInfo:(NSPrintInfo *)printInfo;
{
    NSPrinter *printer = [printInfo printer];
    OAColorProfile *result;
    
    if (!printer)
        return [self defaultProofProfile];

    result = [[[deviceNameDictionary objectForKey:[printer name]] copy] autorelease];
    if (!result)
        result = [self defaultProofProfile];
    return result;
}

#if OA_USE_COLOR_MANAGER
static OSErr nameListIterator(CMProfileIterateData *iterateData, void *refCon)
{
    if (resetProfileLists) {
        [rgbProfileDictionary release];
        [cmykProfileDictionary release];
        [grayProfileDictionary release];
        rgbProfileDictionary = [[NSMutableDictionary alloc] init];
        cmykProfileDictionary = [[NSMutableDictionary alloc] init];
        grayProfileDictionary = [[NSMutableDictionary alloc] init];
        resetProfileLists = NO;
    }
       
    if (iterateData->uniCodeNameCount <= 1) // null terminated
        return cmProfileError;
    
    NSString *name = [NSString stringWithCharacters:iterateData->uniCodeName length:iterateData->uniCodeNameCount - 1]; // -1 because iterateData includes null on end

    CMProfileRef cmProfile = NULL;
    CMError err = CMOpenProfile((CMProfileRef *)&cmProfile, &iterateData->location);
    if (err != noErr) {
        NSLog(@"CMOpenProfile() for '%@' returns %ld", name, (long)err);
        return err;
    }
    
    OAColorProfile *profile = [[OAColorProfile alloc] init];
    
    // NSLog(@"Profile name %@ (v %08x) = %p", name, iterateData->dataVersion, cmProfile);
    switch(iterateData->header.dataColorSpace) {
        case cmRGBData:
            profile->rgbProfile = cmProfile;
            [rgbProfileDictionary setObject:profile forKey:name];
            break;
        case cmCMYKData:
            profile->cmykProfile = cmProfile;
            [cmykProfileDictionary setObject:profile forKey:name];
            break;
        case cmGrayData:
            profile->grayProfile = cmProfile;
            [grayProfileDictionary setObject:profile forKey:name];
            break;
        default:
            CMCloseProfile(cmProfile);
            break;
    }
    [profile release];
    return 0;
}
#endif

+ (void)_iterateAvailableProfiles;
{
#if OA_USE_COLOR_MANAGER
    static UInt32 seed = 0;
    
    resetProfileLists = YES;
    CMIterateColorSyncFolder (nameListIterator, &seed, NULL, NULL);
#else
    OBFinishPorting;
#endif
}

+ (NSArray *)rgbProfileNames;
{
    [self _iterateAvailableProfiles];
    return [rgbProfileDictionary allKeys];
}

+ (NSArray *)cmykProfileNames;
{
    [self _iterateAvailableProfiles];
    return [cmykProfileDictionary allKeys];
}

+ (NSArray *)grayProfileNames;
{
    [self _iterateAvailableProfiles];
    return [grayProfileDictionary allKeys];
}

+ (OAColorProfile *)colorProfileWithRGBNamed:(NSString *)rgbName cmykNamed:(NSString *)cmykName grayNamed:(NSString *)grayName;
{
#if OA_USE_COLOR_MANAGER
    OAColorProfile *profile = [[self alloc] init];
    OAColorProfile *match;

    [self _iterateAvailableProfiles];
    
    if (rgbName) {
        match = [rgbProfileDictionary objectForKey:rgbName];
        if (match) {
            profile->rgbProfile = match->rgbProfile;
            CMCloneProfileRef((CMProfileRef)profile->rgbProfile);
        } else {
            NSLog(@"Warning: can't find profile \"%@\", using default RGB profile", rgbName);
            CMGetDefaultProfileBySpace(cmRGBData, (CMProfileRef *)&profile->rgbProfile);
        }
    }
    if (cmykName) {
        match = [cmykProfileDictionary objectForKey:cmykName];
        if (match) {
            profile->cmykProfile = match->cmykProfile;
            CMCloneProfileRef((CMProfileRef)profile->cmykProfile);
        } else {
            NSLog(@"Warning: can't find profile \"%@\", using default CMYK profile", cmykName);
            CMGetDefaultProfileBySpace(cmCMYKData, (CMProfileRef *)&profile->cmykProfile);
        }
    }
    if (grayName) {
        match = [grayProfileDictionary objectForKey:grayName];
        if (match) {
            profile->grayProfile = match->grayProfile;
            CMCloneProfileRef((CMProfileRef)profile->grayProfile);
        } else {
            NSLog(@"Warning: can't find profile \"%@\", using default grayscale profile", grayName);
            CMGetDefaultProfileBySpace(cmGrayData, (CMProfileRef *)&profile->grayProfile);
        }
    }
    
    return [profile autorelease];
#else
    OBFinishPorting;
#endif
}

#if OA_USE_COLOR_MANAGER
static BOOL loadProfileData(CMProfileRef *cmProfilePointer, NSData *data, OSType fallbackToDefault)
{
    if (data && [data length]) {
        CMProfileRef profile = NULL;
        CMProfileLocation profileLocation;
        profileLocation.locType = cmBufferBasedProfile;
        profileLocation.u.bufferLoc.buffer = (void *)[data bytes];
        
        // Buffer limited to UInt32.
        OBASSERT(strcmp(@encode(typeof(profileLocation.u.bufferLoc.size)), @encode(UInt32)) == 0);
        OBASSERT([data length] <= UINT_MAX);
        profileLocation.u.bufferLoc.size = (UInt32)[data length];
        
        CMError err = CMOpenProfile(&profile, &profileLocation);
        if (err == noErr) {
            if (*cmProfilePointer)
                CMCloseProfile(*cmProfilePointer);
            *cmProfilePointer = profile;  // transfer the ref count
            return YES;
        } else {
            NSLog(@"CMOpenProfile(<%lu bytes>) returns error %ld", [data length], (long)err);
        }
    }
    
    if (fallbackToDefault != 0 && *cmProfilePointer == NULL) {
        CMProfileRef profile = NULL;
        CMError err = CMGetDefaultProfileBySpace(fallbackToDefault, &profile);
        if (err == noErr) {
            NSLog(@"Warning: using default color profile for %@", [NSString stringWithFourCharCode:fallbackToDefault]);
            *cmProfilePointer = profile;
        } else {
            NSLog(@"Warning: can't even find default profile for color space %@!", [NSString stringWithFourCharCode:fallbackToDefault]);
        }
    }
    
    return NO;
}
#endif

+ (OAColorProfile *)colorProfileFromPropertyListRepresentation:(NSDictionary *)dict;
{
#if OA_USE_COLOR_MANAGER
    // If the Name key doesn't exist, +colorProfileWithRGBNamed: will just keep the default entry, and we'll overwrite it below
    OAColorProfile *colorProfile = [self colorProfileWithRGBNamed:[dict objectForKey:@"rgbName"]
                                                        cmykNamed:[dict objectForKey:@"cmykName"]
                                                        grayNamed:[dict objectForKey:@"grayName"]];
    
    // Use any embedded profiles from the plist
    loadProfileData((CMProfileRef *)&colorProfile->rgbProfile, [dict objectForKey:@"rgb"], cmRGBData);
    loadProfileData((CMProfileRef *)&colorProfile->cmykProfile, [dict objectForKey:@"cmyk"], cmCMYKData);
    loadProfileData((CMProfileRef *)&colorProfile->grayProfile, [dict objectForKey:@"gray"], cmGrayData);
    
    // NSLog(@"Read profiles %p %p %p from %@", colorProfile->rgbProfile, colorProfile->cmykProfile, colorProfile->grayProfile, dict);
    
    return colorProfile;
#else
    OBFinishPortingLater("deprecated");
    return nil;
#endif
}

- (void)dealloc;
{
#if OA_USE_COLOR_MANAGER
    if (currentColorProfile == self)
        currentColorProfile = nil;
    if (lastInProfile == self)
        lastInProfile = nil;
    if (lastOutProfile == self)
        lastOutProfile = nil;
    
    if (rgbProfile) 
        CMCloseProfile(rgbProfile);
    if (cmykProfile)
        CMCloseProfile(cmykProfile);
    if (grayProfile)
        CMCloseProfile(grayProfile);
    [super dealloc];
#else
    OBFinishPorting;
    // rdar:///21697606: Unreachable code fails with missing super call error
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunreachable-code"
    // OBFinishPorting aborts, so the dealloc call here is unreachable; however, clang warns that we're missing a call to [super dealloc] if we remove it.
    [super dealloc];
#pragma clang diagnostic pop
#endif
}

- (id)copyWithZone:(NSZone *)zone;
{
#if OA_USE_COLOR_MANAGER
    if (isMutable) {
        OAColorProfile *result = [[OAColorProfile alloc] init];
        
        if (rgbProfile) {
            result->rgbProfile = rgbProfile;
            CMCloneProfileRef((CMProfileRef)rgbProfile);
        }
        if (cmykProfile) {
            result->cmykProfile = cmykProfile;
            CMCloneProfileRef((CMProfileRef)cmykProfile);
        }
        if (grayProfile) {
            result->grayProfile = grayProfile;
            CMCloneProfileRef((CMProfileRef)grayProfile);
        }
        return result;
    } else
        return [self retain];
#else
    OBFinishPorting;
#endif
}

- (NSMutableDictionary *)propertyListRepresentation;
{
#if OA_USE_COLOR_MANAGER
    NSMutableDictionary *result = [NSMutableDictionary dictionary];

    [self _addProfile:rgbProfile  toPropertyList:result keyStem:@"rgb"];
    [self _addProfile:cmykProfile toPropertyList:result keyStem:@"cmyk"];
    [self _addProfile:grayProfile toPropertyList:result keyStem:@"gray"];
    
    return result;
#else
    OBFinishPorting;
#endif
}

- (void)set;
{
    currentColorProfile = self;
    focusedViewForCurrentColorProfile = [NSView focusView];
}

- (void)unset;
{
    currentColorProfile = nil;
}

- (BOOL)isEqualToProfile:(OAColorProfile *)otherProfile;
{
    // UNDONE: should probably be using profile identifiers here instead of names
    if (rgbProfile != [otherProfile _rgbProfile] && ![[self rgbName] isEqualToString:[otherProfile rgbName]])
        return NO;
    if (cmykProfile != [otherProfile _cmykProfile] &&  ![[self cmykName] isEqualToString:[otherProfile cmykName]])
        return NO;
    return grayProfile == [otherProfile _grayProfile] || [[self grayName] isEqualToString:[otherProfile grayName]];
}

- (NSString *)rgbName;
{
    return rgbProfile ? [self _getProfileName:rgbProfile] : @"-";
}
- (NSString *)cmykName;
{
    return cmykProfile ? [self _getProfileName:cmykProfile] : @"-";
}
- (NSString *)grayName;
{
    return grayProfile ? [self _getProfileName:grayProfile] : @"-";
}

- (NSData *)rgbData;
{
#if OA_USE_COLOR_MANAGER
    return (rgbProfile == nil) ? nil : [self _dataForRawProfile:rgbProfile];
#else
    OBFinishPorting;
#endif
}
- (NSData *)cmykData;
{
#if OA_USE_COLOR_MANAGER
    return (cmykProfile == nil) ? nil : [self _dataForRawProfile:cmykProfile];
#else
    OBFinishPorting;
#endif
}
- (NSData *)grayData;
{
#if OA_USE_COLOR_MANAGER
    return (grayProfile == nil) ? nil : [self _dataForRawProfile:grayProfile];
#else
    OBFinishPorting;
#endif
}


- (NSString *)description;
{
    return [NSString stringWithFormat:@"%@/%@/%@", [self rgbName], [self cmykName], [self grayName]];
}

// For use by NSColor only

- (BOOL)_hasRGBSpace;
{
    return rgbProfile != NULL;
}

- (BOOL)_hasCMYKSpace;
{
    return cmykProfile != NULL;
}

- (BOOL)_hasGraySpace;
{
    return grayProfile != NULL;
}

// TODO: Assumes display profile is always RGB
- (void)_setRGBColor:(NSColor *)aColor;
{
    static CGColorSpaceRef deviceRGBColorSpace = NULL;
    CGContextRef contextRef = [[NSGraphicsContext currentContext] graphicsPort];
    OAColorProfile *destination = [NSGraphicsContext currentContextDrawingToScreen] ? [OAColorProfile defaultDisplayProfile] : [OAColorProfile defaultDocumentProfile];
    NSColor *newColor = [aColor convertFromProfile:self toProfile:destination];
    
    if (!deviceRGBColorSpace) {
        deviceRGBColorSpace = CGColorSpaceCreateDeviceRGB();
        CGColorSpaceRetain(deviceRGBColorSpace);
    }
    CGContextSetFillColorSpace(contextRef, deviceRGBColorSpace);
    CGContextSetStrokeColorSpace(contextRef, deviceRGBColorSpace);
    [newColor setCoreGraphicsRGBValues];
}

- (void)_setCMYKColor:(NSColor *)aColor;
{
    static CGColorSpaceRef deviceCMYKColorSpace = NULL;
    CGContextRef contextRef;
    NSColor *newColor;

    if ([NSGraphicsContext currentContextDrawingToScreen]) {
        NSColor *aColorInRGBColorSpace = [aColor colorUsingColorSpaceName:([[aColor colorSpaceName] isEqualToString:@"NSDeviceCMYKColorSpace"]) ? @"NSDeviceRGBColorSpace":@"NSCalibratedRGBColorSpace"];
        [self _setRGBColor:aColorInRGBColorSpace];
        return;
    }
 
    if (!deviceCMYKColorSpace) {
        deviceCMYKColorSpace = CGColorSpaceCreateDeviceCMYK();
        CGColorSpaceRetain(deviceCMYKColorSpace);
    }
    contextRef = [[NSGraphicsContext currentContext] graphicsPort];
    CGContextSetFillColorSpace(contextRef, deviceCMYKColorSpace);
    CGContextSetStrokeColorSpace(contextRef, deviceCMYKColorSpace);
    newColor = [aColor convertFromProfile:self toProfile:[OAColorProfile defaultDocumentProfile]];
    [newColor setCoreGraphicsCMYKValues];
}

- (void)_setGrayColor:(NSColor *)aColor;
{
    static CGColorSpaceRef deviceGrayColorSpace = NULL;
    CGContextRef contextRef;
    NSColor *newColor;

    if ([NSGraphicsContext currentContextDrawingToScreen]) {
        NSColor *aColorInRGBColorSpace = [aColor colorUsingColorSpaceName:([[aColor colorSpaceName] isEqualToString:@"NSDeviceRGBColorSpace"]) ? @"NSDeviceRGBColorSpace":@"NSCalibratedRGBColorSpace"];
        [self _setRGBColor:aColorInRGBColorSpace];
        return;
    }
    
    if (!deviceGrayColorSpace) {
        deviceGrayColorSpace = CGColorSpaceCreateDeviceGray();
        CGColorSpaceRetain(deviceGrayColorSpace);
    }
    contextRef = [[NSGraphicsContext currentContext] graphicsPort];
    CGContextSetFillColorSpace(contextRef, deviceGrayColorSpace);
    CGContextSetStrokeColorSpace(contextRef, deviceGrayColorSpace);
    newColor = [aColor convertFromProfile:self toProfile:[OAColorProfile defaultDocumentProfile]];
    [newColor setCoreGraphicsGrayValues];
}

- (void **)_cachedRGBColorWorldForOutput:(OAColorProfile *)aProfile;
{
#if OA_USE_COLOR_MANAGER
    [self _updateConversionCacheForOutput:aProfile];
    return (void **)&rgbColorWorld;
#else
    OBFinishPorting;
#endif
}

- (void **)_cachedCMYKColorWorldForOutput:(OAColorProfile *)aProfile;
{
#if OA_USE_COLOR_MANAGER
    [self _updateConversionCacheForOutput:aProfile];
    return (void **)&cmykColorWorld;
#else
    OBFinishPorting;
#endif
}

- (void **)_cachedGrayColorWorldForOutput:(OAColorProfile *)aProfile;
{
#if OA_USE_COLOR_MANAGER
    [self _updateConversionCacheForOutput:aProfile];
    return (void **)&grayColorWorld;
#else
    OBFinishPorting;
#endif
}

- (void *)_rgbProfile;
{
    return rgbProfile ? rgbProfile : [self _anyProfile];
}

- (void *)_cmykProfile;
{
    return cmykProfile ? cmykProfile : [self _anyProfile];
}

- (void *)_grayProfile;
{
    return grayProfile ? grayProfile : [self _anyProfile];
}

- (void *)_rgbConversionWorldForOutput:(OAColorProfile *)aProfile;
{
#if OA_USE_COLOR_MANAGER
    if (!aProfile)
        return NULL;
    
    [self _updateConversionCacheForOutput:aProfile];
    
    if (!rgbColorWorld) {
        if (rgbProfile == aProfile->rgbProfile || !rgbProfile)
            return NULL;
        NCWNewColorWorld(&rgbColorWorld, rgbProfile, [aProfile _rgbProfile]);
    }
    return rgbColorWorld;
#else
    OBFinishPorting;
#endif
}

- (void *)_cmykConversionWorldForOutput:(OAColorProfile *)aProfile;
{
#if OA_USE_COLOR_MANAGER
    [self _updateConversionCacheForOutput:aProfile];
    
    if (!cmykColorWorld) {
        if (cmykProfile == aProfile->cmykProfile || !cmykProfile)
            return NULL;
        NCWNewColorWorld(&cmykColorWorld, cmykProfile, [aProfile _cmykProfile]);
    }
    return cmykColorWorld;
#else
    OBFinishPorting;
#endif
}

- (void *)_grayConversionWorldForOutput:(OAColorProfile *)aProfile;
{
#if OA_USE_COLOR_MANAGER
    [self _updateConversionCacheForOutput:aProfile];
    
    if (!grayColorWorld) {
        if (grayProfile == aProfile->grayProfile || !grayProfile)
            return NULL;
        NCWNewColorWorld(&grayColorWorld, grayProfile, [aProfile _grayProfile]);
    }
    return grayColorWorld;
#else
    OBFinishPorting;
#endif
}

@end

@implementation OAColorProfile (Private)

+ (void)_forwardDeviceNotification;
{
    [[NSNotificationCenter defaultCenter] postNotificationName:OAColorProofingDevicesDidChangeNotification object:nil]; 
}

+ (void)_deviceNotification:(NSNotification *)notification;
{
    [self queueSelectorOnce:@selector(_forwardDeviceNotification)];
}

// TODO: This function returns the localized string, which is not very useful for storing in plists!
- (NSString *)_getProfileName:(void *)aProfile;
{
#if OA_USE_COLOR_MANAGER
    // TODO: This leaks.

    CFStringRef string = nil;
    CMError error;
    
    error = CMCopyProfileDescriptionString((CMProfileRef)aProfile, &string);
    if (error == noErr)
        return (NSString *)string;
    
    error = CMCopyProfileLocalizedString((CMProfileRef)aProfile, cmProfileDescriptionTag, 0, 0, &string);
    if (error == noErr)
        return (NSString *)string;
    
    error = CMCopyProfileLocalizedString((CMProfileRef)aProfile, cmProfileDescriptionMLTag, 0,0, &string);
    if (error == noErr)
        return (NSString *)string;
    
    return nil; // everything errored out
#else
    OBFinishPorting;
#endif
}

- (void)colorProfileDidChange:(NSNotification *)notification;
{
#if OA_USE_COLOR_MANAGER
    lastInProfile = nil;
    lastOutProfile = nil;

    CMCloseProfile(rgbProfile);
    CMCloseProfile(cmykProfile);
    CMCloseProfile(grayProfile);
    CMGetDefaultProfileBySpace(cmRGBData, (CMProfileRef *)&rgbProfile);
    CMGetDefaultProfileBySpace(cmCMYKData, (CMProfileRef *)&cmykProfile);
    CMGetDefaultProfileBySpace(cmGrayData, (CMProfileRef *)&grayProfile);
    
    [[NSNotificationCenter defaultCenter] postNotificationName:OADefaultDocumentColorProfileDidChangeNotification object:nil]; 
#else
    OBFinishPorting;
#endif
}

- initDefaultDocumentProfile;
{
#if OA_USE_COLOR_MANAGER
    if (!(self = [super init]))
        return nil;
    
    int errorCode = CMGetDefaultProfileBySpace(cmRGBData, (CMProfileRef *)&rgbProfile);
    if (rgbProfile == NULL || errorCode != noErr) {
        NSColorSpace *colorSpace = [NSColorSpace genericRGBColorSpace];
        rgbProfile = [colorSpace colorSyncProfile];
        [self _profileLoadError:errorCode defaultColorSpace:colorSpace];
    }
    
    errorCode = CMGetDefaultProfileBySpace(cmCMYKData, (CMProfileRef *)&cmykProfile);
    if (cmykProfile == NULL || errorCode != noErr) {
        NSColorSpace *colorSpace = [NSColorSpace genericCMYKColorSpace];
        cmykProfile = [colorSpace colorSyncProfile];
        [self _profileLoadError:errorCode defaultColorSpace:colorSpace];
    }
    
    errorCode = CMGetDefaultProfileBySpace(cmGrayData, (CMProfileRef *)&grayProfile);
    if (grayProfile == NULL || errorCode != noErr) {
        NSColorSpace *colorSpace = [NSColorSpace genericGrayColorSpace];
        grayProfile = [colorSpace colorSyncProfile];
        [self _profileLoadError:errorCode defaultColorSpace:colorSpace];
    }

// The notification isn't available on 10.1
#ifdef kCMPrefsChangedNotification
    [[NSDistributedNotificationCenter defaultCenter] addObserver:self selector:@selector(colorProfileDidChange:) name:(NSString *)kCMPrefsChangedNotification object:nil];
#endif

    isMutable = YES;
    return self;
#else
    OBFinishPortingLater("color profiles are disabled");
    [self release];
    return nil;
#endif
}

- initDefaultProofProfile;
{
#if OA_USE_COLOR_MANAGER
    if (!(self = [super init]))
        return nil;
    
    CMProfileRef profile;
    CMAppleProfileHeader header;
    
    int errorCode = CMGetDefaultProfileByUse(cmProofUse, &profile);
    if (profile == NULL || errorCode != noErr) {
        NSColorSpace *colorSpace = [NSColorSpace genericRGBColorSpace];
        profile = [colorSpace colorSyncProfile];
        [self _profileLoadError:errorCode defaultColorSpace:colorSpace];
    }
    
    CMGetProfileHeader(profile, &header);
    switch(header.cm2.dataColorSpace) {
        case cmRGBData:
            rgbProfile = profile;
            break;
        case cmCMYKData:
            cmykProfile = profile;
            break;
        case cmGrayData:
            grayProfile = profile;
            break;
        default:
            [self release];
            return nil;
    }
    isMutable = YES;
    return self;
#else
    OBFinishPorting;
#endif
}

- initDefaultDisplayProfile;
{
#if OA_USE_COLOR_MANAGER
    if (!(self = [super init]))
        return nil;
    
    CMProfileRef profile;
    CMAppleProfileHeader header;
    
    int errorCode = CMGetDefaultProfileByUse(cmDisplayUse, &profile);
    if (profile == NULL || errorCode != noErr) {
        NSColorSpace *colorSpace = [NSColorSpace genericRGBColorSpace];
        profile = [colorSpace colorSyncProfile];
        [self _profileLoadError:errorCode defaultColorSpace:colorSpace];
    }
    
    CMGetProfileHeader(profile, &header);
    switch(header.cm2.dataColorSpace) {
        case cmRGBData:
            rgbProfile = profile;
            break;
        case cmCMYKData:
            cmykProfile = profile;
            break;
        case cmGrayData:
            grayProfile = profile;
            break;
        default:
            [self release];
            return nil;
    }
    isMutable = YES;
    return self;
#else
    OBFinishPorting;
#endif
}

- (void)_updateConversionCacheForOutput:(OAColorProfile *)aProfile;
{
#if OA_USE_COLOR_MANAGER
    if (self != lastInProfile || aProfile != lastOutProfile) {
        if (rgbColorWorld != NULL) {
            CWDisposeColorWorld(rgbColorWorld);
            rgbColorWorld = NULL;
        }
        if (cmykColorWorld != NULL) {
            CWDisposeColorWorld(cmykColorWorld);
            cmykColorWorld = NULL;
        }
        if (grayColorWorld != NULL) {
            CWDisposeColorWorld(grayColorWorld);
            grayColorWorld = NULL;
        }
        lastInProfile = self;
        lastOutProfile = aProfile;
    }
#else
    OBFinishPorting;
#endif
}

- (void *)_anyProfile;
{
    if (rgbProfile)
        return rgbProfile;
    else if (cmykProfile)
        return cmykProfile;
    else 
        return grayProfile;
}

#if OA_USE_COLOR_MANAGER
- (NSData *)_dataForRawProfile:(CMProfileRef)rawProfile;
{
    CMProfileRef targetRef;
    CMAppleProfileHeader header;
    CMProfileLocation profileLocation;
    NSMutableData *data;

    CMError err = CMGetProfileHeader(rawProfile, &header);
    if (err != noErr) {
        NSLog(@"Cannot copy color profile %p: CMError %ld", rawProfile, (long)err);
        return nil;
    }
    
    data = [[NSMutableData alloc] initWithLength:header.cm2.size];
    profileLocation.locType = cmBufferBasedProfile;
    profileLocation.u.bufferLoc.buffer = [data mutableBytes];
    profileLocation.u.bufferLoc.size = header.cm2.size;
    CMCopyProfile(&targetRef, &profileLocation, rawProfile);
    
#ifdef OMNI_ASSERTIONS_ON
    CFDataRef iccData = CMProfileCopyICCData(kCFAllocatorDefault, rawProfile);
    OBASSERT([data isEqual:(id)iccData]);
    CFRelease(iccData);
#endif
    
    return [data autorelease];
}

- (BOOL)_addProfile:(CMProfileRef)cmProfile
     toPropertyList:(NSMutableDictionary *)dict
            keyStem:(NSString *)spaceName
{
    CMProfileMD5 hash;
    if (CMGetProfileMD5(cmProfile, hash) == noErr) {
        [dict setObject:[NSData dataWithBytes:hash length:sizeof(hash)] forKey:[spaceName stringByAppendingString:@"Digest"]];
    }

    if (![self _rawProfileIsBuiltIn:cmProfile]) {
        NSData *profileData = [self _dataForRawProfile:cmProfile];
        if (profileData && [profileData length]) {
            [dict setObject:profileData forKey:spaceName];
            return YES;
        }
    }
    
    NSString *profileName = [self _getProfileName:cmProfile];
    if(![NSString isEmptyString:profileName]) {
        [dict setObject:profileName forKey:[spaceName stringByAppendingString:@"Name"]];
        return YES;
    }
    
    return NO;
}
#endif

- (void)_profileLoadError:(int)errorCode defaultColorSpace:(NSColorSpace *)colorSpace;
{
    NSString *failureReason = NSLocalizedStringFromTableInBundle(@"Failed to set color sync profile (error %i)", @"OmniAppKit", [OAColorProfile bundle], @"Color sync profile load error");
    NSString *description = NSLocalizedStringFromTableInBundle(@"Defaulting to '%@'", @"OmniAppKit", [OAColorProfile bundle], @"Color sync profile load error recovery description");
    NSDictionary *errorUserInfo = [[NSDictionary alloc] initWithObjectsAndKeys:[NSString stringWithFormat:failureReason, errorCode], NSLocalizedDescriptionKey, [NSString stringWithFormat:description, [colorSpace localizedName]], NSLocalizedRecoverySuggestionErrorKey, nil];
    [self performSelector:@selector(_displayErrorWithUserInfo:) withObject:errorUserInfo afterDelay:0];
    [errorUserInfo release];
}

- (void)_displayErrorWithUserInfo:(NSDictionary *)errorUserInfo;
{
    NSError *error = [[NSError alloc] initWithDomain:NSCocoaErrorDomain code:0 userInfo:errorUserInfo];
    [[NSApplication sharedApplication] presentError:error];
    [error release];
}

@end
