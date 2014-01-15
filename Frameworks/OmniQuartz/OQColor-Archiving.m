// Copyright 2010-2012 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniQuartz/OQColor-Archiving.h>

#import <OmniBase/OmniBase.h>
RCS_ID("$Id$");

#import <OmniFoundation/OFXMLCursor.h>
#import <OmniFoundation/OFXMLDocument.h>
#import <OmniFoundation/NSNumber-OFExtensions-CGTypes.h>
#import <OmniFoundation/NSData-OFEncoding.h>

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
#import <AppKit/NSColor.h>
#endif

@implementation OQColor (XML)

/*
 Cribbed from OmniAppKit for backwards compatibility.
 */

#define OQColorXMLElementName (@"color")

typedef struct {
    BOOL (*component)(void *container, NSString *key, CGFloat *outComponent); // Should only set the output if the key was present.  Returns YES if the key was present.
    NSString * (*string)(void *container, NSString *key);
    NSData * (*data)(void *container, NSString *key);
} OAColorGetters;

// Works for both NSString and NSNumber encoded components
static BOOL _dictionaryComponentGetter(void *container, NSString *key, CGFloat *outComponent)
{
    OBPRECONDITION([(id)container isKindOfClass:[NSDictionary class]]);
    
    // In some cases we care if we got the default value due to it being missing or whether it was actually in the plist.
    id obj = [(NSMutableDictionary *)container objectForKey:key];
    if (!obj)
        return NO;
    *outComponent = [obj cgFloatValue];
    return YES;
}

static NSString *_dictionaryStringGetter(void *container, NSString *key)
{
    OBPRECONDITION([(id)container isKindOfClass:[NSDictionary class]]);
    NSString *result = [(NSMutableDictionary *)container objectForKey:key];
    OBASSERT(!result || [result isKindOfClass:[NSString class]]);
    return result;
}

static NSData *_dictionaryDataGetter(void *container, NSString *key)
{
    OBPRECONDITION([(id)container isKindOfClass:[NSDictionary class]]);
    NSData *result = [(NSMutableDictionary *)container objectForKey:key];
    OBASSERT(!result || [result isKindOfClass:[NSData class]]);
    return result;
}

+ (OQColor *)_colorFromContainer:(void *)container getters:(OAColorGetters)getters;
{
#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
    NSData *data = getters.data(container, @"archive");
    if (data) {
        if ([data isKindOfClass:[NSData class]] && [data length] > 0) {
            NSColor *unarchived = [NSKeyedUnarchiver unarchiveObjectWithData:data];
            if ([unarchived isKindOfClass:[NSColor class]]) {
                OBASSERT_NOT_REACHED("<bug://bugs/60464> (Deal with custom (NSKeyedArchiver) color archive/unarchive in OQColor on iPad)");
                return [OQColor colorWithPlatformColor:unarchived];
            }
        }
        
        // otherwise, fallback -- might be a rgb color in the plist too.
    }
#endif
    
    CGFloat alpha = 1.0f;
    getters.component(container, @"a", &alpha);
    
    CGFloat v0;
    if (getters.component(container, @"w", &v0))
        return [OQColor colorWithWhite:v0 alpha:alpha];
    
#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
    NSString *catalog = getters.string(container, @"catalog");
    if (catalog) {
        NSString *name = getters.string(container, @"name");
        if ([catalog isKindOfClass:[NSString class]] && [name isKindOfClass:[NSString class]]) {
            NSColor *color = [NSColor colorWithCatalogName:catalog colorName:name];
            if (color) {
                OBASSERT_NOT_REACHED("<bug://bugs/60463> (Deal with named color archive/unarchive in OQColor on iPad)");
                return [OQColor colorWithPlatformColor:color];
            }
        }
        
        // otherwise, fallback -- might be a rgb color in the plist too.
    }
#endif
    
    if (getters.component(container, @"r", &v0)) {
        CGFloat v1 = 0.0f, v2 = 0.0f;
        getters.component(container, @"g", &v1);
        getters.component(container, @"b", &v2);
        return [OQColor colorWithRed:v0 green:v1 blue:v2 alpha:alpha];
    }
    
    if (getters.component(container, @"c", &v0)) {
        // No global name for the calibrated CMYK color space
        
        CGFloat components[5];
        components[0] = v0;
        getters.component(container, @"m", &components[1]);
        getters.component(container, @"y", &components[2]);
        getters.component(container, @"k", &components[3]);
        components[4] = alpha;
        
        OBFinishPortingLater("<bug://bugs/60461> (Deal with CMYK color archive/unarchive in OQColor on iPad)");
        //return [OQColor colorWithColorSpace:[NSColorSpace genericCMYKColorSpace] components:components count:5];
        return [OQColor whiteColor];
    }
    
    // There is no HSB/HSV colorspace, but lets allow specifying colors in property lists (for defaults in Info.plist) that way
    if (getters.component(container, @"h", &v0)) {
        CGFloat v1 = 0.0f, v2 = 0.0f;
        getters.component(container, @"s", &v1);
        if (!getters.component(container, @"v", &v2))
            getters.component(container, @"b", &v2);
        
        return [OQColor colorWithHue:v0 saturation:v1 brightness:v2 alpha:alpha];
    }
    
    NSData *patternData = getters.data(container, @"png");
    if (!patternData)
        patternData = getters.data(container, @"tiff");
    if ([patternData isKindOfClass:[NSData class]]) {
        // <bug://bugs/60462> (Deal with pattern color archive/unarchive in OQColor on iPad)
        OBFinishPortingLater("Warning: unable to unarchive pattern colors on iOS, falling back to white");
#if 0
        NSBitmapImageRep *bitmapImageRep = (id)[NSBitmapImageRep imageRepWithData:patternData];
        NSSize imageSize = [bitmapImageRep size];
        if (bitmapImageRep == nil || NSEqualSizes(imageSize, NSZeroSize)) {
            NSLog(@"Warning, could not rebuild pattern color from image rep %@, data %@", bitmapImageRep, patternData);
        } else {
            NSImage *patternImage = [[NSImage alloc] initWithSize:imageSize];
            [patternImage addRepresentation:bitmapImageRep];
            return [NSColor colorWithPatternImage:[patternImage autorelease]];
        }
#endif
        
        // fall through
    }
    
#ifdef DEBUG
    NSLog(@"Unable to unarchive color from container %@.  Falling back to white.", container);
#endif
    return [OQColor whiteColor];
}

