// Copyright 2004-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OAColorSpace.h"

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

RCS_ID("$Id$");

@interface OACGColorSpaceColor : NSColor
{
    OAContinuousColorSpace *space;
    float components[0];
}

- initWithComponents:(const float *)someComponents space:(OAContinuousColorSpace *)space;

- (float)componentNamed:(NSString *)componentName;

@end

@interface OAIndexedColor : NSColor
{
    OADiscreteColorSpace *space;
    NSString *colorName;
    unsigned int colorIndex;
    NSColor *colorValue;
}

- initWithColor:(NSColor *)aColor index:(unsigned int)anIndex name:(NSString *)aName space:(OADiscreteColorSpace *)aSpace;

@end

@implementation OAColorSpace

static NSArray *xyzNames, *labNames, *luvNames, *yxyNames, *ycbcrNames, *rgbNames, *grayNames, *hsvNames, *hlsNames, *cmykNames, *cmyNames, *nameNames;

+ (void)initialize
{
    OBINITIALIZE;
    
    xyzNames = [[NSArray alloc] initWithObjects:@"x", @"y", @"z", nil];
    labNames = [[NSArray alloc] initWithObjects:@"L*", @"a*", @"b*", nil];
    luvNames = [[NSArray alloc] initWithObjects:@"L*", @"u*", @"v*", nil];
    yxyNames = [[NSArray alloc] initWithObjects:@"Y", @"x", @"y", nil];
    ycbcrNames = [[NSArray alloc] initWithObjects:@"Y", @"Cb", @"Cr", nil];
    rgbNames = [[NSArray alloc] initWithObjects:@"r", @"g", @"b", nil];
    hsvNames = [[NSArray alloc] initWithObjects:@"h", @"s", @"v", nil];
    hlsNames = [[NSArray alloc] initWithObjects:@"h", @"l", @"s", nil];
    cmykNames = [[NSArray alloc] initWithObjects:@"c", @"m", @"y", @"k", nil];
    cmyNames = [[NSArray alloc] initWithObjects:@"c", @"m", @"y", nil];
    grayNames = [[NSArray alloc] initWithObjects:@"w", nil];
    nameNames = [[NSArray alloc] initWithObjects:@"name", nil];
}

static NSArray *componentNamesForColorSpace(OSType inputColorSpace)
{
    switch(inputColorSpace) {
        case cmXYZData:
            return xyzNames;
        case cmLabData:
            return labNames;
        case cmLuvData:
            return luvNames;
        case cmYCbCrData:
            return ycbcrNames;
        case cmYxyData:
            return yxyNames;
        case cmRGBData:
        case cmSRGBData:
            return rgbNames;
        case cmGrayData:
            return grayNames;
        case cmHSVData:
            return hsvNames;
        case cmHLSData:
            return hlsNames;
        case cmCMYKData:
            return cmykNames;
        case cmCMYData:
            return xyzNames;
        case cmNamedData:
            return nameNames;
    }
    
    int componentCount;
    
    if ((inputColorSpace & 0xFFFFFFF0) == 'MCH0') {
        componentCount = inputColorSpace & 0x0F;
    } else if ((inputColorSpace & 0xF0FFFFFF) == '0CLR') {
        componentCount = ( inputColorSpace & 0x0F000000 ) >> 24;
    } else if ((inputColorSpace & 0xF8FFFFFF) == '@CLR') {
        componentCount = (( inputColorSpace & 0x07000000 ) >> 24) + 9;
    } else {
        return nil;
    }

    NSString *parts[componentCount];
    int part;
    NSArray *result;
    
    for(part = 0; part < componentCount; part++)
        parts[part] = [[NSString alloc] initWithFormat:@"c%d", part+1];
        
    result = [NSArray arrayWithObjects:parts count:componentCount];

    for(part = 0; part < componentCount; part++)
        [parts[part] release];
    
    return result;
}

