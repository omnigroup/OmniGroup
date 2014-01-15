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
#import <OmniFoundation/OFBinding.h> // for OFKeysForKeyPath()
#import <OmniQuartz/OQColor.h>
#import <objc/runtime.h>

RCS_ID("$Id$")

@implementation OUIAppearance
{
    NSDictionary *_plist;
}

#pragma mark - Lifecycle

- (id)_initWithPlistName:(NSString *)plistName inBundle:(NSBundle *)bundle;
{
    if (!(self = [super init]))
        return nil;
    
    NSURL *plistURL = [bundle URLForResource:[plistName stringByAppendingString:@"Appearance"] withExtension:@"plist"];
    if (!plistURL)
        plistURL = [bundle URLForResource:plistName withExtension:@"plist"];
    
    if (plistURL) {
        OB_AUTORELEASING NSError *error;
        _plist = [NSPropertyListSerialization propertyListWithData:[NSData dataWithContentsOfURL:plistURL] options:0 format:NULL error:&error];
    
        if (!_plist)
            NSLog(@"%@ failed to load appearance at URL %@: %@", NSStringFromClass([self class]), plistURL, error);
    }
    
    if (!_plist)
        _plist = [NSDictionary new];
    
    return self;
}

+ (instancetype)appearance;
{
    return AppearanceForClass(self);
}

static inline OUIAppearance *AppearanceForClass(Class cls)
{
    static NSMapTable *ClassToAppearanceMap;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        ClassToAppearanceMap = [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsObjectPointerPersonality valueOptions:NSPointerFunctionsObjectPersonality];
    });
    
    OUIAppearance *appearance = [ClassToAppearanceMap objectForKey:cls];
    if (!appearance) {
        appearance = [[cls alloc] _initWithPlistName:NSStringFromClass(cls) inBundle:[NSBundle bundleForClass:cls]];
        OBASSERT_NOTNULL(appearance);
        
        [ClassToAppearanceMap setObject:appearance forKey:cls];
    }
    
    return appearance;
}

#pragma mark - Static accessors

- (id)_objectOfClass:(Class)cls forPlistKeyPath:(NSString *)keyPath;
{
    id obj = _plist;
    
    NSArray *keys = OFKeysForKeyPath(keyPath);

    NSUInteger keyCount = keys.count;
    for (NSUInteger idx = 0; idx < keyCount; idx++) {
        NSString *key = keys[idx];
        obj = [obj objectForKey:key];
        Class expectedClass = (idx == keyCount - 1) ? cls : [NSDictionary class];
        
        if (!obj) {
            if ([self class] == [OUIAppearance class])
                @throw [NSException exceptionWithName:NSInvalidArgumentException reason:[NSString stringWithFormat:@"No object found for key path component '%@'", key] userInfo:nil];
            else
                return [AppearanceForClass([self superclass]) _objectOfClass:cls forPlistKeyPath:keyPath];
        } else if (![obj isKindOfClass:expectedClass]) {
            @throw [NSException exceptionWithName:NSInvalidArgumentException reason:[NSString stringWithFormat:@"Object for key path component '%@' in appearance '%@' is not an instance of expected class '%@'", key, NSStringFromClass([self class]), NSStringFromClass(expectedClass)] userInfo:@{key:obj}];
        }
    };
    
    return obj;
}

- (NSDictionary *)dictionaryForKeyPath:(NSString *)keyPath;
{
    return [self _objectOfClass:[NSDictionary class] forPlistKeyPath:keyPath];
}

- (OUI_SYSTEM_COLOR_CLASS *)colorForKeyPath:(NSString *)keyPath;
{
    return [OUI_SYSTEM_COLOR_CLASS colorFromPropertyListRepresentation:[self _objectOfClass:[NSDictionary class] forPlistKeyPath:keyPath]];
}

- (CGFloat)CGFloatForKeyPath:(NSString *)keyPath;
{
    return [(NSNumber *)[self _objectOfClass:[NSNumber class] forPlistKeyPath:keyPath] cgFloatValue];
}

- (BOOL)boolForKeyPath:(NSString *)keyPath;
{
    return [(NSNumber *)[self _objectOfClass:[NSNumber class] forPlistKeyPath:keyPath] boolValue];
}

