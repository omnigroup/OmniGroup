// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIAppearance.h>

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
#import <OmniUI/UIColor-OUIExtensions.h>
#endif

#import <OmniFoundation/NSDictionary-OFExtensions.h>
#import <OmniFoundation/NSNumber-OFExtensions-CGTypes.h>
#import <OmniQuartz/OQColor.h>

RCS_ID("$Id$")

@implementation OUIAppearance
{
    NSDictionary *_plist;
}

- (id)_initWithPlist:(NSString *)plist inBundle:(NSBundle *)bundle;
{
    if (!(self = [super init]))
        return nil;
    
    NSString *plistFilename = [plist stringByAppendingPathExtension:@"plist"];
    
    NSURL *plistURL = [bundle URLForResource:plistFilename withExtension:nil];
    if (!plistURL)
        @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:[NSString stringWithFormat:@"Could not find resource '%@'.", plistFilename] userInfo:nil];
    
    NSError *error;
    _plist = [NSPropertyListSerialization propertyListWithData:[NSData dataWithContentsOfURL:plistURL] options:0 format:NULL error:&error];
    if (!_plist)
        @throw [NSException exceptionWithName:NSInvalidUnarchiveOperationException reason:[NSString stringWithFormat:@"Could not read property list from URL '%@'", plistURL] userInfo:[NSDictionary dictionaryWithObject:error forKey:NSUnderlyingErrorKey]];
    
    return self;
}

- (id)_initForBundle:(NSBundle *)bundle;
{
    return [self _initWithPlist:NSStringFromClass([self class]) inBundle:bundle];
}

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE

- (id)initWithName:(NSString *)appearanceName;
{
    NSBundle *bundle = [NSBundle mainBundle];
    
    // Search for "FooAppearance.plist" first
    NSString *searchName = [NSString stringWithFormat:@"%@Appearance", appearanceName];
    if ([bundle pathForResource:searchName ofType:@"plist"] != nil) {
        return [self _initWithPlist:searchName inBundle:bundle];
    }
    
    // Next do plain "Foo.plist"
    if ([bundle pathForResource:appearanceName ofType:@"plist"]) {
        return [self _initWithPlist:appearanceName inBundle:bundle];
    }
    
    // Finally, bail
    @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:[NSString stringWithFormat:@"Could not find any resource for appearance name '%@'", appearanceName] userInfo:nil];
}

+ (instancetype)appearance;
{
    return [self appearanceWithName:NSStringFromClass(self)];
}

+ (instancetype)appearanceWithName:(NSString *)appearanceName;
{
    return [[self alloc] initWithName:appearanceName];
}

#endif

- (NSDictionary *)_objectOfClass:(Class)cls forPlistKey:(NSString *)key;
{
    id obj = [_plist objectForKey:key];
    
    if (!obj)
        @throw [NSException exceptionWithName:NSInvalidArgumentException reason:[NSString stringWithFormat:@"No dictionary found for key '%@'", key] userInfo:nil];
    else if (!([obj isKindOfClass:cls]))
        @throw [NSException exceptionWithName:NSInvalidArgumentException reason:[NSString stringWithFormat:@"Object for key '%@' is not an instance of expected class '%@'", key, NSStringFromClass(cls)] userInfo:[NSDictionary dictionaryWithObject:obj forKey:key]];
    
    return obj;
}

- (OUI_SYSTEM_COLOR_CLASS *)colorForKey:(NSString *)key;
{
    return [OUI_SYSTEM_COLOR_CLASS colorFromPropertyListRepresentation:[self _objectOfClass:[NSDictionary class] forPlistKey:key]];
}

- (CGFloat)CGFloatForKey:(NSString *)key;
{
    return [(NSNumber *)[self _objectOfClass:[NSNumber class] forPlistKey:key] cgFloatValue];
}

- (BOOL)boolForKey:(NSString *)key;
{
    return [(NSNumber *)[self _objectOfClass:[NSNumber class] forPlistKey:key] boolValue];
}