BOOL OAConvertCMColorToComponents(CMColor color, OSType space, float *c)
{
    
#define TRIPLET(scale, c0, c1, c2) c[0] = ((float)(color . c0) / (float)(scale)); c[1] = ((float)(color . c1) / (float)(scale)); c[2] = ((float)(color . c2) / (float)(scale)); 
    
    switch(space) {
        case cmRGBData:
        case cmSRGBData:
            TRIPLET(65535, rgb.red, rgb.blue, rgb.green);
            return YES;
            
        case cmHSVData:
            TRIPLET(65535, hsv.hue, hsv.saturation, hsv.value);
            return YES;
            
        case cmHLSData:
            TRIPLET(65535, hls.hue, hls.lightness, hls.saturation);
            return YES;
            
        case cmXYZData:
            TRIPLET(0x8000, XYZ.X, XYZ.Y, XYZ.Z);
            return YES;
            
        case cmLabData:
            c[0] = (float)(color.Lab.L) / 655.35;
            c[1] = (float)(color.Lab.a) / 65535 - 128;
            c[2] = (float)(color.Lab.b) / 65535 - 128;
            return YES;
            
        case cmLuvData:
            c[0] = (float)(color.Luv.L) / 655.35;
            c[1] = (float)(color.Luv.u) / 65535 - 128;
            c[2] = (float)(color.Luv.v) / 65535 - 128;
            return YES;
            
        case cmYxyData:
            TRIPLET(65535, Yxy.capY, Yxy.x, Yxy.y);
            return YES;
            
        case cmCMYKData:
            c[3] = (float)(color.cmyk.black) / 65535;
        case cmCMYData:
            TRIPLET(65535, cmy.cyan, cmy.magenta, cmy.yellow);
            return YES;
            
        case cmGrayData:
            c[0] = (float)(color.gray.gray) / 65535;
            return YES;
            
        // Unclear what the conversion from the CMMultichannelNColor representation to the float[] representation is.
        case cmMCH5Data:
        case cmMCH6Data:
        case cmMCH7Data:
        case cmMCH8Data:
            
        default:
            return NO;
    }
}

static NSString *getProfileName(CMProfileRef p)
{
    // TODO: Attempt to get a non-localized name, if we can. We want the profile's name in some format we can use to look it up again later.
    
    CMError ok;
    CFStringRef desc;
    
    desc = NULL;
    ok = CMCopyProfileDescriptionString(p, &desc);
    if (ok != noErr)
        return nil;
    if (desc == NULL)
        return nil;
    
    return [(NSString *)desc autorelease];
}

+ newFromICCData:(NSData *)iccData cache:(NSMutableDictionary *)profileCache;
{
    CMProfileRef profileReference;
    CMProfileLocation from;
    OAColorSpace *result;
    CMError ok;
    
    if (!iccData || [iccData length] < 8)
        return nil;
    
    if (profileCache != nil) {
        NSData *checksum = [iccData md5Signature];
        id cachedProfile = [profileCache objectForKey:checksum];
        if (cachedProfile != nil)
            return cachedProfile;
    }
    
    bzero(&from, sizeof(from));
    from.locType = cmBufferBasedProfile;
    from.u.bufferLoc.buffer = [iccData bytes];
    from.u.bufferLoc.size = [iccData length];
    
    profileReference = NULL;
    ok = CMOpenProfile(&profileReference, &from);
    if (ok != noErr || profileReference == NULL) {
        [NSException raise:OAColorSyncException format:@"Unable to read color profile: CMOpenProfile returns %d", ok];
        return nil;
    }
    NS_DURING {
        result = [self newFromCMProfile:profileReference cache:profileCache];
    } NS_HANDLER {
        CMCloseProfile(profileReference);
        [localException raise];
    } NS_ENDHANDLER;
    
    CMCloseProfile(profileReference);
    
    return result;
}

