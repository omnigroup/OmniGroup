// Copyright 2000-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "NSColor-OAExtensions.h"

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

#import "OAColorProfile.h"
#import "NSImage-OAExtensions.h"

RCS_ID("$Id$")

NSString * const OAColorXMLAdditionalColorSpace = @"OAColorXMLAdditionalColorSpace";

static NSColorList *classicCrayonsColorList(void)
{
    static NSColorList *classicCrayonsColorList = nil;
    
    if (classicCrayonsColorList == nil) {
	NSString *colorListName = NSLocalizedStringFromTableInBundle(@"Classic Crayons", @"OmniAppKit", OMNI_BUNDLE, "color list name");
	classicCrayonsColorList = [[NSColorList alloc] initWithName:colorListName fromFile:[OMNI_BUNDLE pathForResource:@"Classic Crayons" ofType:@"clr"]];
    }
    return classicCrayonsColorList;
}

@interface NSColorPicker (Private)
- (void)attachColorList:(id)list makeSelected:(BOOL)flag;
- (void)refreashUI; // sic
@end

// Adding a color list to the color panel when it is NOT in list mode, will not to anything.  Radar #4341924.
@implementation NSColorPanel (OAHacks)
static void (*originalSwitchToPicker)(id self, SEL _cmd, NSColorPicker *picker);
+ (void)performPosing;
{
    // No public API for this
    if ([self instancesRespondToSelector:@selector(_switchToPicker:)])
	originalSwitchToPicker = (typeof(originalSwitchToPicker))OBReplaceMethodImplementationWithSelector(self, @selector(_switchToPicker:), @selector(_replacement_switchToPicker:));
}
- (void)_replacement_switchToPicker:(NSColorPicker *)picker;
{
    originalSwitchToPicker(self, _cmd, picker);

    static BOOL attached = NO;
    if (!attached && [NSStringFromClass([picker class]) isEqual:@"NSColorPickerPageableNameList"]) {
	attached = YES;
	
	// Look at the (private) preference for which color list to have selected.  If it is the one we are adding, use -attachColorList: (which will select it).  Otherwise, use the (private) -attachColorList:makeSelected: and specify to not select it (otherwise the color list selected when the real code sets up and reads the default will be overridden).  If we fail to select the color list we are adding, though, the picker will show an empty color list (since the real code will have tried to select it before it is added).  Pheh.  See <bug://30338> for some of these issues.  Logged Radar 4640063 to add for asks for -attachColorList:makeSelected: to be public.

	// Sadly, the (private) preference encodes the color list name with a '1' at the beginning.  I have no idea what this is for.  I'm uncomfortable using [defaultColorList hasSuffix:[colorList name]] below since that might match more than one color list.
	NSString *defaultColorList = [[NSUserDefaults standardUserDefaults] stringForKey:@"NSColorPickerPageableNameListDefaults"];
	if ([defaultColorList hasPrefix:@"1"])
	    defaultColorList = [defaultColorList substringFromIndex:1];
	
	NSColorList *colorList = classicCrayonsColorList();
	if ([picker respondsToSelector:@selector(attachColorList:makeSelected:)]) {
	    BOOL select = OFISEQUAL(defaultColorList, [colorList name]);

	    [picker attachColorList:colorList makeSelected:select];
	    if (select && [picker respondsToSelector:@selector(refreashUI)])
		// The picker is in a bad state from trying to select a color list that wasn't there when -restoreDefaults was called.  Passing makeSelected:YES will apparently bail since the picker things that color list is already selected and we'll be left with an empty list of colors displayed.  First, select some other color list if possible.
		[picker refreashUI];
	} else
	    [picker attachColorList:colorList];
    }
}
@end

@implementation NSColor (OAExtensions)

typedef struct {
    BOOL (*component)(void *container, NSString *key, CGFloat *outComponent); // Should only set the output if the key was present.  Returns YES if the key was present.
    NSString * (*string)(void *container, NSString *key);
    NSData * (*data)(void *container, NSString *key);
} OAColorGetters;

// Works for both NSString and NSNumber encoded components
static BOOL _dictionaryComponentGetter(void *container, NSString *key, CGFloat *outComponent)
{
    OBPRECONDITION([(id)container isKindOfClass:[NSMutableDictionary class]]);

    // In some cases we care if we got the default value due to it being missing or whether it was actually in the plist.
    id obj = [(NSMutableDictionary *)container objectForKey:key];
    if (!obj)
        return NO;
    *outComponent = [obj cgFloatValue];
    return YES;
}