- (OUI_SYSTEM_EDGE_INSETS_STRUCT)edgeInsetsForKey:(NSString *)key;
{
    NSDictionary *insetsDescription = [self _objectOfClass:[NSDictionary class] forPlistKey:key];
    
    static NSNumber *zero;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        zero = [NSNumber numberWithCGFloat:0];
    });
    
    OUI_SYSTEM_EDGE_INSETS_STRUCT result;
    result.top = [[insetsDescription objectForKey:@"top" defaultObject:zero] cgFloatValue];
    result.left = [[insetsDescription objectForKey:@"left" defaultObject:zero] cgFloatValue];
    result.bottom = [[insetsDescription objectForKey:@"bottom" defaultObject:zero] cgFloatValue];
    result.right = [[insetsDescription objectForKey:@"right" defaultObject:zero] cgFloatValue];
    
    return result;
}

@end

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE

@implementation NSBundle (OUIAppearance)

- (OUIAppearance *)appearance;
{
    static NSMutableDictionary *BundleIdentifierToOUIAppearance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        BundleIdentifierToOUIAppearance = [[NSMutableDictionary alloc] init];
    });
    
    NSString *identifier = [self bundleIdentifier];
    OUIAppearance *appearance = [BundleIdentifierToOUIAppearance objectForKey:identifier];
    
    // Only try loading the appearance once, if it fails, use NSNull as a sentinel.
    if (appearance) {
        if (appearance == (id)[NSNull null])
            return nil;
        else
            return appearance;
    }
    
    @try {
        appearance = [[OUIAppearance alloc] _initForBundle:self];
    } @catch (NSException *e) {
        appearance = nil;
        @throw e;
    } @finally {
        if (!appearance)
            appearance = (id)[NSNull null];
        
        [BundleIdentifierToOUIAppearance setObject:appearance forKey:identifier];
    }
    
    return appearance;
}

@end

static NSGradient *SelectionGradient;
static NSColor *SelectionBorderColor;
static id SystemColorsObserver;
NSString *const OUIAppearanceColorsDidChangeNotification = @"com.omnigroup.OmniUI.OUIAppearance.ColorsDidChange";

static void EnsureSystemColorsObserver(void)
{
    if (!SystemColorsObserver) {
        SystemColorsObserver = [[NSNotificationCenter defaultCenter] addObserverForName:NSSystemColorsDidChangeNotification object:nil queue:nil usingBlock:^(NSNotification *unused){
            SelectionGradient = nil;
            
            SelectionBorderColor = nil;
            
            [[NSNotificationCenter defaultCenter] postNotificationName:OUIAppearanceColorsDidChangeNotification object:NSApp];
        }];
    }
}

@implementation NSColor (OUIAppearance)

+ (NSColor *)OUISidebarBackgroundColor;
{
    static NSColor *color;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        color = [[OMNI_BUNDLE appearance] colorForKey:@"OUISidebarBackgroundColor"];
    });
    
    return color;
}

+ (NSColor *)OUISidebarFontColor;
{
    static NSColor *color;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        color = [[OMNI_BUNDLE appearance] colorForKey:@"OUISidebarFontColor"];
    });
    
    return color;
}

+ (NSColor *)OUISelectionBorderColor;
{
    EnsureSystemColorsObserver();
    
    if (!SelectionBorderColor) {
        SelectionBorderColor = [[NSColor alternateSelectedControlColor] colorWithAlphaComponent:([[OMNI_BUNDLE appearance] CGFloatForKey:@"OUISelectionBorderColorAlphaPercentage"] / 100.0)];
    }
    
    return SelectionBorderColor;
}

+ (NSColor *)OUIInactiveSelectionBorderColor;
{
    static NSColor *color;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        color = [[OMNI_BUNDLE appearance] colorForKey:@"OUIInactiveSelectionBorderColor"];
    });
    
    return color;
}

@end

@implementation NSGradient (OUIAppearance)

