// Copyright 2018-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OAColorCatalog.h>

#import <objc/runtime.h>

@import OmniBase;
@import OmniFoundation;

#if TARGET_OS_IOS
    @import UIKit;
#else
    @import AppKit;
#endif

NS_ASSUME_NONNULL_BEGIN

#ifdef OA_PLATFORM_COLOR_CLASS

static NSString *nameForProperty(objc_property_t property, Class *outClass);
static _Nullable Class classFromTypeEncoding(const char *type);
static objc_property_t propertyForSelectorInClass(SEL selector, Class cls, BOOL matchGetter);

#pragma mark -

@implementation OAColorCatalog

- (instancetype)init NS_UNAVAILABLE;
{
    OBRejectUnusedImplementation(self, _cmd);
    return nil;
}

+ (nullable NSString *)colorNamePrefix;
{
    return nil;
}

+ (nullable OA_PLATFORM_COLOR_CLASS *)colorNamed:(NSString *)name;
{
    return [self colorNamed:name bundle:nil];
}

+ (nullable OA_PLATFORM_COLOR_CLASS *)colorNamed:(NSString *)name bundle:(nullable NSBundle *)bundle;
{
    NSBundle *providedBundleOrClassBundle = bundle ?: [NSBundle bundleForClass:self];
#if TARGET_OS_IOS
    return [UIColor colorNamed:name inBundle:providedBundleOrClassBundle compatibleWithTraitCollection:nil];
#else
    return [NSColor colorNamed:name bundle:providedBundleOrClassBundle];
#endif
}

+ (BOOL)resolveClassMethod:(SEL)selector;
{
    if ([self resolveClassMethod:selector forClass:self]) {
        return YES;
    }

    return [super resolveClassMethod:selector];
}

+ (BOOL)resolveClassMethod:(SEL)selector forClass:(Class)cls;
{
    OBPRECONDITION([cls isSubclassOfClass:self]);
    if (![cls isSubclassOfClass:self]) {
        return NO;
    }

    const char *className = NSStringFromClass(cls).UTF8String;
    Class metaClass = objc_getMetaClass(className);
    objc_property_t property = propertyForSelectorInClass(selector, metaClass, YES);

    if (property != NULL) {
        Class valueClass = nil;
        NSString *propertyName = nameForProperty(property, &valueClass);
        if (propertyName != nil && valueClass == [OA_PLATFORM_COLOR_CLASS class]) {
            char *propertyIsReadOnly = property_copyAttributeValue(property, "R");
            if (propertyIsReadOnly == NULL) {
                @throw [NSException exceptionWithName:NSInvalidArgumentException reason:[NSString stringWithFormat:@"Property declaration for '%@' must be readonly.", propertyName] userInfo:nil];
            } else {
                free(propertyIsReadOnly);
            }
            
            NSString *colorName = propertyName;
            
            NSString *propertyPrefix = [self colorNamePrefix];
            if (![NSString isEmptyString:propertyPrefix]) {
                colorName = [NSString stringWithFormat:@"%@_%@", propertyPrefix, colorName];
            }

            OA_PLATFORM_COLOR_CLASS *color = [self colorNamed:colorName];
            OBASSERT(color != nil, "Could not look up color named: %@", colorName);
            if (color != nil) {
                IMP implementation = imp_implementationWithBlock(^(id object) {
                    return color;
                });
                
                NSMethodSignature *methodSignature = [self methodSignatureForSelector:@selector(__color_property_getter)];
                class_addMethod(metaClass, selector, implementation, methodSignature.methodReturnType);
                
                return YES;
            }
        }
    }
    
    return NO;
}

+ (OA_PLATFORM_COLOR_CLASS *)__color_property_getter NS_UNAVAILABLE;
{
    OBRejectUnusedImplementation(self, _cmd);
    return nil;
}

@end

#pragma mark -

@implementation OAColorCatalog (LegacyDarkSupport)

+ (NSString *)legacyDarkColorNameForColorName:(NSString *)colorName;
{
    return [NSString stringWithFormat:@"__%@_DARK", colorName];
}

@end

#pragma mark -

static NSString *nameForProperty(objc_property_t property, Class *outClass)
{
    const char *propertyName = property_getName(property);
    char *type = property_copyAttributeValue(property, "T");
    NSString *nameString = [NSString stringWithUTF8String:propertyName];

    *outClass = Nil;

    @try {
        if (type[0] == '@') {
            Class valueClass = classFromTypeEncoding(type);
            if (valueClass == Nil) {
                @throw [NSException exceptionWithName:NSInvalidArgumentException reason:[NSString stringWithFormat:@"Unknown class type '%@' for key '%@'", [NSString stringWithUTF8String:type], nameString] userInfo:nil];
            }
            
            *outClass = valueClass;
        } else {
            @throw [NSException exceptionWithName:NSInvalidArgumentException reason:[NSString stringWithFormat:@"Unsupported type encoding '%@' for plist key '%@'", [NSString stringWithUTF8String:type], nameString] userInfo:nil];
        }
        
        return nameString;
    } @finally {
        free(type);
    }
}

static _Nullable Class classFromTypeEncoding(const char *type)
{
    if (type[0] != '@') {
        return nil;
    }
    
    // Properties with object values have an encoding of `@"ClassName"` or `@"ClassName<ProtocolList>"` (which is an undocumented extension to the @encode() spec).
    
    // drop leading at-sign and quotation mark
    char *className = strdup(type + 2);
    BOOL trimmedProtocol = NO;
    NSInteger length = strlen(className);

    for (NSInteger i = 0; i < length; i++) {
        if (className[i] == '<') {
            // drop everything from the opening less-than delimiter to the end
            trimmedProtocol = YES;
            className[i] = '\0';
            break;
        }
    }

    if (!trimmedProtocol) {
        // drop trailing quotation marks
        className[strlen(className) - 1] = '\0';
    }

    Class valueClass = objc_getClass(className);
    free(className);
    return valueClass;
}

static objc_property_t propertyForSelectorInClass(SEL selector, Class cls, BOOL matchGetter)
{
    unsigned int propertyCount;
    objc_property_t *allProperties = class_copyPropertyList(cls, &propertyCount);
    objc_property_t backingProp = NULL;
    
    for (unsigned int i = 0; i < propertyCount; i++) {
        SEL getterSel;
        
        char *getterName = property_copyAttributeValue(allProperties[i], "G");
        if (getterName != NULL && matchGetter) {
            getterSel = sel_getUid(getterName);
            free(getterName);
        } else {
            getterSel = sel_getUid(property_getName(allProperties[i]));
        }
        
        if (getterSel == selector) {
            backingProp = allProperties[i];
            break;
        }
    }
    
    free(allProperties);
    
    return backingProp;
}

#endif

NS_ASSUME_NONNULL_END