static NSString *_dictionaryStringGetter(void *container, NSString *key)
{
    OBPRECONDITION([(id)container isKindOfClass:[NSMutableDictionary class]]);
    NSString *result = [(NSMutableDictionary *)container objectForKey:key];
    OBASSERT(!result || [result isKindOfClass:[NSString class]]);
    return result;
}

static NSData *_dictionaryDataGetter(void *container, NSString *key)
{
    OBPRECONDITION([(id)container isKindOfClass:[NSMutableDictionary class]]);
    NSData *result = [(NSMutableDictionary *)container objectForKey:key];
    OBASSERT(!result || [result isKindOfClass:[NSData class]]);
    return result;
}

+ (NSColor *)_colorFromContainer:(void *)container getters:(OAColorGetters)getters;
{
    NSData *data = getters.data(container, @"archive");
    if (data) {
        if ([data isKindOfClass:[NSData class]] && [data length] > 0) {
            NSColor *unarchived = [NSKeyedUnarchiver unarchiveObjectWithData:data];
            if ([unarchived isKindOfClass:[NSColor class]])
                return unarchived;
        }
        
        // otherwise, fallback -- might be a rgb color in the plist too.
    }
    
    CGFloat alpha = 1.0;
    getters.component(container, @"a", &alpha);

    CGFloat v0;
    if (getters.component(container, @"w", &v0))
        return [NSColor colorWithCalibratedWhite:v0 alpha:alpha];
    
    NSString *catalog = getters.string(container, @"catalog");
    if (catalog) {
        NSString *name = getters.string(container, @"name");
        if ([catalog isKindOfClass:[NSString class]] && [name isKindOfClass:[NSString class]]) {
            NSColor *color = [NSColor colorWithCatalogName:catalog colorName:name];
            if (color)
                return color;
        }
        
        // otherwise, fallback -- might be a rgb color in the plist too.
    }
    
    if (getters.component(container, @"r", &v0)) {
        CGFloat v1 = 0.0f, v2 = 0.0f;
        getters.component(container, @"g", &v1);
        getters.component(container, @"b", &v2);
        return [NSColor colorWithCalibratedRed:v0 green:v1 blue:v2 alpha:alpha];
    }
    
    if (getters.component(container, @"c", &v0)) {
        // No global name for the calibrated CMYK color space

        CGFloat components[5];
        components[0] = v0;
        getters.component(container, @"m", &components[1]);
        getters.component(container, @"y", &components[2]);
        getters.component(container, @"k", &components[3]);
        components[4] = alpha;
        
        return [NSColor colorWithColorSpace:[NSColorSpace genericCMYKColorSpace] components:components count:5];
    }
    
    // There is no HSB/HSV colorspace, but lets allow specifying colors in property lists (for defaults in Info.plist) that way
    if (getters.component(container, @"h", &v0)) {
        CGFloat v1 = 0.0f, v2 = 0.0f;
        getters.component(container, @"s", &v1);
        if (!getters.component(container, @"v", &v2))
            getters.component(container, @"b", &v2);
        
        return [NSColor colorWithCalibratedHue:v0 saturation:v1 brightness:v2 alpha:alpha];
    }
    
    NSData *patternData = getters.data(container, @"png");
    if (!patternData)
        patternData = getters.data(container, @"tiff");
    if ([patternData isKindOfClass:[NSData class]]) {
        NSBitmapImageRep *bitmapImageRep = (id)[NSBitmapImageRep imageRepWithData:patternData];
        NSSize imageSize = [bitmapImageRep size];
        if (bitmapImageRep == nil || NSEqualSizes(imageSize, NSZeroSize)) {
            NSLog(@"Warning, could not rebuild pattern color from image rep %@, data %@", bitmapImageRep, patternData);
        } else {
            NSImage *patternImage = [[NSImage alloc] initWithSize:imageSize];
            [patternImage addRepresentation:bitmapImageRep];
            return [NSColor colorWithPatternImage:[patternImage autorelease]];
        }
        
        // fall through
    }
    
#ifdef DEBUG
    NSLog(@"Unable to unarchive color from container %@.  Falling back to white.", container);
#endif
    return [NSColor whiteColor];
}

+ (NSColor *)colorFromPropertyListRepresentation:(NSDictionary *)dict;
{
    OAColorGetters getters = {
        .component = _dictionaryComponentGetter,
        .string = _dictionaryStringGetter,
        .data = _dictionaryDataGetter,
    };
    return [self _colorFromContainer:dict getters:getters];
}


typedef struct {
    void (*component)(id container, NSString *key, float component);
    void (*string)(id container, NSString *key, NSString *string);
    void (*data)(id container, NSString *key, NSData *data);
} OAColorAdders;