+ newFromCMProfile:(CMProfileRef)cmProfile cache:(NSMutableDictionary *)profileCache;
{
    CMAppleProfileHeader header;
    CMError ok;
    OSType inputColorSpace;
    CGColorSpaceRef cgSpace;
    OAColorSpace *result;
    
    if (cmProfile == NULL)
        return nil;
    
    if (profileCache != nil) {
        CMProfileMD5 profileDigest;

        bzero(&profileDigest, sizeof(profileDigest));

        ok = CMGetProfileMD5(cmProfile, profileDigest);
        if (ok == noErr) {
            NSData *key = [[NSData alloc] initWithBytes:profileDigest length:sizeof(profileDigest)];
            id cachedProfile = [profileCache objectForKey:key];
            [key release];
            if (cachedProfile != nil)
                return cachedProfile;
        }
    }
    
    bzero(&header, sizeof(header));
    ok = CMGetProfileHeader(cmProfile, &header);
    if (ok != noErr) {
        [NSException raise:OAColorSyncException format:@"Unable to retrieve CMProfile header (%d)", ok];
        return nil;
    }
    
    if (header.cm1.applProfileVersion == 0x0100) {
        inputColorSpace = header.cm1.dataType;
    } else {
        inputColorSpace = header.cm2.dataColorSpace;
    }
    
    if (inputColorSpace == cmNamedData) {
        return [[[OADiscreteColorSpace alloc] initWithCMProfile:cmProfile cache:profileCache] autorelease];
    }
    
    cgSpace = CGColorSpaceCreateWithPlatformColorSpace(cmProfile);
    if (cgSpace == NULL)
        [NSException raise:OAColorSyncException format:@"Unable to create CGColorSpace from CMProfile"];
    
    result = [[OAContinuousColorSpace alloc] initWithCGColorSpace:cgSpace inputSpace:inputColorSpace name:getProfileName(cmProfile)];
    CGColorSpaceRelease(cgSpace);
    
    return [result autorelease];
}

// Init and dealloc

- (void)dealloc;
{
    [componentNames release];
    [spaceName release];
    [super dealloc];
}


// API

- (int)numberOfComponents;
{
    OBRequestConcreteImplementation(self, _cmd);
}

- (NSArray *)componentNames;
{
    return componentNames;
}

- (NSString *)name;
{
    return spaceName;
}

- (NSColor *)colorFromPropertyListRepresentation:(NSDictionary *)dict;
{
    OBRequestConcreteImplementation(self, _cmd);
}

- (NSColor *)colorFromCMColor:(CMColor)aColor;
{
    OBRequestConcreteImplementation(self, _cmd);
}

- (OSType)colorSpaceType;
{
    OBRequestConcreteImplementation(self, _cmd);
}

- (NSString *)colorSpaceName
{
    switch([self colorSpaceType]) {
        case cmRGBData:
        case cmSRGBData:
            return NSCalibratedRGBColorSpace;
        case cmGrayData:
            return NSCalibratedWhiteColorSpace;
        case cmCMYKData:
        case cmCMYData:
            return NSDeviceCMYKColorSpace;
        case cmNamedData:
            return NSNamedColorSpace;
        default:
            return NSCustomColorSpace;
    }
}

@end

@implementation OAContinuousColorSpace

// Init and dealloc

- initWithCGColorSpace:(CGColorSpaceRef)colorSpace inputSpace:(OSType)inputSpace name:(NSString *)name;
{
    if ([super init] == nil)
        return nil;
    
    OBASSERT(colorSpace != NULL);
    OBASSERT(CFGetTypeID(colorSpace) == CGColorSpaceGetTypeID());
    
    cgColorSpace = colorSpace;
    CGColorSpaceRetain(cgColorSpace);
    
    if (inputSpace == 0)
        componentNames = nil;
    else
        componentNames = [componentNamesForColorSpace(inputSpace) retain];
    
    if (componentNames != nil) {
        OBASSERT([componentNames count] == [self numberOfComponents]);
    }
    
    if (name == nil)
        spaceName = [[NSString alloc] initWithFormat:@"<CGColorSpace %p>", cgColorSpace];
    else
        spaceName = [name copy];
    
    geom = inputSpace;
    
    return self;
}

- (void)dealloc;
{
    if (cgColorSpace != NULL)
        CGColorSpaceRelease(cgColorSpace);
    [super dealloc];
}

- (int)numberOfComponents;
{
    return CGColorSpaceGetNumberOfComponents(cgColorSpace);
}

- (NSColor *)colorWithComponents:(const float *)components;
{
    OACGColorSpaceColor *result = [(OACGColorSpaceColor *)NSAllocateObject([OACGColorSpaceColor class], sizeof(float) * [self numberOfComponents], NULL) initWithComponents:components space:self];
    return [result autorelease];
}

- (NSColor *)colorFromPropertyListRepresentation:(NSDictionary *)dict;
{
    int componentCount = [self numberOfComponents], componentIndex;
    float components[componentCount];
    
    if (componentNames == nil)
        return nil;
    
    OBINVARIANT([componentNames count] == componentCount);
    
    for(componentIndex = 0; componentIndex < componentCount; componentIndex ++) {
        components[componentIndex] = [dict floatForKey:[componentNames objectAtIndex:componentIndex] defaultValue:1.0];
    }
    
    return [self colorWithComponents:components];
}

