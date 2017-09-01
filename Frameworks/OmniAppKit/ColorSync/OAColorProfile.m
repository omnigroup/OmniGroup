// Copyright 2002-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OAColorProfile.h>

#import <OmniAppKit/NSColor-ColorSyncExtensions.h>
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
- (instancetype)initDefaultDocumentProfile;
- (instancetype)initDefaultProofProfile;
- (instancetype)initDefaultDisplayProfile;

- (NSString *)_getProfileName:(ColorSyncProfileRef)aProfile;

- (ColorSyncProfileRef)_anyProfile;
- (void)_updateConversionCacheForOutput:(OAColorProfile *)outputProfile;
- (NSData *)_dataForRawProfile:(ColorSyncProfileRef)rawProfile;
- (BOOL)_addProfile:(ColorSyncProfileRef)cmProfile toPropertyList:(NSMutableDictionary *)dict keyStem:(NSString *)spaceName;
- (void)_profileLoadError:(int)errorCode defaultColorSpace:(NSColorSpace *)colorSpace;

@end

NSString * const OADefaultDocumentColorProfileDidChangeNotification = @"OADefaultDocumentColorProfileDidChangeNotification";
NSString * const OAColorProofingDevicesDidChangeNotification = @"OAColorProofingDevicesDidChangeNotification";

@implementation OAColorProfile

static BOOL resetProfileLists = YES;
static NSMutableDictionary *rgbProfileDictionary = nil;
static NSMutableDictionary *cmykProfileDictionary = nil;
static NSMutableDictionary *grayProfileDictionary = nil;
static BOOL resetDeviceList = YES;
static NSMutableDictionary *deviceProfileDictionary = nil;
static NSMutableDictionary *deviceNameDictionary = nil;
static __unsafe_unretained OAColorProfile *currentColorProfile = nil;
static NSView *focusedViewForCurrentColorProfile = nil;

static __unsafe_unretained OAColorProfile *lastInProfile = nil;
static __unsafe_unretained OAColorProfile *lastOutProfile = nil;
static ColorSyncTransformRef rgbColorWorld = NULL;
static ColorSyncTransformRef cmykColorWorld = NULL;
static ColorSyncTransformRef grayColorWorld = NULL;

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
    OAColorProfile *result = [[self alloc] init];
    
    result->cmykProfile = ColorSyncProfileCreateMutableCopy([[self defaultDocumentProfile] _cmykProfile]);
    return [result autorelease];
}

+ (nullable OAColorProfile *)currentProfile;
{
    if (currentColorProfile != nil) {
        if ([NSView focusView] == focusedViewForCurrentColorProfile)
            return currentColorProfile;
        else
            currentColorProfile = nil;
    }
    return nil;
}