static void _dictionaryStringComponentAdder(id container, NSString *key, float component)
{
    OBPRECONDITION([container isKindOfClass:[NSMutableDictionary class]]);
    NSString *str = [[NSString alloc] initWithFormat:@"%g", component];
    [container setObject:str forKey:key];
    [str release];
}

static void _dictionaryNumberComponentAdder(id container, NSString *key, float component)
{
    OBPRECONDITION([container isKindOfClass:[NSMutableDictionary class]]);
    NSNumber *num = [[NSNumber alloc] initWithFloat:component];
    [container setObject:num forKey:key];
    [num release];
}

static void _dictionaryStringAdder(id container, NSString *key, NSString *string)
{
    OBPRECONDITION([container isKindOfClass:[NSMutableDictionary class]]);
    [container setObject:string forKey:key];
}

static void _dictionaryDataAdder(id container, NSString *key, NSData *data)
{
    OBPRECONDITION([container isKindOfClass:[NSMutableDictionary class]]);
    [container setObject:data forKey:key];
}


// Allow for including default values, particular for scripting so that users don't have to check for missing values
- (void)_addComponentsToContainer:(id)container adders:(OAColorAdders)adders omittingDefaultValues:(BOOL)omittingDefaultValues;
{
    BOOL hasAlpha = NO;
    
    NSString *colorSpaceName = [self colorSpaceName];
    NSColorSpace *colorSpace = nil;
    
    if (OFNOTEQUAL(colorSpaceName, NSPatternColorSpace) && OFNOTEQUAL(colorSpaceName, NSNamedColorSpace)) // This will raise if it is a pattern or catalog
        colorSpace = [self colorSpace];
    
    if ([colorSpaceName isEqualToString:NSCalibratedWhiteColorSpace] || [colorSpaceName isEqualToString:NSDeviceWhiteColorSpace]) {
        NSColor *calibratedColor = [self colorUsingColorSpaceName:NSCalibratedWhiteColorSpace]; // don't archive device colors if at all possible
        adders.component(container, @"w", [calibratedColor whiteComponent]);
        hasAlpha = YES;
    } else if ([colorSpaceName isEqualToString:NSCalibratedRGBColorSpace] || [colorSpaceName isEqualToString:NSDeviceRGBColorSpace]) {
        NSColor *calibratedColor = [self colorUsingColorSpaceName:NSCalibratedRGBColorSpace]; // don't archive device colors if at all possible
        adders.component(container, @"r", [calibratedColor redComponent]);
        adders.component(container, @"g", [calibratedColor greenComponent]);
        adders.component(container, @"b", [calibratedColor blueComponent]);
        hasAlpha = YES;
    } else if ([colorSpaceName isEqualToString:NSNamedColorSpace]) {
        adders.string(container, @"catalog", [self catalogNameComponent]);
        adders.string(container, @"name", [self colorNameComponent]);
    } else if (OFISEQUAL(colorSpace, [NSColorSpace genericCMYKColorSpace])) { // There is no global name for calibrated CMYK
        // The -{cyan,magenta,yellow,black}Component methods are only valid for RGB colors, intuitively.
        CGFloat components[5]; // Assuming that it'll write out alpha too.
        [self getComponents:components];

        adders.component(container, @"c", components[0]);
        adders.component(container, @"m", components[1]);
        adders.component(container, @"y", components[2]);
        adders.component(container, @"k", components[3]);
        hasAlpha = YES;
    } else if ([colorSpaceName isEqualToString:NSPatternColorSpace]) {
        adders.data(container, @"tiff", [[self patternImage] TIFFRepresentation]);
    } else {
        NSColor *rgbColor = [self colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
        if (rgbColor)
            [rgbColor _addComponentsToContainer:container adders:adders omittingDefaultValues:omittingDefaultValues];
        NSData *archive = [NSKeyedArchiver archivedDataWithRootObject:self];
        if (archive != nil && [archive length] > 0)
            adders.data(container, @"archive", archive);
        return;
    }
    if (hasAlpha) {
        float alpha = [self alphaComponent];
        if (alpha != 1.0 || !omittingDefaultValues)
            adders.component(container, @"a", alpha);
    }
}

- (NSMutableDictionary *)propertyListRepresentationWithStringComponentsOmittingDefaultValues:(BOOL)omittingDefaultValues;
{
    OAColorAdders adders = {
        .component = _dictionaryStringComponentAdder,
        .string = _dictionaryStringAdder,
        .data = _dictionaryDataAdder
    };
    NSMutableDictionary *plist = [NSMutableDictionary dictionary];
    [self _addComponentsToContainer:plist adders:adders omittingDefaultValues:omittingDefaultValues];
    return plist;
}

- (NSMutableDictionary *)propertyListRepresentationWithNumberComponentsOmittingDefaultValues:(BOOL)omittingDefaultValues;
{
    OAColorAdders adders = {
        .component = _dictionaryNumberComponentAdder,
        .string = _dictionaryStringAdder,
        .data = _dictionaryDataAdder
    };
    NSMutableDictionary *plist = [NSMutableDictionary dictionary];
    [self _addComponentsToContainer:plist adders:adders omittingDefaultValues:omittingDefaultValues];
    return plist;
}

// For backwards compatibility (these property lists can be stored in files), we return string components.
- (NSMutableDictionary *)propertyListRepresentation;
{
    return [self propertyListRepresentationWithStringComponentsOmittingDefaultValues:YES];
}

//

- (BOOL)isSimilarToColor:(NSColor *)color;
{
    NSString *colorSpace = [self colorSpaceName];

    if (!([colorSpace isEqualToString:[color colorSpaceName]])) {
        return NO;
    }

    if ([colorSpace isEqualToString:NSCalibratedWhiteColorSpace] || [colorSpace isEqualToString:NSDeviceWhiteColorSpace]) {
        return (fabs([self whiteComponent]-[color whiteComponent]) < 0.001) && (fabs([self alphaComponent]-[color alphaComponent]) < 0.001);

    } else if ([colorSpace isEqualToString:NSCalibratedRGBColorSpace] || [colorSpace isEqualToString:NSDeviceRGBColorSpace]) {
        return (fabs([self redComponent]-[color redComponent]) < 0.001) && (fabs([self greenComponent]-[color greenComponent]) < 0.001) && (fabs([self blueComponent]-[color blueComponent]) < 0.001) && (fabs([self alphaComponent]-[color alphaComponent]) < 0.001);

    } else if ([colorSpace isEqualToString:NSNamedColorSpace]) {
        return [[self catalogNameComponent] isEqualToString:[color catalogNameComponent]] && [[self colorNameComponent] isEqualToString:[color colorNameComponent]];

    } else if ([colorSpace isEqualToString:NSDeviceCMYKColorSpace]) {
        return (fabs([self cyanComponent]-[color cyanComponent]) < 0.001) && (fabs([self magentaComponent]-[color magentaComponent]) < 0.001) && (fabs([self yellowComponent]-[color yellowComponent]) < 0.001) && (fabs([self blackComponent]-[color blackComponent]) < 0.001) && (fabs([self alphaComponent]-[color alphaComponent]) < 0.001);

    } else if ([colorSpace isEqualToString:NSPatternColorSpace]) {
        return [[[self patternImage] TIFFRepresentation] isEqualToData:[[color patternImage] TIFFRepresentation]];
    }
    
    if ([color isEqual:self])  // works for CMYK colors, which have a NSCustomColorSpace
        return YES;
    
    return NO;
}


- (NSData *)patternImagePNGData;
{
    NSString *colorSpace = [self colorSpaceName];
    if (!([colorSpace isEqualToString:NSPatternColorSpace]))
        return nil;

    return [[self patternImage] pngData];
}

typedef struct {
    NSString *name; // easy name lookup
    CGFloat   h, s, v, a; // avoid conversions
    CGFloat   r, g, B;
    NSColor  *color; // in the original color space
} OANamedColorEntry;

static OANamedColorEntry *_addColorsFromList(OANamedColorEntry *colorEntries, unsigned int *entryCount, NSColorList *colorList)
{
    if (colorList == nil)
	return colorEntries;

    NSArray *allColorKeys = [colorList allKeys];
    unsigned int colorIndex, colorCount = [allColorKeys count];
    
    // Make room for the extra entries
    colorEntries = (OANamedColorEntry *)realloc(colorEntries, sizeof(*colorEntries)*(*entryCount + colorCount));
    
    for (colorIndex = 0; colorIndex < colorCount; colorIndex++) {
	NSString *colorKey = [allColorKeys objectAtIndex:colorIndex];
	NSColor *color = [colorList colorWithKey:colorKey];
	
	OANamedColorEntry *entry = &colorEntries[*entryCount + colorIndex];
	entry->name = [colorKey copy];
	
	NSColor *rgbColor = [color colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
	[rgbColor getHue:&entry->h saturation:&entry->s brightness:&entry->v alpha:&entry->a];
	[rgbColor getRed:&entry->r green:&entry->g blue:&entry->B alpha:&entry->a];
	
	entry->color = [color retain];
    }
    
    // Inform caller of new entry count, finally
    *entryCount += colorCount;
    return colorEntries;
}

static const OANamedColorEntry *_combinedColorEntries(unsigned int *outEntryCount)
{
    static OANamedColorEntry *entries = NULL;
    static unsigned int entryCount = 0;
    
    if (entries == NULL) {
	// Two built-in color lists that should get localized
        entries = _addColorsFromList(entries, &entryCount, [NSColorList colorListNamed:@"Apple"]);
        entries = _addColorsFromList(entries, &entryCount, [NSColorList colorListNamed:@"Crayons"]);
	
	// Load *our* color list last since it should be localized and has more colors than either of the above
	entries = _addColorsFromList(entries, &entryCount, classicCrayonsColorList());
    }
    
    *outEntryCount = entryCount;
    return entries;
}

static float _nearnessWithWrap(float a, float b)
{
    float value1 = 1.0 - a + b;
    float value2 = 1.0 - b + a;
    float value3 = a - b;
    return MIN(ABS(value1), MIN(ABS(value2), ABS(value3)));
}

static float _colorCloseness(const OANamedColorEntry *e1, const OANamedColorEntry *e2)
{
    // As saturation goes to zero, hue becomes irrelevant.  For example, black has h=0, but that doesn't mean it is "like" red.  So, we do the distance in RGB space.  But the modifier words in HSV.
    float sdiff = ABS(e1->s - e2->s);
    if (sdiff < 0.1 && e1->s < 0.1) {
	float rd = e1->r - e2->r;
	float gd = e1->g - e2->g;
	float bd = e1->B - e2->B;
	
	return sqrt(rd*rd + gd*gd + bd*bd);
    } else {
	// We weight the hue stronger than the saturation or brightness, since it's easier to talk about 'dark yellow' than it is 'yellow except for with a little red in it'
	return 3.0 * _nearnessWithWrap(e1->h, e2->h) + sdiff + ABS(e1->v - e2->v);
    }
}
        
- (NSString *)similarColorNameFromColorLists;
{
    if ([[self colorSpaceName] isEqualToString:NSNamedColorSpace])
        return [self localizedColorNameComponent];
    else if ([[self colorSpaceName] isEqualToString:NSPatternColorSpace])
        return NSLocalizedStringFromTableInBundle(@"Image", @"OmniAppKit", [OAColorProfile bundle], "generic color name for pattern colors");
    else if ([[self colorSpaceName] isEqualToString:NSCustomColorSpace])
        return NSLocalizedStringFromTableInBundle(@"Custom", @"OmniAppKit", [OAColorProfile bundle], "generic color name for custom colors");

    unsigned int entryCount;
    const OANamedColorEntry *entries = _combinedColorEntries(&entryCount);
    
    if (entryCount == 0) {
	// Avoid crasher below if something goes wrong in building the entries
	OBASSERT_NOT_REACHED("No color entries found");
	return @"";
    }
    
    OANamedColorEntry colorEntry;
    memset(&colorEntry, 0, sizeof(colorEntry));
    NSColor *rgbColor = [self colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
    [rgbColor getHue:&colorEntry.h saturation:&colorEntry.s brightness:&colorEntry.v alpha:&colorEntry.a];
    [rgbColor getRed:&colorEntry.r green:&colorEntry.g blue:&colorEntry.B alpha:&colorEntry.a];

    const OANamedColorEntry *closestEntry = &entries[0];
    float closestEntryDistance = 1e9;

    // Entries at the end of the array have higher precedence; loop backwards
    unsigned int entryIndex = entryCount;
    while (entryIndex--) {
	const OANamedColorEntry *entry = &entries[entryIndex];
	float distance = _colorCloseness(&colorEntry, entry);
	if (distance < closestEntryDistance) {
	    closestEntryDistance = distance;
	    closestEntry = entry;
	}
    }

    float brightnessDifference = colorEntry.v - closestEntry->v;
    NSString *brightnessString = nil;
    if (brightnessDifference < -.1 && colorEntry.v < .1)
        brightnessString =  NSLocalizedStringFromTableInBundle(@"Near-black", @"OmniAppKit", [OAColorProfile bundle], "word comparing color brightnesss");
    else if (brightnessDifference < -.2)
        brightnessString =  NSLocalizedStringFromTableInBundle(@"Dark", @"OmniAppKit", [OAColorProfile bundle], "word comparing color brightnesss");
    else if (brightnessDifference < -.1)
        brightnessString =  NSLocalizedStringFromTableInBundle(@"Smokey", @"OmniAppKit", [OAColorProfile bundle], "word comparing color brightnesss");
    else if (brightnessDifference > .1 && colorEntry.v > .9)
        brightnessString =  NSLocalizedStringFromTableInBundle(@"Off-white", @"OmniAppKit", [OAColorProfile bundle], "word comparing color brightnesss");
    else if (brightnessDifference > .2)
        brightnessString =  NSLocalizedStringFromTableInBundle(@"Bright", @"OmniAppKit", [OAColorProfile bundle], "word comparing color brightnesss");
    else if (brightnessDifference > .1)
        brightnessString =  NSLocalizedStringFromTableInBundle(@"Light", @"OmniAppKit", [OAColorProfile bundle], "word comparing color brightnesss");

    // Input saturation less than some value means that the saturation is irrelevant.
    NSString *saturationString = nil;
    if (colorEntry.s > 0.01) {
	float saturationDifference = colorEntry.s - closestEntry->s;
	if (saturationDifference < -0.3)
	    saturationString =  NSLocalizedStringFromTableInBundle(@"Washed-out", @"OmniAppKit", [OAColorProfile bundle], "word comparing color saturations");
	else if (saturationDifference < -.2)
	    saturationString =  NSLocalizedStringFromTableInBundle(@"Faded", @"OmniAppKit", [OAColorProfile bundle], "word comparing color saturations");
	else if (saturationDifference < -.1)
	    saturationString =  NSLocalizedStringFromTableInBundle(@"Mild", @"OmniAppKit", [OAColorProfile bundle], "word comparing color saturations");
	else if (saturationDifference > -0.01 && saturationDifference < 0.01)
	    saturationString = nil;
	else if (saturationDifference < .1)
	    saturationString = nil;
	else if (saturationDifference < .2)
	    saturationString =  NSLocalizedStringFromTableInBundle(@"Rich", @"OmniAppKit", [OAColorProfile bundle], "word comparing color saturations");
	else if (saturationDifference < .3)
	    saturationString =  NSLocalizedStringFromTableInBundle(@"Deep", @"OmniAppKit", [OAColorProfile bundle], "word comparing color saturations");
	else
	    saturationString =  NSLocalizedStringFromTableInBundle(@"Intense", @"OmniAppKit", [OAColorProfile bundle], "word comparing color saturations");
    }
    
    NSString *closestColorDescription = nil;
    if (saturationString != nil && brightnessString != nil)
        closestColorDescription = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"%@, %@ %@", @"OmniAppKit", [OAColorProfile bundle], "format string for color with saturation and brightness descriptions"), brightnessString, saturationString, closestEntry->name];
    else if (saturationString != nil)
        closestColorDescription = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"%@ %@", @"OmniAppKit", [OAColorProfile bundle], "format string for color with saturation description"), saturationString, closestEntry->name];
    else if (brightnessString != nil)
        closestColorDescription = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"%@ %@", @"OmniAppKit", [OAColorProfile bundle], "format string for color with brightness description"), brightnessString, closestEntry->name];
    else
        closestColorDescription = closestEntry->name;

    if (colorEntry.a <= 0.001)
        return NSLocalizedStringFromTableInBundle(@"Clear", @"OmniAppKit", [OAColorProfile bundle], "name of completely transparent color");
    else if (colorEntry.a < .999)
        return [NSString stringWithFormat:@"%d%% %@", (int)(colorEntry.a * 100), closestColorDescription];
    else
        return closestColorDescription;
}

