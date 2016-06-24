// Copyright 2003-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/NSColor-ColorSyncExtensions.h>
#import <OmniAppKit/OAColorProfile.h>
#import <OmniAppKit/NSImage-ColorSyncExtensions.h>

#import <OmniAppKit/OAFeatures.h>
#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>

RCS_ID("$Id$");

@implementation NSColor (ColorSyncExtensions)

static void (*originalPatternImp)(NSColor *color, SEL _cmd);
static void (*originalCalibratedRGBImp)(NSColor *color, SEL _cmd);
static void (*originalCalibratedGrayImp)(NSColor *color, SEL _cmd);
static void (*originalDeviceRGBImp)(NSColor *color, SEL _cmd);
static void (*originalDeviceGrayImp)(NSColor *color, SEL _cmd);
static void (*originalDeviceCMYKImp)(NSColor *color, SEL _cmd);

+ (void)performPosing;
{
    originalPatternImp = (typeof(originalPatternImp))OBReplaceMethodImplementationWithSelectorOnClass(NSClassFromString(@"NSPatternColor"), @selector(set), self, @selector(_setPattern));
    originalCalibratedRGBImp = (typeof(originalCalibratedRGBImp))OBReplaceMethodImplementationWithSelectorOnClass(NSClassFromString(@"NSCalibratedRGBColor"), @selector(set), self, @selector(_setCalibratedRGB));
    originalCalibratedGrayImp = (typeof(originalCalibratedGrayImp))OBReplaceMethodImplementationWithSelectorOnClass(NSClassFromString(@"NSCalibratedWhiteColor"), @selector(set), self, @selector(_setCalibratedGray));
    originalDeviceRGBImp = (typeof(originalDeviceRGBImp))OBReplaceMethodImplementationWithSelectorOnClass(NSClassFromString(@"NSDeviceRGBColor"), @selector(set), self, @selector(_setDeviceRGB));
    originalDeviceGrayImp = (typeof(originalDeviceGrayImp))OBReplaceMethodImplementationWithSelectorOnClass(NSClassFromString(@"NSDeviceWhiteColor"), @selector(set), self, @selector(_setDeviceGray));
    originalDeviceCMYKImp = (typeof(originalDeviceCMYKImp))OBReplaceMethodImplementationWithSelectorOnClass(NSClassFromString(@"NSDeviceCMYKColor"), @selector(set), self, @selector(_setDeviceCMYK));
}

- (void)setCoreGraphicsRGBValues;
{
    CGFloat components[4];
    CGContextRef contextRef;
    
    components[0] = [self redComponent];
    components[1] = [self greenComponent];
    components[2] = [self blueComponent];
    components[3] = [self alphaComponent];
        
    contextRef = [[NSGraphicsContext currentContext] graphicsPort];
    CGContextSetFillColor(contextRef, components);
    CGContextSetStrokeColor(contextRef, components);
}

- (void)setCoreGraphicsCMYKValues;
{
    CGFloat components[5];
    CGContextRef contextRef;
    
    components[0] = [self cyanComponent];
    components[1] = [self magentaComponent];
    components[2] = [self yellowComponent];
    components[3] = [self blackComponent];
    components[4] = [self alphaComponent];
        
    contextRef = [[NSGraphicsContext currentContext] graphicsPort];
    CGContextSetFillColor(contextRef, components);
    CGContextSetStrokeColor(contextRef, components);
}

- (void)setCoreGraphicsGrayValues;
{
    CGFloat components[2];
    CGContextRef contextRef;
    
    components[0] = [self whiteComponent];
    components[1] = [self alphaComponent];
        
    contextRef = [[NSGraphicsContext currentContext] graphicsPort];
    CGContextSetFillColor(contextRef, components);
    CGContextSetStrokeColor(contextRef, components);
}

- (void)_setPattern;
{
    OAColorProfile *profile;
    
    if ((profile = [OAColorProfile currentProfile])) {
        NSImage *newImage = [[NSImage alloc] initWithData:[[self patternImage] TIFFRepresentation]];

        [newImage convertFromProfile:profile toProfile:[OAColorProfile defaultDisplayProfile]];
        NSColor *convertedPatternColor = [NSColor colorWithPatternImage:newImage];
        originalPatternImp(convertedPatternColor, @selector(set));
    } else
        originalPatternImp(self, @selector(set));
}