- (void)setColorWithComponents:(const float *)components;
{
    CGContextRef currentContext = [[NSGraphicsContext currentContext] graphicsPort];
    
    CGContextSetFillColorSpace(currentContext, cgColorSpace);
    CGContextSetStrokeColorSpace(currentContext, cgColorSpace);
    
    if (components != NULL) {
        CGContextSetFillColor(currentContext, components);
        CGContextSetStrokeColor(currentContext, components);
    }
}

- (NSColor *)colorFromCMColor:(CMColor)aColor;
{
    float c[15];
    
    if (!OAConvertCMColorToComponents(aColor, geom, c))
        return nil;
    
    return [self colorWithComponents:c];
}

- (OSType)colorSpaceType;
{
    return geom;
}

@end

@implementation OACGColorSpaceColor

- initWithComponents:(const float *)someComponents space:(OAColorSpace *)someColorSpace
{
    [super init];
    space = [someColorSpace retain];
    memcpy(components, someComponents, sizeof(*someComponents) * [space numberOfComponents]);
    return self;
}

- (void)dealloc
{
    [space release];
    [super dealloc];
}

- (NSString *)colorSpaceName
{
    return [space colorSpaceName];
}

- (void)set
{
    [space setColorWithComponents:components];
}

- (float)redComponent           { return [self componentNamed:@"r"]; }
- (float)greenComponent         { return [self componentNamed:@"g"]; }
- (float)blueComponent          { return [self componentNamed:@"b"]; }
- (float)hueComponent           { return [self componentNamed:@"h"]; }
- (float)saturationComponent    { return [self componentNamed:@"s"]; }
- (float)brightnessComponent    { return [self componentNamed:@"v"]; }
- (float)whiteComponent         { return [self componentNamed:@"w"]; }
- (float)cyanComponent          { return [self componentNamed:@"c"]; }
- (float)magentaComponent       { return [self componentNamed:@"m"]; }
- (float)yellowComponent        { return [self componentNamed:@"y"]; }
- (float)blackComponent         { return [self componentNamed:@"k"]; }

- (float)componentNamed:(NSString *)componentName;
{
    NSArray *names = [space componentNames];
    if (names) {
        unsigned nameIndex = [names indexOfObject:componentName];
        if (nameIndex != NSNotFound)
            return components[nameIndex];
    }
    
    [NSException raise:NSInvalidArgumentException format:@"*** Color component \"%@\" is not defined for colorspace %@", componentName, space];
    return -1;
}

- (NSMutableDictionary *)propertyListRepresentation;
{
    NSMutableDictionary *dict;
    id colorSpaceRepresentation;
    NSArray *componentNames;
    unsigned int componentCount = [space numberOfComponents], componentIndex;
    BOOL hasAlpha = NO;
    
    colorSpaceRepresentation = [space propertyListRepresentation];
    
    dict = [NSMutableDictionary dictionary];
    if (colorSpaceRepresentation != nil)
        [dict setObject:colorSpaceRepresentation forKey:@"space"];
    
    componentNames = [space componentNames];
    for(componentIndex = 0; componentIndex < componentCount; componentIndex ++) {
        if (componentNames)
            [dict setFloatValue:components[componentIndex] forKey:[componentNames objectAtIndex:componentIndex]];
        else
            [dict setFloatValue:components[componentIndex] forKey:[NSString stringWithFormat:@"c%d", componentIndex+1]];
    }
    
    float alpha = [self alphaComponent];
    if (alpha != 1.0)
        [dict setFloatValue:alpha forKey:@"a"];

    return dict;
}

- (void)encodeWithCoder:(NSCoder *)aCoder;
{
    [aCoder encodeObject:space];
    [aCoder encodeArrayOfObjCType:@encode(float) count:[space numberOfComponents] at:components];
}

- (id)initWithCoder:(NSCoder *)aCoder
{
    [self release];
    
    OAContinuousColorSpace *decodedSpace = [aCoder decodeObject];
    float *decodedComponents = alloca(sizeof(*decodedComponents) * [decodedSpace numberOfComponents]);
    [aCoder decodeArrayOfObjCType:@encode(float) count:[decodedSpace numberOfComponents] at:decodedComponents];
    
    return [[decodedSpace colorWithComponents:decodedComponents] retain];
}

@end