+ (NSColor *)_adjustColor:(NSColor *)aColor withAdjective:(NSString *)adjective;
{
    CGFloat hue, saturation, brightness, alpha;
    [[aColor colorUsingColorSpaceName:NSCalibratedRGBColorSpace] getHue:&hue saturation:&saturation brightness:&brightness alpha:&alpha];

    if ([adjective isEqualToString:@"Near-black"]) {
        brightness = MIN(brightness, 0.05);
    } else if ([adjective isEqualToString:@"Dark"]) {
        brightness = MAX(0.0, brightness - 0.25);
    } else if ([adjective isEqualToString:@"Smokey"]) {
        brightness = MAX(0.0, brightness - 0.15);
    } else if ([adjective isEqualToString:@"Off-white"]) {
        brightness = MAX(brightness, 0.95);
    } else if ([adjective isEqualToString:@"Bright"]) {
        brightness = MIN(1.0, brightness + 0.25);
    } else if ([adjective isEqualToString:@"Light"]) {
        brightness = MIN(1.0, brightness + 0.15);
    } else if ([adjective isEqualToString:@"Washed-out"]) {
        saturation = MAX(0.0, saturation - 0.35);
    } else if ([adjective isEqualToString:@"Faded"]) {
        saturation = MAX(0.0, saturation - 0.25);
    } else if ([adjective isEqualToString:@"Mild"]) {
        saturation = MAX(0.0, saturation - 0.15);
    } else if ([adjective isEqualToString:@"Rich"]) {
        saturation = MIN(1.0, saturation + 0.15);
    } else if ([adjective isEqualToString:@"Deep"]) {
        saturation = MIN(1.0, saturation + 0.25);
    } else if ([adjective isEqualToString:@"Intense"]) {
        saturation = MIN(1.0, saturation + 0.35);
    }
    return [NSColor colorWithCalibratedHue:hue saturation:saturation brightness:brightness alpha:alpha];
}