- (void)_setCalibratedRGB;
{
    OAColorProfile *profile;
    
    if ((profile = [OAColorProfile currentProfile])) {
        if ([profile _hasRGBSpace])
            [profile _setRGBColor:self];
        else if ([profile _hasCMYKSpace])
            [profile _setCMYKColor:[self colorUsingColorSpaceName:NSDeviceCMYKColorSpace]];
        else
            [profile _setGrayColor:[self colorUsingColorSpaceName:NSDeviceWhiteColorSpace]];
    } else
        originalCalibratedRGBImp(self, @selector(set));
}

- (void)_setCalibratedGray;
{
    OAColorProfile *profile;
    
    if ((profile = [OAColorProfile currentProfile])) {
        if ([profile _hasGraySpace])
            [profile _setGrayColor:self];
        else if ([profile _hasRGBSpace])
            [profile _setRGBColor:[self colorUsingColorSpaceName:NSDeviceRGBColorSpace]];
        else
            [profile _setCMYKColor:[self colorUsingColorSpaceName:NSDeviceCMYKColorSpace]];
    } else
        originalCalibratedGrayImp(self, @selector(set));
}

- (void)_setDeviceRGB;
{
    OAColorProfile *profile;
    
    if ((profile = [OAColorProfile currentProfile])) {
        if ([profile _hasRGBSpace])
            [profile _setRGBColor:self];
        else if ([profile _hasCMYKSpace])
            [profile _setCMYKColor:[self colorUsingColorSpaceName:NSDeviceCMYKColorSpace]];
        else
            [profile _setGrayColor:[self colorUsingColorSpaceName:NSDeviceWhiteColorSpace]];
    } else
        originalDeviceRGBImp(self, @selector(set));
}

- (void)_setDeviceGray;
{
    OAColorProfile *profile;
    
    if ((profile = [OAColorProfile currentProfile])) {
        if ([profile _hasGraySpace])
            [profile _setGrayColor:self];
        else if ([profile _hasRGBSpace])
            [profile _setRGBColor:[self colorUsingColorSpaceName:NSDeviceRGBColorSpace]];
        else
            [profile _setCMYKColor:[self colorUsingColorSpaceName:NSDeviceCMYKColorSpace]];
    } else
        originalDeviceGrayImp(self, @selector(set));
}

- (void)_setDeviceCMYK;
{
    OAColorProfile *profile;
    
    if ((profile = [OAColorProfile currentProfile])) {
        if ([profile _hasCMYKSpace])
            [profile _setCMYKColor:self];
        else if ([profile _hasRGBSpace])
            [profile _setRGBColor:[self colorUsingColorSpaceName:NSDeviceRGBColorSpace]];
        else
            [profile _setGrayColor:[self colorUsingColorSpaceName:NSDeviceWhiteColorSpace]];
    } else
        originalDeviceCMYKImp(self, @selector(set));
}

- (NSColor *)_rgbConvertUsingColorWorld:(ColorSyncTransformRef)colorWorldRef;
{
    if (colorWorldRef == NULL)
        return self;

    float colorFrom[3] = {self.redComponent, self.greenComponent, self.blueComponent};
    float colorTo[3];
    
    BOOL success = ColorSyncTransformConvert(colorWorldRef, 1, 1, colorTo, kColorSync32BitFloat, kColorSyncByteOrderDefault | kColorSyncAlphaNone, sizeof(colorTo), colorFrom, kColorSync32BitFloat, kColorSyncByteOrderDefault | kColorSyncAlphaNone, sizeof(colorFrom), NULL);
    
    if (!success) {
        return self;
    } else {
        return [NSColor colorWithDeviceRed:colorTo[0] green:colorTo[1] blue:colorTo[2] alpha:[self alphaComponent]];
    }
}