static bool deviceListIterator(CFDictionaryRef deviceInfo,
                               void* refCon)
{
    ColorSyncProfileRef cmProfile;
    CMAppleProfileHeader header;
    OAColorProfile *profile;
    NSString *deviceName, *profileName;
    
    if (resetDeviceList) {
        [deviceProfileDictionary release];
        [deviceNameDictionary release];
        deviceProfileDictionary = [[NSMutableDictionary alloc] init];
        deviceNameDictionary = [[NSMutableDictionary alloc] init];
        resetDeviceList = NO;
    }
    
    CFStringRef deviceClass = CFDictionaryGetValue(deviceInfo, kColorSyncDeviceClass);
    if (!CFEqual(deviceClass, kColorSyncPrinterDeviceClass) && !CFEqual(deviceClass, CFSTR("pruf"))) {
        return true;
    }
    CFURLRef profileURL = CFDictionaryGetValue(deviceInfo, kColorSyncDeviceProfileURL);
    
    cmProfile = ColorSyncProfileCreateWithURL(profileURL, NULL);
    if (cmProfile == NULL)
        return true;
    
    CFDataRef cfHeader = ColorSyncProfileCopyHeader(cmProfile);
    if (cfHeader == NULL) {
        CFRelease(cmProfile);
        return 0;
    }
    
    profile = [[OAColorProfile alloc] init];
    CFDataGetBytes(cfHeader, CFRangeMake(0, sizeof(CMAppleProfileHeader)), (UInt8*)&header);
    CFRelease(cfHeader);
    
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
            CFRelease(cmProfile);
            [profile release];
            return 0;
    }
    
    if (CFDictionaryGetValue(deviceInfo, kColorSyncDeviceDescription) || CFDictionaryGetValue(deviceInfo, kColorSyncDeviceDescriptions)) {
        NSDictionary *nameDictionary = CFDictionaryGetValue(deviceInfo, kColorSyncDeviceDescriptions);
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

+ (NSArray *)proofingDeviceProfileNames;
{
    resetDeviceList = YES;
    ColorSyncIterateDeviceProfiles(deviceListIterator, NULL);
    return [deviceProfileDictionary allKeys];
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

static bool nameListIterator(CFDictionaryRef profileInfo, void *refCon)
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
    
    //if (iterateData->uniCodeNameCount <= 1) // null terminated
    //    return cmProfileError;
    
    NSString *name = CFDictionaryGetValue(profileInfo, CFSTR("com.apple.ColorSync.ProfileASCIIDescription"));
    
    CFURLRef profileURL = CFDictionaryGetValue(profileInfo, kColorSyncProfileURL);
    ColorSyncProfileRef cmProfile = NULL;
    
    cmProfile = ColorSyncProfileCreateWithURL(profileURL, NULL);
    if (cmProfile == NULL) {
        NSLog(@"ColorSyncProfileCreateWithURL() for '%@' returns nil", name);
        return true;
    }
    
    OAColorProfile *profile = [[OAColorProfile alloc] init];
    
    // NSLog(@"Profile name %@ (v %08x) = %p", name, iterateData->dataVersion, cmProfile);
    CFStringRef colorSpace = CFDictionaryGetValue(profileInfo, kColorSyncProfileColorSpace);
    if (CFEqual(colorSpace, kColorSyncSigRgbData)) {
        profile->rgbProfile = (void*)cmProfile;
        [rgbProfileDictionary setObject:profile forKey:name];
    } else if(CFEqual(colorSpace, kColorSyncSigCmykData)) {
        profile->cmykProfile = (void*)cmProfile;
        [rgbProfileDictionary setObject:profile forKey:name];
    } else if(CFEqual(colorSpace, kColorSyncSigGrayData)) {
        profile->grayProfile = (void*)cmProfile;
        [rgbProfileDictionary setObject:profile forKey:name];
    } else {
        CFRelease(cmProfile);
    }
    [profile release];
    return true;
}

+ (void)_iterateAvailableProfiles;
{
    static UInt32 seed = 0;
    
    resetProfileLists = YES;
    ColorSyncIterateInstalledProfiles(nameListIterator, &seed, NULL, NULL);
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
    // ColorSyncProfileCreateMutableCopy is the closest I could find to a copy function :/
    OAColorProfile *profile = [[self alloc] init];
    OAColorProfile *match;

    [self _iterateAvailableProfiles];
    
    if (rgbName) {
        match = [rgbProfileDictionary objectForKey:rgbName];
        if (match) {
            profile->rgbProfile = ColorSyncProfileCreateMutableCopy(match->rgbProfile);
        } else {
            NSLog(@"Warning: can't find profile \"%@\", using default RGB profile", rgbName);
            profile->rgbProfile = ColorSyncProfileCreateWithName(kColorSyncGenericRGBProfile);
        }
    }
    if (cmykName) {
        match = [cmykProfileDictionary objectForKey:cmykName];
        if (match) {
            profile->cmykProfile = ColorSyncProfileCreateMutableCopy(match->cmykProfile);
        } else {
            NSLog(@"Warning: can't find profile \"%@\", using default CMYK profile", cmykName);
            profile->cmykProfile = ColorSyncProfileCreateWithName(kColorSyncGenericCMYKProfile);
        }
    }
    if (grayName) {
        match = [grayProfileDictionary objectForKey:grayName];
        if (match) {
            profile->grayProfile = ColorSyncProfileCreateMutableCopy(match->grayProfile);
        } else {
            NSLog(@"Warning: can't find profile \"%@\", using default grayscale profile", grayName);
            profile->grayProfile = ColorSyncProfileCreateWithName(kColorSyncGenericGrayProfile);
        }
    }
    
    return [profile autorelease];
}

static BOOL loadProfileData(ColorSyncProfileRef *cmProfilePointer, NSData *data, CFStringRef fallbackToDefault)
{
    if (data && [data length]) {
        ColorSyncProfileRef profile = NULL;
        CFErrorRef err = NULL;
        
        // Buffer limited to UInt32.
        //OBASSERT(strcmp(@encode(typeof(profileLocation.u.bufferLoc.size)), @encode(UInt32)) == 0);
        OBASSERT([data length] <= UINT_MAX);
        //profileLocation.u.bufferLoc.size = (UInt32)[data length];
        
        profile = ColorSyncProfileCreate((CFDataRef)data, &err);
        if (profile != nil) {
            if (*cmProfilePointer)
                CFRelease(*cmProfilePointer);
            *cmProfilePointer = profile;  // transfer the ref count
            return YES;
        } else {
            NSLog(@"CMOpenProfile(<%lu bytes>) returns error %@", [data length], err);
        }
    }
    
    if (fallbackToDefault != 0 && *cmProfilePointer == NULL) {
        ColorSyncProfileRef profile = NULL;
        profile = ColorSyncProfileCreateWithName(fallbackToDefault);
        if (profile != nil) {
            NSLog(@"Warning: using default color profile for %@", fallbackToDefault);
            *cmProfilePointer = profile;
        } else {
            NSLog(@"Warning: can't even find default profile for color space %@!", fallbackToDefault);
        }
    }
    
    return NO;
}

+ (OAColorProfile *)colorProfileFromPropertyListRepresentation:(NSDictionary *)dict;
{
    // If the Name key doesn't exist, +colorProfileWithRGBNamed: will just keep the default entry, and we'll overwrite it below
    OAColorProfile *colorProfile = [self colorProfileWithRGBNamed:[dict objectForKey:@"rgbName"]
                                                        cmykNamed:[dict objectForKey:@"cmykName"]
                                                        grayNamed:[dict objectForKey:@"grayName"]];
    
    // Use any embedded profiles from the plist
    loadProfileData(&colorProfile->rgbProfile, [dict objectForKey:@"rgb"], kColorSyncGenericRGBProfile);
    loadProfileData(&colorProfile->cmykProfile, [dict objectForKey:@"cmyk"], kColorSyncGenericCMYKProfile);
    loadProfileData(&colorProfile->grayProfile, [dict objectForKey:@"gray"], kColorSyncGenericGrayProfile);
    
    // NSLog(@"Read profiles %p %p %p from %@", colorProfile->rgbProfile, colorProfile->cmykProfile, colorProfile->grayProfile, dict);
    
    return colorProfile;
}

- (void)dealloc;
{
    if (currentColorProfile == self)
        currentColorProfile = nil;
    if (lastInProfile == self)
        lastInProfile = nil;
    if (lastOutProfile == self)
        lastOutProfile = nil;
    
    if (rgbProfile)
        CFRelease(rgbProfile);
    if (cmykProfile)
        CFRelease(cmykProfile);
    if (grayProfile)
        CFRelease(grayProfile);
    [super dealloc];
}

- (id)copyWithZone:(NSZone *)zone;
{
    // ColorSyncProfileCreateMutableCopy is the closest I could find to a copy function :/
    if (isMutable) {
        OAColorProfile *result = [[OAColorProfile alloc] init];
        
        if (rgbProfile) {
            result->rgbProfile = ColorSyncProfileCreateMutableCopy(rgbProfile);
        }
        if (cmykProfile) {
            result->cmykProfile = ColorSyncProfileCreateMutableCopy(cmykProfile);
        }
        if (grayProfile) {
            result->grayProfile = ColorSyncProfileCreateMutableCopy(grayProfile);
        }
        return result;
    } else
        return [self retain];
}

- (NSMutableDictionary *)propertyListRepresentation;
{
    NSMutableDictionary *result = [NSMutableDictionary dictionary];

    [self _addProfile:rgbProfile  toPropertyList:result keyStem:@"rgb"];
    [self _addProfile:cmykProfile toPropertyList:result keyStem:@"cmyk"];
    [self _addProfile:grayProfile toPropertyList:result keyStem:@"gray"];
    
    return result;
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
    return (rgbProfile == nil) ? nil : [self _dataForRawProfile:rgbProfile];
}
- (NSData *)cmykData;
{
    return (cmykProfile == nil) ? nil : [self _dataForRawProfile:cmykProfile];
}
- (NSData *)grayData;
{
    return (grayProfile == nil) ? nil : [self _dataForRawProfile:grayProfile];
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
        NSColor *aColorInRGBColorSpace = [aColor colorUsingColorSpaceName:([[aColor colorSpaceName] isEqualToString:NSDeviceCMYKColorSpace]) ? NSDeviceRGBColorSpace : NSCalibratedRGBColorSpace];
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

- (ColorSyncTransformRef*)_cachedRGBColorWorldForOutput:(OAColorProfile *)aProfile;
{
    [self _updateConversionCacheForOutput:aProfile];
    return &rgbColorWorld;
}

- (ColorSyncTransformRef*)_cachedCMYKColorWorldForOutput:(OAColorProfile *)aProfile;
{
    [self _updateConversionCacheForOutput:aProfile];
    return &cmykColorWorld;
}

- (ColorSyncTransformRef*)_cachedGrayColorWorldForOutput:(OAColorProfile *)aProfile;
{
    [self _updateConversionCacheForOutput:aProfile];
    return &grayColorWorld;
}

- (ColorSyncProfileRef)_rgbProfile;
{
    return rgbProfile ? rgbProfile : [self _anyProfile];
}

- (ColorSyncProfileRef)_cmykProfile;
{
    return cmykProfile ? cmykProfile : [self _anyProfile];
}

- (ColorSyncProfileRef)_grayProfile;
{
    return grayProfile ? grayProfile : [self _anyProfile];
}

- (ColorSyncTransformRef _Nullable)_rgbConversionWorldForOutput:(OAColorProfile *)aProfile;
{
    if (!aProfile)
        return NULL;
    
    [self _updateConversionCacheForOutput:aProfile];
    
    if (!rgbColorWorld) {
        if (rgbProfile == aProfile->rgbProfile || !rgbProfile)
            return NULL;
        NSMutableArray *profiles = [NSMutableArray arrayWithCapacity:2];
        [profiles addObject:[NSDictionary dictionaryWithObjectsAndKeys:(id)rgbProfile, (id)kColorSyncProfile, (id)kColorSyncRenderingIntentPerceptual, (id)kColorSyncRenderingIntent, (id)kColorSyncTransformDeviceToPCS, (id)kColorSyncTransformTag, nil]];
        [profiles addObject:[NSDictionary dictionaryWithObjectsAndKeys:(id)[aProfile _rgbProfile], (id)kColorSyncProfile, (id)kColorSyncRenderingIntentPerceptual, (id)kColorSyncRenderingIntent, (id)kColorSyncTransformPCSToDevice, (id)kColorSyncTransformTag, nil]];
        
        cmykColorWorld = ColorSyncTransformCreate((CFArrayRef)profiles, NULL);
    }
    return cmykColorWorld;
}

- (ColorSyncTransformRef _Nullable)_cmykConversionWorldForOutput:(OAColorProfile *)aProfile;
{
    if (!aProfile)
        return NULL;
    
    [self _updateConversionCacheForOutput:aProfile];
    
    if (!cmykColorWorld) {
        if (cmykProfile == aProfile->cmykProfile || !cmykProfile)
            return NULL;
        NSMutableArray *profiles = [NSMutableArray arrayWithCapacity:2];
        [profiles addObject:[NSDictionary dictionaryWithObjectsAndKeys:(id)cmykProfile, (id)kColorSyncProfile, (id)kColorSyncRenderingIntentPerceptual, (id)kColorSyncRenderingIntent, kColorSyncTransformDeviceToPCS, kColorSyncTransformTag, nil]];
        [profiles addObject:[NSDictionary dictionaryWithObjectsAndKeys:(id)[aProfile _cmykProfile], (id)kColorSyncProfile, (id)kColorSyncRenderingIntentPerceptual, (id)kColorSyncRenderingIntent, kColorSyncTransformPCSToDevice, kColorSyncTransformTag, nil]];
        
        cmykColorWorld = ColorSyncTransformCreate((CFArrayRef)profiles, NULL);
    }
    return cmykColorWorld;
}

- (ColorSyncTransformRef _Nullable)_grayConversionWorldForOutput:(OAColorProfile *)aProfile;
{
    if (!aProfile)
        return NULL;
    
    [self _updateConversionCacheForOutput:aProfile];
    
    if (!grayColorWorld) {
        if (grayProfile == aProfile->grayProfile || !grayProfile)
            return NULL;
        NSMutableArray *profiles = [NSMutableArray arrayWithCapacity:2];
        [profiles addObject:[NSDictionary dictionaryWithObjectsAndKeys:(id)grayProfile, (id)kColorSyncProfile, (id)kColorSyncRenderingIntentPerceptual, (id)kColorSyncRenderingIntent, kColorSyncTransformDeviceToPCS, kColorSyncTransformTag, nil]];
        [profiles addObject:[NSDictionary dictionaryWithObjectsAndKeys:(id)[aProfile _grayProfile], (id)kColorSyncProfile, (id)kColorSyncRenderingIntentPerceptual, (id)kColorSyncRenderingIntent, (id)kColorSyncTransformPCSToDevice, (id)kColorSyncTransformTag, nil]];

        grayColorWorld = ColorSyncTransformCreate((CFArrayRef)profiles, NULL);
    }
    return grayColorWorld;
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
- (NSString *)_getProfileName:(ColorSyncProfileRef)aProfile;
{
    return CFBridgingRelease(ColorSyncProfileCopyDescriptionString(aProfile));
}

- (void)colorProfileDidChange:(NSNotification *)notification;
{
    lastInProfile = nil;
    lastOutProfile = nil;

    if (rgbProfile) { CFRelease(rgbProfile); rgbProfile = NULL; }
    if (cmykProfile) { CFRelease(cmykProfile); cmykProfile = NULL; }
    if (grayProfile) { CFRelease(grayProfile); grayProfile = NULL; }
    rgbProfile = ColorSyncProfileCreateWithName(kColorSyncGenericRGBProfile);
    cmykProfile = ColorSyncProfileCreateWithName(kColorSyncGenericCMYKProfile);
    grayProfile = ColorSyncProfileCreateWithName(kColorSyncGenericGrayProfile);
    
    [[NSNotificationCenter defaultCenter] postNotificationName:OADefaultDocumentColorProfileDidChangeNotification object:nil]; 
}

- initDefaultDocumentProfile;
{
    if (!(self = [super init]))
        return nil;
    
    rgbProfile = ColorSyncProfileCreateWithName(kColorSyncGenericRGBProfile);
    if (rgbProfile == NULL) {
        NSColorSpace *colorSpace = [NSColorSpace genericRGBColorSpace];
        rgbProfile = CFRetain([colorSpace colorSyncProfile]);
        [self _profileLoadError:-1 defaultColorSpace:colorSpace];
    }
    
    cmykProfile = ColorSyncProfileCreateWithName(kColorSyncGenericCMYKProfile);
    if (cmykProfile == NULL) {
        NSColorSpace *colorSpace = [NSColorSpace genericCMYKColorSpace];
        cmykProfile = CFRetain([colorSpace colorSyncProfile]);
        [self _profileLoadError:-1 defaultColorSpace:colorSpace];
    }
    
    grayProfile = ColorSyncProfileCreateWithName(kColorSyncGenericGrayProfile);
    if (grayProfile == NULL) {
        NSColorSpace *colorSpace = [NSColorSpace genericGrayColorSpace];
        grayProfile = CFRetain([colorSpace colorSyncProfile]);
        [self _profileLoadError:-1 defaultColorSpace:colorSpace];
    }

// The notification isn't available on 10.1
#ifdef kCMPrefsChangedNotification
    [[NSDistributedNotificationCenter defaultCenter] addObserver:self selector:@selector(colorProfileDidChange:) name:(NSString *)kCMPrefsChangedNotification object:nil];
#endif

    isMutable = YES;
    return self;
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
    OBFinishPortingWithNote("<bug:///147881> (iOS-OmniOutliner Engineering: -[OAColorProfile initDefaultProofProfile] - update for new ColorSync APIs)");
#endif
}

- (instancetype)initDefaultDisplayProfile;
{
    if (!(self = [super init]))
        return nil;
    
    ColorSyncProfileRef profile = ColorSyncProfileCreateWithDisplayID(0);
    CMAppleProfileHeader header;
    
    int errorCode = -1;
    if (profile == NULL || errorCode != noErr) {
        NSColorSpace *colorSpace = [NSColorSpace genericRGBColorSpace];
        profile = (ColorSyncProfileRef)CFRetain([colorSpace colorSyncProfile]);
        [self _profileLoadError:errorCode defaultColorSpace:colorSpace];
    }
    
    {
        CFDataRef headerData = ColorSyncProfileCopyHeader(profile);
        CFDataGetBytes(headerData, CFRangeMake(0, sizeof(header)), (UInt8 *)&header);
        CFRelease(headerData);
    }
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
            CFRelease(profile);
            [self release];
            return nil;
    }
    isMutable = YES;
    return self;
}

- (void)_updateConversionCacheForOutput:(OAColorProfile *)aProfile;
{
    if (self != lastInProfile || aProfile != lastOutProfile) {
        if (rgbColorWorld != NULL) {
            CFRelease(rgbColorWorld);
            rgbColorWorld = NULL;
        }
        if (cmykColorWorld != NULL) {
            CFRelease(cmykColorWorld);
            cmykColorWorld = NULL;
        }
        if (grayColorWorld != NULL) {
            CFRelease(grayColorWorld);
            grayColorWorld = NULL;
        }
        lastInProfile = self;
        lastOutProfile = aProfile;
    }
}

- (ColorSyncProfileRef)_anyProfile;
{
    if (rgbProfile)
        return rgbProfile;
    else if (cmykProfile)
        return cmykProfile;
    else 
        return grayProfile;
}

- (NSData *)_dataForRawProfile:(ColorSyncProfileRef)rawProfile;
{
    return CFBridgingRelease(ColorSyncProfileCopyData(rawProfile, NULL));
}

//ColorSyncProfileGetMD5 returns an invalid hash when all the bytes are 0.
static BOOL isValidHash(ColorSyncMD5 hash)
{
    for (int i = 0; i < COLORSYNC_MD5_LENGTH; i++) {
        if (hash.digest[i] != 0) {
            return YES;
        }
    }
    return NO;
}

- (BOOL)_addProfile:(ColorSyncProfileRef)cmProfile
     toPropertyList:(NSMutableDictionary *)dict
            keyStem:(NSString *)spaceName
{
    ColorSyncMD5 hash = ColorSyncProfileGetMD5(cmProfile);
    
    if (isValidHash(hash)) {
        [dict setObject:[NSData dataWithBytes:&hash length:sizeof(hash)] forKey:[spaceName stringByAppendingString:@"Digest"]];
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