+ (OQColor *)colorFromPropertyListRepresentation:(NSDictionary *)dict;
{
    OAColorGetters getters = {
        .component = _dictionaryComponentGetter,
        .string = _dictionaryStringGetter,
        .data = _dictionaryDataGetter,
    };
    return [self _colorFromContainer:dict getters:getters];
}


typedef struct {
    void (*component)(id container, NSString *key, double component);
    void (*string)(id container, NSString *key, NSString *string);
    void (*data)(id container, NSString *key, NSData *data);
} OAColorAdders;

static void _dictionaryStringComponentAdder(id container, NSString *key, double component)
{
    OBPRECONDITION([container isKindOfClass:[NSMutableDictionary class]]);
    NSMutableDictionary *dict = container;
    
    NSString *str = [[NSString alloc] initWithFormat:@"%g", component];
    [dict setObject:str forKey:key];
    [str release];
}

static void _dictionaryNumberComponentAdder(id container, NSString *key, double component)
{
    OBPRECONDITION([container isKindOfClass:[NSMutableDictionary class]]);
    NSMutableDictionary *dict = container;

    NSNumber *num = [[NSNumber alloc] initWithDouble:component];
    [dict setObject:num forKey:key];
    [num release];
}

static void _dictionaryStringAdder(id container, NSString *key, NSString *string)
{
    OBPRECONDITION([container isKindOfClass:[NSMutableDictionary class]]);
    NSMutableDictionary *dict = container;

    [dict setObject:string forKey:key];
}

static void _dictionaryDataAdder(id container, NSString *key, NSData *data)
{
    OBPRECONDITION([container isKindOfClass:[NSMutableDictionary class]]);
    NSMutableDictionary *dict = container;

    [dict setObject:data forKey:key];
}