- (OUI_SYSTEM_EDGE_INSETS_STRUCT)edgeInsetsForKeyPath:(NSString *)keyPath;
{
    NSDictionary *insetsDescription = [self _objectOfClass:[NSDictionary class] forPlistKeyPath:keyPath];
    
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

- (OUI_SYSTEM_SIZE_STRUCT)sizeForKeyPath:(NSString *)keyPath;
{
    NSDictionary *sizeDescription = [self _objectOfClass:[NSDictionary class] forPlistKeyPath:keyPath];
    
    static NSNumber *zero;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        zero = [NSNumber numberWithCGFloat:0];
    });
    
    OUI_SYSTEM_SIZE_STRUCT result;
    result.width = [[sizeDescription objectForKey:@"width" defaultObject:zero] cgFloatValue];
    result.height = [[sizeDescription objectForKey:@"height" defaultObject:zero] cgFloatValue];
    
    return result;
}

#pragma mark - Dynamic accessors

- (objc_property_t)_propertyForSelector:(SEL)invocationSel;
{
    unsigned int propertyCount;
    objc_property_t *allProperties = class_copyPropertyList([self class], &propertyCount);
    objc_property_t backingProp = NULL;
    
    for (unsigned int i = 0; i < propertyCount; i++) {
        SEL getterSel;
        
        char *getterName = property_copyAttributeValue(allProperties[i], "G");
        if (getterName) {
            getterSel = sel_getUid(getterName);
            free(getterName);
        } else {
            getterSel = sel_getUid(property_getName(allProperties[i]));
        }
        
        if (getterSel == invocationSel) {
            backingProp = allProperties[i];
            break;
        }
    }
    
    free(allProperties);
    
    return backingProp;
}

- (void)_synthesizeGetter:(SEL)invocationSel forProperty:(objc_property_t)backingProp;
{
    const char *backingPropName = property_getName(backingProp);
    
    char *backingPropReadonly = property_copyAttributeValue(backingProp, "R");
    if (!backingPropReadonly)
        @throw [NSException exceptionWithName:NSInvalidArgumentException reason:[NSString stringWithFormat:@"Property declaration for '%@' must be readonly.", [NSString stringWithUTF8String:backingPropName]] userInfo:nil];
    free(backingPropReadonly);
    
    char *backingPropType = property_copyAttributeValue(backingProp, "T");
    
    IMP getterImp;
    char *getterTypes;
    
    MakeImpForProperty([NSString stringWithUTF8String:backingPropName], backingPropType, invocationSel, &getterImp, &getterTypes);
    free(backingPropType);
    
    class_addMethod([self class], invocationSel, getterImp, getterTypes);
    
    free(getterTypes);
}