@implementation OADiscreteColorSpace

- initWithCMProfile:(CMProfileRef)colorTable cache:(NSMutableDictionary *)profileCache
{
    CMError ok;
    UInt32 devChannels, count;
    OSType devSpace, connSpace;
    unsigned char descPrefix[256], descSuffix[256];  // Pascal strings are at most 255 bytes + length byte
    CMProfileRef connProfile;
    
    if (![super init])
        return nil;
    
    cmColorSpace = colorTable;
    if (CMCloneProfileRef(cmColorSpace) != noErr) {
        cmColorSpace = NULL;
        [self release];
        return nil;
    }
    
    ok = CMGetNamedColorInfo(cmColorSpace, &devChannels, &devSpace, &connSpace, &count, descPrefix, descSuffix);
    if (ok != noErr) {
        [self release];
        return nil;
    }
    
    colorCount = count;
    
    connProfile = NULL;
    ok = CMGetDefaultProfileBySpace(connSpace, &connProfile);
    if (ok != noErr || connProfile == NULL) {
        [self release];
        return nil;
    }
    
    NS_DURING {
        connectionSpace = [[self class] newFromCMProfile:connProfile cache:profileCache];
    } NS_HANDLER {
        CMCloseProfile(connProfile);
        connectionSpace = nil;
        [self release];
        [localException raise];
    } NS_ENDHANDLER;
    [connectionSpace retain];
    CMCloseProfile(connProfile);
    
    descriptionPrefix = CFStringCreateWithPascalString(kCFAllocatorDefault, descPrefix, CFStringGetSystemEncoding());
    descriptionSuffix = CFStringCreateWithPascalString(kCFAllocatorDefault, descSuffix, CFStringGetSystemEncoding());
    
    return self;
}

- (void)dealloc
{
    if (descriptionSuffix) CFRelease(descriptionSuffix);
    if (descriptionPrefix) CFRelease(descriptionPrefix);
    
    [connectionSpace release];
    
    if (cmColorSpace != NULL) CMCloseProfile(cmColorSpace);
    
    [super dealloc];
}

// - (void)setCachesColors:(BOOL)shouldMaintainCache;

- (NSColor *)colorWithName:(NSString *)colorName;
{
    CMError ok;
    CMColor devColor, connColor;
    Str255 pascalColorName;
    UInt32 colorIndex;
    NSColor *connectedColor;
    
    if (!colorName)
        return nil;
    
    if (!CFStringGetPascalString((CFStringRef)colorName, pascalColorName, 256, CFStringGetSystemEncoding()))
        return nil;
    
    ok = CMGetNamedColorValue(cmColorSpace, pascalColorName, &devColor, &connColor);
    if (ok != noErr) {
        if (ok != cmIndexRangeErr && ok != cmNamedColorNotFound)
            [NSException raise:OAColorSyncException format:@"*** %@: Unable to retrieve color %u: CMGetIndNamedColorValue returns %d", [self shortDescription], colorIndex, ok];
        return nil;
    }
    
    connectedColor = [connectionSpace colorFromCMColor:connColor];
    if (!connectedColor)
        return nil;
    
    ok = CMGetNamedColorIndex(cmColorSpace, pascalColorName, &colorIndex);
    if (ok != noErr)
        colorIndex = 0;  // CM color indices start at 1, so this is an invalid index
    
    return [[[OAIndexedColor alloc] initWithColor:connectedColor index:colorIndex name:colorName space:self] autorelease];
}

- (NSColor *)colorWithIndex:(unsigned int)colorIndex;
{
    CMError ok;
    unsigned char colorNameBuffer[256];  // A Pascal string
    CFStringRef colorName;
    CMColor devColor, connColor;
    NSColor *connectedColor;
    
    ok = CMGetIndNamedColorValue(cmColorSpace, colorIndex, &devColor, &connColor);
    if (ok != noErr) {
        if (ok != cmIndexRangeErr)
            [NSException raise:OAColorSyncException format:@"*** %@: Unable to retrieve color %u: CMGetIndNamedColorValue returns %d", [self shortDescription], colorIndex, ok];
        return nil;
    }

    connectedColor = [connectionSpace colorFromCMColor:connColor];
    if (!connectedColor)
        return nil;
    
    ok = CMGetNamedColorName(cmColorSpace, colorIndex, colorNameBuffer);
    if (ok == noErr) {
        colorName = CFStringCreateWithPascalString(kCFAllocatorDefault, colorNameBuffer, CFStringGetSystemEncoding());
        if (CFStringGetLength(colorName) == 0) {
            CFRelease(colorName);
            colorName = NULL;
        }
    }
    
    OAIndexedColor *result = [[OAIndexedColor alloc] initWithColor:connectedColor index:colorIndex name:(NSString *)colorName space:self];
    
    if (colorName)
        CFRelease(colorName);
    
    return [result autorelease];
}