+ (NSGradient *)OUISelectionGradient;
{
    static NSColor *grayColor;
    static CGFloat startingGrayBlendFraction, endingGrayBlendFraction;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        OUIAppearance *appearance = [OMNI_BUNDLE appearance];
        grayColor = [appearance colorForKey:@"OUISelectionGradientGrayColor"];
        startingGrayBlendFraction = ([appearance CGFloatForKey:@"OUISelectionGradientStartingGrayBlendPercentage"] / 100.0);
        endingGrayBlendFraction = ([appearance CGFloatForKey:@"OUISelectionGradientStartingGrayBlendPercentage"] / 100.0);
    });
    
    EnsureSystemColorsObserver();
    
    if (!SelectionGradient) {
        NSColor *startColor = [grayColor blendedColorWithFraction:startingGrayBlendFraction ofColor:[NSColor selectedControlColor]];
        NSColor *endColor = [grayColor blendedColorWithFraction:endingGrayBlendFraction ofColor:[NSColor selectedControlColor]];
        SelectionGradient = [[NSGradient alloc] initWithStartingColor:startColor endingColor:endColor];
    }
    
    return SelectionGradient;
}

+ (NSGradient *)OUIInactiveSelectionGradient;
{
    static NSGradient *gradient;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        OUIAppearance *appearance = [OMNI_BUNDLE appearance];
        NSColor *startColor = [appearance colorForKey:@"OUIInactiveSelectionGradientStartColor"];
        NSColor *endColor = [appearance colorForKey:@"OUIInactiveSelectionGradientEndColor"];
        gradient = [[NSGradient alloc] initWithStartingColor:startColor endingColor:endColor];
    });
    
    return gradient;
}

@end

#else // defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE

@implementation UIColor (OUIAppearance)

#if OB_ARC
    #define DO_RETAIN(x) // assign to global does it
#else
    #define DO_RETAIN(x) OBStrongRetain(x);
#endif

#define CACHED_COLOR(key) do { \
    static UIColor *color; \
    static dispatch_once_t onceToken; \
    dispatch_once(&onceToken, ^{ \
        color = [[OUIAppearance appearance] colorForKey:key]; \
        DO_RETAIN(color); \
    }); \
    return color; \
} while(0);

+ (UIColor *)omniRedColor;
{
    CACHED_COLOR(@"OmniRed");
}

+ (UIColor *)omniOrangeColor;
{
    CACHED_COLOR(@"OmniOrange");
}

+ (UIColor *)omniYellowColor;
{
    CACHED_COLOR(@"OmniYellow");
}

+ (UIColor *)omniGreenColor;
{
    CACHED_COLOR(@"OmniGreen");
}

+ (UIColor *)omniTealColor;
{
    CACHED_COLOR(@"OmniTeal");
}

+ (UIColor *)omniBlueColor;
{
    CACHED_COLOR(@"OmniBlue");
}

+ (UIColor *)omniPurpleColor;
{
    CACHED_COLOR(@"OmniPurple");
}

+ (UIColor *)omniGraphiteColor;
{
    CACHED_COLOR(@"OmniGraphite");
}

+ (UIColor *)omniAlternateRedColor;
{
    CACHED_COLOR(@"OmniAlternateRed");
}

+ (UIColor *)omniAlternateYellowColor;
{
    CACHED_COLOR(@"OmniAlternateYellow");
}

+ (UIColor *)omniNeutralDeemphasizedColor;
{
    CACHED_COLOR(@"OmniNeutralDeemphasized");
}

+ (UIColor *)omniNeutralPlaceholderColor;
{
    CACHED_COLOR(@"OmniNeutralPlaceholder");
}

+ (UIColor *)omniNeutralLightweightColor;
{
    CACHED_COLOR(@"OmniNeutralLightweight");
}

+ (UIColor *)omniDeleteColor;
{
    CACHED_COLOR(@"OmniDelete");
}

- (BOOL)isLightColor;
{
    static CGFloat lightColorLimit;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        OUIAppearance *appearance = [OUIAppearance appearance];
        lightColorLimit = ([appearance CGFloatForKey:@"OUILightColorLumaLimit"]);
    });

    OQColor *aColor = [OQColor colorWithPlatformColor:self];
    CGFloat luma = OQGetRGBAColorLuma([aColor toRGBA]);

    if (luma < lightColorLimit)
        return NO;
    else
        return YES;
}

@end

#endif