/*! outImpTypes must be free()d. */
static void MakeImpForProperty(NSString *backingPropName, const char *type, SEL invocationSel, IMP *outImp, char **outImpTypes)
{
#if 0 && defined(DEBUG)
#define DEBUG_DYNAMIC_GETTER(...) NSLog(@"%@", [[NSString stringWithFormat:@"DYNAMIC OUIAPPEARANCE GETTER: -%@ ", [self class]] stringByAppendingFormat:__VA_ARGS__]);
#else
#define DEBUG_DYNAMIC_GETTER(...)
#endif
    char *returnType;
    
    if (type[0] == '@') {
        returnType = "@";
        
        // Properties with object values have an encoding of `@"ClassName"` (which is an undocumented extension to the @encode() spec).
        char *className = strdup(type + 2);
        className[strlen(className) - 1] = '\0';
        Class cls = objc_getClass(className);
        
        if (!cls) {
            @throw [NSException exceptionWithName:NSInvalidArgumentException reason:[NSString stringWithFormat:@"Unknown class '%@' for key '%@'", [NSString stringWithUTF8String:className], backingPropName] userInfo:nil];
        } else if (cls == [OUI_SYSTEM_COLOR_CLASS class]) {
            *outImp = imp_implementationWithBlock(^(id self, id self2, va_list method_args, ...) {
                OUI_SYSTEM_COLOR_CLASS *color = [self colorForKeyPath:backingPropName];
                DEBUG_DYNAMIC_GETTER(@"colorForKeyPath:%@ --> %@", backingPropName, color);
                return color;
            });
        } else {
            *outImp = imp_implementationWithBlock(^(id self, id self2, va_list method_args, ...) {
                id object = [self _objectOfClass:cls forPlistKeyPath:backingPropName];
                DEBUG_DYNAMIC_GETTER(@"_objectOfClass:%@ forPlistKeyPath:%@ --> %@", NSStringFromClass(cls), backingPropName, object);
                return object;
            });
        }
        
        free(className);
    } else if (strcmp(type, @encode(CGFLOAT_TYPE)) == 0) {
        returnType = @encode(CGFLOAT_TYPE);
        *outImp = imp_implementationWithBlock(^(id self, id self2, va_list method_args, ...) {
            CGFloat val = [self CGFloatForKeyPath:backingPropName];
            DEBUG_DYNAMIC_GETTER(@"CGFloatForKeyPath:%@ --> %f", backingPropName, val);
            return val;
        });
    } else if (strcmp(type, @encode(BOOL)) == 0) {
        returnType = "c";
        *outImp = imp_implementationWithBlock(^(id self, id self2, va_list method_args, ...) {
            BOOL val = [self boolForKeyPath:backingPropName];
            DEBUG_DYNAMIC_GETTER(@"boolForKeyPath:%@ --> %@", backingPropName, val ? @"YES" : @"NO");
            return val;
        });
    } else if (strcmp(type, @encode(OUI_SYSTEM_EDGE_INSETS_STRUCT)) == 0) {
        returnType = @encode(OUI_SYSTEM_EDGE_INSETS_STRUCT);
        *outImp = imp_implementationWithBlock(^(id self, id self2, va_list method_args, ...) {
            OUI_SYSTEM_EDGE_INSETS_STRUCT insets = [self edgeInsetsForKeyPath:backingPropName];
            
            DEBUG_DYNAMIC_GETTER(@"edgeInsetsForKeyPath:%@ --> %@", backingPropName, [NSValue valueWithBytes:&insets objCType:returnType]);
            
            return insets;
        });
    } else if (strcmp(type, @encode(OUI_SYSTEM_SIZE_STRUCT)) == 0) {
        returnType = @encode(OUI_SYSTEM_SIZE_STRUCT);
        *outImp = imp_implementationWithBlock(^(id self, id self2, va_list method_args, ...) {
            OUI_SYSTEM_SIZE_STRUCT size = [self sizeForKeyPath:backingPropName];
            
            DEBUG_DYNAMIC_GETTER(@"sizeForKeyPath:%@ --> %@", backingPropName, [NSValue valueWithBytes:&size objCType:returnType]);
            
            return size;
        });
    } else {
        @throw [NSException exceptionWithName:NSInvalidArgumentException reason:[NSString stringWithFormat:@"Unsupported type encoding '%@' for plist key '%@'", [NSString stringWithUTF8String:type], backingPropName] userInfo:nil];
    }
    
    size_t returnTypeLength = strlen(returnType);
    char *buf = malloc(returnTypeLength + 3);
    strncpy(buf, returnType, returnTypeLength);
    strncpy(buf + returnTypeLength, "@:", 2);
    *outImpTypes = buf;
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector;
{
    NSMethodSignature *signature = [super methodSignatureForSelector:aSelector];
    if (signature)
        return signature;
    
    objc_property_t backingProperty = [self _propertyForSelector:aSelector];
    if (backingProperty) {
        [self _synthesizeGetter:aSelector forProperty:backingProperty];
        signature = [super methodSignatureForSelector:aSelector];
        
        OBASSERT_NOTNULL(signature, "But we just synthesized it!");
        return signature;
    } else {
        return nil;
    }
}

- (void)forwardInvocation:(NSInvocation *)anInvocation;
{
    if ([self respondsToSelector:anInvocation.selector])
        [anInvocation invoke];
    else
        [super forwardInvocation:anInvocation];
}

@end

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE

#pragma mark - Mac Convenience Accessors

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
        color = [[OUIAppearance appearance] colorForKeyPath:@"OUISidebarBackgroundColor"];
    });
    
    return color;
}

+ (NSColor *)OUISidebarFontColor;
{
    static NSColor *color;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        color = [[OUIAppearance appearance] colorForKeyPath:@"OUISidebarFontColor"];
    });
    
    return color;
}

+ (NSColor *)OUISelectionBorderColor;
{
    EnsureSystemColorsObserver();
    
    if (!SelectionBorderColor) {
        SelectionBorderColor = [[NSColor alternateSelectedControlColor] colorWithAlphaComponent:([[OUIAppearance appearance] CGFloatForKeyPath:@"OUISelectionBorderColorAlphaPercentage"] / 100.0)];
    }
    
    return SelectionBorderColor;
}

+ (NSColor *)OUIInactiveSelectionBorderColor;
{
    static NSColor *color;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        color = [[OUIAppearance appearance] colorForKeyPath:@"OUIInactiveSelectionBorderColor"];
    });
    
    return color;
}

@end

#else // defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE

#pragma mark - iOS Convenience Accessors

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
        color = [[OUIAppearance appearance] colorForKeyPath:key]; \
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
        lightColorLimit = ([appearance CGFloatForKeyPath:@"OUILightColorLumaLimit"]);
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