+ (NSColor *)colorWithSimilarName:(NSString *)aName;
{
    // special case clear
    if ([aName isEqualToString:@"Clear"] || [aName isEqualToString:NSLocalizedStringFromTableInBundle(@"Clear", @"OmniAppKit", [OAColorProfile bundle], "name of completely transparent color")])
        return [NSColor clearColor];
    
    unsigned int entryCount;
    const OANamedColorEntry *entries = _combinedColorEntries(&entryCount);
    
    if (entryCount == 0) {
	// Avoid crasher below if something goes wrong in building the entries
	OBASSERT_NOT_REACHED("No color entries found");
	return nil;
    }

    // Entries at the end of the array have higher precedence; loop backwards
    unsigned int entryIndex = entryCount;

    NSColor *baseColor = nil;
    unsigned int longestMatch = 0;
    
    // find base color
    while (entryIndex--) {
	const OANamedColorEntry *entry = &entries[entryIndex];
        NSString *colorKey = entry->name;
        unsigned int length;
        
        if ([aName hasSuffix:colorKey] && (length = [colorKey length]) > longestMatch) {
            baseColor = entry->color;
            longestMatch = length;
        }
    }
    if (baseColor == nil)
        return nil;
    if ([aName length] == longestMatch)
        return baseColor;
    aName = [aName substringToIndex:([aName length] - longestMatch) - 1];
    
    // get alpha percentage
    NSRange percentRange = [aName rangeOfString:@"%"];
    if (percentRange.length == 1) {
        baseColor = [baseColor colorWithAlphaComponent:([aName cgFloatValue] / 100.0)];
        if (NSMaxRange(percentRange) + 1 >= [aName length])
            return baseColor;
        aName = [aName substringFromIndex:NSMaxRange(percentRange) + 1];
    }
    
    // adjust by adjectives
    NSRange commaRange = [aName rangeOfString:@", "];
    if (commaRange.length == 2) {
        baseColor = [self _adjustColor:baseColor withAdjective:[aName substringToIndex:commaRange.location]];
        aName = [aName substringFromIndex:NSMaxRange(commaRange)];
    }
    return [self _adjustColor:baseColor withAdjective:aName];
}