- (NSColor *)_cmykConvertUsingColorWorld:(ColorSyncTransformRef)colorWorldRef intoRGB:(BOOL)intoRGB;
{
    if (colorWorldRef == NULL)
        return self;
    
    float colorFrom[4] = {self.cyanComponent, self.magentaComponent, self.yellowComponent, self.blackComponent};

    if (intoRGB) {
        float colorTo[3];
        BOOL success = ColorSyncTransformConvert(colorWorldRef, 1, 1, colorTo, kColorSync32BitFloat, kColorSyncByteOrderDefault | kColorSyncAlphaNone, sizeof(colorTo), colorFrom, kColorSync32BitFloat, kColorSyncByteOrderDefault | kColorSyncAlphaNone, sizeof(colorFrom), NULL);

        if (success) {
            return [NSColor colorWithDeviceRed:colorTo[0] green:colorTo[1] blue:colorTo[2] alpha:[self alphaComponent]];
        } else {
            return [self colorUsingColorSpaceName:NSDeviceRGBColorSpace];
        }
    } else {
        float colorTo[4];
        
        BOOL success = ColorSyncTransformConvert(colorWorldRef, 1, 1, colorTo, kColorSync32BitFloat, kColorSyncByteOrderDefault | kColorSyncAlphaNone, sizeof(colorTo), colorFrom, kColorSync32BitFloat, kColorSyncByteOrderDefault | kColorSyncAlphaNone, sizeof(colorFrom), NULL);

        if (success) {
            return [NSColor colorWithDeviceCyan:colorTo[0] magenta:colorTo[1] yellow:colorTo[2] black:colorTo[3] alpha:self.alphaComponent];
        } else {
            return self;
        }
    }
}

- (NSColor *)_grayConvertUsingColorWorld:(ColorSyncTransformRef)colorWorldRef intoRGB:(BOOL)intoRGB;
{
    if (colorWorldRef == NULL)
        return self;
    
    float colorFrom[1] = {self.whiteComponent};

    if (intoRGB) {
        float colorTo[3];
        BOOL success = ColorSyncTransformConvert(colorWorldRef, 1, 1, colorTo, kColorSync32BitFloat, kColorSyncByteOrderDefault | kColorSyncAlphaNone, sizeof(colorTo), colorFrom, kColorSync32BitFloat, kColorSyncByteOrderDefault | kColorSyncAlphaNone, sizeof(colorFrom), NULL);
        
        if (success) {
            return [NSColor colorWithDeviceRed:colorTo[0] green:colorTo[1] blue:colorTo[2] alpha:[self alphaComponent]];
        } else {
            return [self colorUsingColorSpaceName:NSDeviceRGBColorSpace];
        }
    } else {
        float colorTo[1];
        BOOL success = ColorSyncTransformConvert(colorWorldRef, 1, 1, colorTo, kColorSync32BitFloat, kColorSyncByteOrderDefault | kColorSyncAlphaNone, sizeof(colorTo), colorFrom, kColorSync32BitFloat, kColorSyncByteOrderDefault | kColorSyncAlphaNone, sizeof(colorFrom), NULL);
        
        if (success) {
            return [NSColor colorWithDeviceWhite:colorTo[0] alpha:self.alphaComponent];
        } else {
            return self;
        }
    }
}

- (NSColor *)convertFromProfile:(OAColorProfile *)inProfile toProfile:(OAColorProfile *)outProfile;
{
    NSString *colorSpaceName;
        
    colorSpaceName = [self colorSpaceName];
    if (colorSpaceName == NSPatternColorSpace) {
        ColorSyncTransformRef world = [inProfile _rgbConversionWorldForOutput:outProfile];
        NSImage *newImage;
        NSColor *result;
        
        if (!world)
            return self;
            
        newImage = [[self patternImage] copy];
        [newImage convertFromProfile:inProfile toProfile:outProfile];
        result = [NSColor colorWithPatternImage:newImage];
        OB_RELEASE(newImage);
        return result;
    } else if (colorSpaceName == NSDeviceCMYKColorSpace) {
        return [self _cmykConvertUsingColorWorld:[inProfile _cmykConversionWorldForOutput:outProfile] intoRGB:![outProfile _hasCMYKSpace]];
    } else if (colorSpaceName == NSDeviceWhiteColorSpace || colorSpaceName == NSCalibratedWhiteColorSpace) {
        return [self _grayConvertUsingColorWorld:[inProfile _grayConversionWorldForOutput:outProfile] intoRGB:![outProfile _hasGraySpace]];
    } else {
        ColorSyncTransformRef world = [inProfile _rgbConversionWorldForOutput:outProfile];
        
        if (!world)
            return self;
        if (colorSpaceName == NSDeviceRGBColorSpace || colorSpaceName == NSCalibratedRGBColorSpace)
            return [self _rgbConvertUsingColorWorld:world];
        else
            return [[self colorUsingColorSpaceName:NSDeviceRGBColorSpace] _rgbConvertUsingColorWorld:world];
    }
}

@end