- (NSArray *)colorNames;
{
    CFStringRef *names;
    unsigned int aColorIndex, colorNameCount;
    
    names = malloc(sizeof(*names) * colorCount);
    colorNameCount = 0;
    for(aColorIndex = 1; aColorIndex <= colorCount; aColorIndex ++) {
        CMError ok;
        unsigned char colorNameBuffer[256];
        
        ok = CMGetNamedColorName(cmColorSpace, aColorIndex, colorNameBuffer);
        if (ok == noErr && colorNameBuffer[0] != 0) {
            names[colorNameCount++] = CFStringCreateWithPascalString(kCFAllocatorDefault, colorNameBuffer, CFStringGetSystemEncoding());
        }
    }
    
    NSArray *result = [NSArray arrayWithObjects:(id *)names count:colorNameCount];
    
    for(aColorIndex = 0; aColorIndex < colorNameCount; aColorIndex ++)
        CFRelease(names[aColorIndex]);
    free(names);

    return result;
}

- (NSColor *)colorFromCMColor:(CMColor)aColor;
{
    return [self colorWithIndex:aColor.namedColor.namedColorIndex];
}

- (OSType)colorSpaceType;
{
    return cmNamedData;
}


@end

@implementation OAIndexedColor

- initWithColor:(NSColor *)aColor index:(unsigned int)anIndex name:(NSString *)aName space:(OADiscreteColorSpace *)aSpace;
{
    [super init];
    
    colorName = [aName copy];
    colorIndex = anIndex;
    colorValue = [aColor retain];
    space = [aSpace retain];
    
    return self;
}

- (void)dealloc
{
    [space release];
    [colorName release];
    [colorValue release];
    [super dealloc];
}

- (NSString *)colorSpaceName
{
    return NSNamedColorSpace;
}

- (void)set
{
    [colorValue set];
}

- (NSColor *)colorUsingColorSpaceName:(NSString *)colorSpace device:(NSDictionary *)deviceDescription;
{
    return [colorValue colorUsingColorSpaceName:colorSpace device:deviceDescription];
}

- (NSColor *)colorWithAlphaComponent:(float)alpha;
{
    NSColor *result = [super colorWithAlphaComponent:alpha];
    if (result)
        return result;
    else
        return [colorValue colorWithAlphaComponent:alpha];
}

- (NSString *)catalogNameComponent;
{
    return [space name];
}

- (NSString *)colorNameComponent;
{
    return colorName;
}

#if 0
- (NSString *)localizedCatalogNameComponent;
- (NSString *)localizedColorNameComponent;
#endif

- (NSMutableDictionary *)propertyListRepresentation;
{
    NSMutableDictionary *dict;
    id colorSpaceRepresentation;
    
    colorSpaceRepresentation = [space propertyListRepresentation];
    
    dict = [NSMutableDictionary dictionary];
    if (colorSpaceRepresentation != nil)
        [dict setObject:colorSpaceRepresentation forKey:@"space"];
    
    if (colorName)
        [dict setObject:colorName forKey:@"name"];
    else if (colorIndex != 0)
        [dict setIntValue:colorIndex forKey:@"index"];
    
    return dict;
}

- (void)encodeWithCoder:(NSCoder *)aCoder;
{
    [aCoder encodeObject:space];
    [aCoder encodeValueOfObjCType:@encode(unsigned int) at:&colorIndex];
}

- (id)initWithCoder:(NSCoder *)aCoder
{
    unsigned int decodedIndex;
    
    [self release];
    
    OADiscreteColorSpace *decodedSpace = [aCoder decodeObject];
    [aCoder decodeValueOfObjCType:@encode(unsigned int) at:&decodedIndex];
    
    return [[decodedSpace colorWithIndex:decodedIndex] retain];
}

@end

NSString * const OAColorSyncException = @"OAColorSyncException";