#pragma mark -
#pragma mark XML Archiving

static NSString *XMLElementName = @"color";

+ (NSString *)xmlElementName;
{
    return XMLElementName;
}

static void _xmlComponentAdder(id container, NSString *key, float component)
{
    OBPRECONDITION([container isKindOfClass:[OFXMLDocument class]]);
    [container setAttribute:key real:component];
}

static void _xmlStringAdder(id container, NSString *key, NSString *string)
{
    OBPRECONDITION([container isKindOfClass:[OFXMLDocument class]]);
    [container setAttribute:key string:string];
}

static void _xmlDataAdder(id container, NSString *key, NSData *data)
{
    OBPRECONDITION([container isKindOfClass:[OFXMLDocument class]]);
    [container setAttribute:key string:[data base64String]];
}


- (void) appendXML:(OFXMLDocument *)doc;
{
    [doc pushElement: XMLElementName];
    {
        OAColorAdders adders = {
            .component = _xmlComponentAdder,
            .string = _xmlStringAdder,
            .data = _xmlDataAdder
        };
        [self _addComponentsToContainer:doc adders:adders omittingDefaultValues:YES];

        // This is used in cases where you want to export both the real colorspace AND something that might be understandable to other XML readers (who won't be able to understand catalog colors).
        NSString *additionalColorSpace = [doc userObjectForKey:OAColorXMLAdditionalColorSpace];
        if (additionalColorSpace && OFNOTEQUAL(additionalColorSpace, [self colorSpaceName]))
            [[self colorUsingColorSpaceName:additionalColorSpace] _addComponentsToContainer:doc adders:adders omittingDefaultValues:YES];
    }
    [doc popElement];
}