// Allow for including default values, particular for scripting so that users don't have to check for missing values
- (void)_addComponentsToContainer:(id)container adders:(OAColorAdders)adders omittingDefaultValues:(BOOL)omittingDefaultValues;
{
    BOOL hasAlpha = NO;
    
    OQColorSpace colorSpace = [self colorSpace];
    
    if (colorSpace == OQColorSpaceWhite) {
        adders.component(container, @"w", [self whiteComponent]);
        hasAlpha = YES;
    } else if (colorSpace == OQColorSpaceRGB) {
        adders.component(container, @"r", [self redComponent]);
        adders.component(container, @"g", [self greenComponent]);
        adders.component(container, @"b", [self blueComponent]);
        hasAlpha = YES;
    } else if (colorSpace == OQColorSpaceHSV) {
	// The Mac supports reading this, but will convert it to RGBA. OQColor can read/write it since we have an actual color space enum for HSV.
        adders.component(container, @"h", [self hueComponent]);
        adders.component(container, @"s", [self saturationComponent]);
        adders.component(container, @"v", [self brightnessComponent]);
        hasAlpha = YES;
    } else if (colorSpace == OQColorSpaceCMYK) {
        OBASSERT_NOT_REACHED("<bug://bugs/60461> (Deal with CMYK color archive/unarchive in OQColor on iPad)");
        adders.component(container, @"w", 0);
        adders.component(container, @"a", 0);
#if 0
        // The -{cyan,magenta,yellow,black}Component methods are only valid for RGB colors, intuitively.
        CGFloat components[5]; // Assuming that it'll write out alpha too.
        [self getComponents:components];
        
        adders.component(container, @"c", components[0]);
        adders.component(container, @"m", components[1]);
        adders.component(container, @"y", components[2]);
        adders.component(container, @"k", components[3]);
        hasAlpha = YES;
#endif
    } else if (colorSpace == OQColorSpacePattern) {
        OBASSERT_NOT_REACHED("<bug://bugs/60462> (Deal with pattern color archive/unarchive in OQColor on iPad)");
        adders.component(container, @"w", 0);
        adders.component(container, @"a", 0);
#if 0
        adders.data(container, @"tiff", [[self patternImage] TIFFRepresentation]);
#endif
    } else if (colorSpace == OQColorSpaceNamed) {
        OBASSERT_NOT_REACHED("<bug://bugs/60463> (Deal with named color archive/unarchive in OQColor on iPad)");
        adders.component(container, @"w", 0);
        adders.component(container, @"a", 0);
#if 0
        adders.string(container, @"catalog", [self catalogNameComponent]);
        adders.string(container, @"name", [self colorNameComponent]);
#endif
    } else {
        OQColor *rgbColor = [self colorUsingColorSpace:OQColorSpaceRGB];
        if (rgbColor)
            [rgbColor _addComponentsToContainer:container adders:adders omittingDefaultValues:omittingDefaultValues];
	else {
            OBASSERT_NOT_REACHED("<bug://bugs/60464> (Deal with custom (NSKeyedArchiver) color archive/unarchive in OQColor on iPad)");
            adders.component(container, @"w", 0);
            adders.component(container, @"a", 0);
#if 0
	    NSData *archive = [NSKeyedArchiver archivedDataWithRootObject:self];
	    if (archive != nil && [archive length] > 0)
		adders.data(container, @"archive", archive);
#endif
	}
        return;
    }
    if (hasAlpha) {
        double alpha = [self alphaComponent];
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

#pragma mark -
#pragma mark XML Archiving

+ (NSString *)xmlElementName;
{
    return OQColorXMLElementName;
}

static void _xmlComponentAdder(id container, NSString *key, double component)
{
    OBPRECONDITION([container isKindOfClass:[OFXMLDocument class]]);
    // No double-taking XML archiver right now.
    [container setAttribute:key real:(float)component];
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

- (void)appendXML:(OFXMLDocument *)doc;
{
    [doc pushElement: OQColorXMLElementName];
    {
        OAColorAdders adders = {
            .component = _xmlComponentAdder,
            .string = _xmlStringAdder,
            .data = _xmlDataAdder
        };
        [self _addComponentsToContainer:doc adders:adders omittingDefaultValues:YES];
        
        // OBFinishPorting: support the 'extra color space'?
#if 0 && (!defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE)
        // This is used in cases where you want to export both the real colorspace AND something that might be understandable to other XML readers (who won't be able to understand catalog colors).
        NSString *additionalColorSpace = [doc userObjectForKey:OAColorXMLAdditionalColorSpace];
        if (additionalColorSpace && OFNOTEQUAL(additionalColorSpace, [self colorSpaceName]))
            [[self colorUsingColorSpaceName:additionalColorSpace] _addComponentsToContainer:doc adders:adders omittingDefaultValues:YES];
#endif
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

+ (OQColor *)colorFromXML:(OFXMLCursor *)cursor;
{
    OBPRECONDITION([[cursor name] isEqualToString: OQColorXMLElementName]);
    
    OAColorGetters getters = {
        .component = _xmlCursorComponentGetter,
        .string = _xmlCursorStringGetter,
        .data = _xmlCursorDataGetter
    };
    return [OQColor _colorFromContainer:cursor getters:getters];
}

@end