static BOOL _xmlCursorComponentGetter(void *container, NSString *key, CGFloat *outComponent)
{
    NSString *attribute = [(OFXMLCursor *)container attributeNamed:key];
    if (!attribute)
        return NO;
    *outComponent = [attribute cgFloatValue];
    return YES;
}

static NSString *_xmlCursorStringGetter(void *container, NSString *key)
{
    return [(OFXMLCursor *)container attributeNamed:key];
}

static NSData *_xmlCursorDataGetter(void *container, NSString *key)
{
    NSString *string = [(OFXMLCursor *)container attributeNamed:key];
    if (!string)
        return nil;
    return [[[NSData alloc] initWithBase64String:string] autorelease];
}

+ (NSColor *)colorFromXML:(OFXMLCursor *)cursor;
{
    OBPRECONDITION([[cursor name] isEqualToString: XMLElementName]);

    OAColorGetters getters = {
        .component = _xmlCursorComponentGetter,
        .string = _xmlCursorStringGetter,
        .data = _xmlCursorDataGetter
    };
    return [NSColor _colorFromContainer:cursor getters:getters];
}

static BOOL _xmlNodeAttributeDictionaryComponentGetter(void *container, NSString *key, CGFloat *outComponent)
{
    NSString *attribute = [(NSDictionary *)container objectForKey:key];
    if (!attribute)
        return NO;
    *outComponent = [attribute cgFloatValue];
    return YES;
}

static NSString *_xmlNodeAttributeDictionaryStringGetter(void *container, NSString *key)
{
    return [(NSDictionary *)container objectForKey:key];
}

static NSData *_xmlNodeAttributeDictionaryDataGetter(void *container, NSString *key)
{
    NSString *string = [(NSDictionary *)container objectForKey:key];
    if (!string)
        return nil;
    return [[[NSData alloc] initWithBase64String:string] autorelease];
}

+ (NSColor *)colorFromXMLTreeRef:(CFXMLTreeRef)treeRef;
{
    CFXMLNodeRef nodeRef = CFXMLTreeGetNode(treeRef);
    if (nodeRef == NULL)
        return [NSColor whiteColor];
    
    NSDictionary *colorAttributes = (NSDictionary *)(((CFXMLElementInfo *)CFXMLNodeGetInfoPtr(nodeRef))->attributes);
    
    OAColorGetters getters = {
        .component = _xmlNodeAttributeDictionaryComponentGetter,
        .string = _xmlNodeAttributeDictionaryStringGetter,
        .data = _xmlNodeAttributeDictionaryDataGetter
    };
    return [NSColor _colorFromContainer:colorAttributes getters:getters];
}

@end


// Value transformers

NSString * const OAColorToPropertyListTransformerName = @"OAColorToPropertyList";

@interface OAColorToPropertyList : NSValueTransformer
@end

@implementation OAColorToPropertyList

+ (void)didLoad;
{
    [NSValueTransformer setValueTransformer:[[self alloc] init] forName:OAColorToPropertyListTransformerName];
}

+ (Class)transformedValueClass;
{
    return [NSDictionary class];
}

+ (BOOL)allowsReverseTransformation;
{
    return YES;
}

- (id)transformedValue:(id)value;
{
    if ([value isKindOfClass:[NSColor class]])
	return [(NSColor *)value propertyListRepresentation];
    return nil;
}

- (id)reverseTransformedValue:(id)value;
{
    if ([value isKindOfClass:[NSDictionary class]])
	return [NSColor colorFromPropertyListRepresentation:value];
    return nil;
}

@end

// Converts a BOOL to either +controlTextColor or +disabledControlTextColor
NSString * const OABooleanToControlColorTransformerName = @"OABooleanToControlColor";
NSString * const OANegateBooleanToControlColorTransformerName = @"OANegateBooleanToControlColor";

@interface OABooleanToControlColor : NSValueTransformer
{
    BOOL _negate;
}
@end

@implementation OABooleanToControlColor

+ (void)didLoad;
{
    OABooleanToControlColor *normal = [[self alloc] init];
    [NSValueTransformer setValueTransformer:normal forName:OABooleanToControlColorTransformerName];
    [normal release];
    
    OABooleanToControlColor *negate = [[self alloc] init];
    negate->_negate = YES;
    [NSValueTransformer setValueTransformer:negate forName:OANegateBooleanToControlColorTransformerName];
    [negate release];
}

+ (Class)transformedValueClass;
{
    return [NSColor class];
}

- (id)transformedValue:(id)value;
{
    if ([value isKindOfClass:[NSNumber class]]) {
        if ([value boolValue] ^ _negate)
            return [NSColor controlTextColor];
        return [NSColor disabledControlTextColor];
    }
    
    OBASSERT_NOT_REACHED("Invalid value for transformer");
    return [NSColor controlTextColor];
}

@end

