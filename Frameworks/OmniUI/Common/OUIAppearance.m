// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIAppearance.h>

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
#import <OmniUI/OUIAppearanceColors.h>
#import <OmniUI/UIColor-OUIExtensions.h>
#endif

#import <OmniFoundation/NSDictionary-OFExtensions.h>
#import <OmniFoundation/NSNumber-OFExtensions-CGTypes.h>
#import <OmniFoundation/OFBinding.h> // for OFKeysForKeyPath()
#import <OmniFoundation/OFEnumNameTable.h>
#import <OmniQuartz/OQColor-Archiving.h>
#import <objc/runtime.h>

NSString * const OUIAppearanceAliasesKey = @"OUIAppearanceAliases";
NSString * const OUIAppearancePlistExtension = @"plist";
NSString * const OUIAppearanceValuesWillChangeNotification = @"com.omnigroup.OmniUI.OUIAppearance.ValuesWillChange";
NSString * const OUIAppearanceValuesDidChangeNotification = @"com.omnigroup.OmniUI.OUIAppearance.ValuesDidChange";

#define OUI_PERFORM_FILE_PRESENTATION (!defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE)

#if OUI_PERFORM_FILE_PRESENTATION

@interface OUIAppearanceUserPlistFilePresenter : NSObject <NSFilePresenter> {
  @private
    __weak OUIAppearance *_weak_owner;
    NSOperationQueue *_userPlistPresentationQueue;
}

- (instancetype)initWithOwner:(OUIAppearance *)owner;

@end

#endif // OUI_PERFORM_FILE_PRESENTATION

RCS_ID("$Id$")

static NSMapTable *ClassToAppearanceMap = nil;

@interface OUIAppearance () {
  @private
    NSDictionary *_plist;
#if OUI_PERFORM_FILE_PRESENTATION
    OUIAppearanceUserPlistFilePresenter *_userPlistFilePresenter;
#endif
}

@property (nonatomic, copy) NSString *plistName;
@property (nonatomic, strong) NSBundle *plistBundle;

@end

@implementation OUIAppearance

#pragma mark - Lifecycle

- (id)_initWithPlistName:(NSString *)plistName inBundle:(NSBundle *)bundle;
{
    if (!(self = [super init]))
        return nil;

    _plistName = [plistName copy];
    _plistBundle = bundle;
    
    [self recachePlistFromFile];

    return self;
}

- (void)dealloc;
{
    [self endPresentingUserPlistIfNecessary];
}

+ (instancetype)appearance;
{
    return [self appearanceForClass:self];
}

static NSString *_OUIAppearanceUserOverrideFolder = nil;

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE

void OUIAppearanceSetUserOverrideFolder(NSString *userOverrideFolder)
{
    if (OFNOTEQUAL(_OUIAppearanceUserOverrideFolder, userOverrideFolder)) {
        _OUIAppearanceUserOverrideFolder = [userOverrideFolder copy];
        
        for (Class cls in ClassToAppearanceMap) {
            OUIAppearance *appearance = [ClassToAppearanceMap objectForKey:cls];
            [appearance endPresentingUserPlistIfNecessary];
            [appearance invalidateCachedValues];
            [appearance beginPresentingUserPlistIfNecessary];
        }
    }
}

#endif

#pragma mark Helpers

- (void)invalidateCachedValues;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    [[NSNotificationCenter defaultCenter] postNotificationName:OUIAppearanceValuesWillChangeNotification object:self];

    [self recachePlistFromFile];
    _cacheInvalidationCount++;
    
    [[NSNotificationCenter defaultCenter] postNotificationName:OUIAppearanceValuesDidChangeNotification object:self];
}

- (void)beginPresentingUserPlistIfNecessary;
{
#if OUI_PERFORM_FILE_PRESENTATION
    // N.B. Note that if the user plist doesn't exist when we start presenting, we won't get any notification when it does appear, but we will get one for the first change to it after it does appear.
    
    if (_userPlistFilePresenter == nil) {
        _userPlistFilePresenter = [[OUIAppearanceUserPlistFilePresenter alloc] initWithOwner:self];
        [NSFileCoordinator addFilePresenter:_userPlistFilePresenter];
    }
#endif
}

- (void)endPresentingUserPlistIfNecessary;
{
#if OUI_PERFORM_FILE_PRESENTATION
    if (_userPlistFilePresenter != nil) {
        [NSFileCoordinator removeFilePresenter:_userPlistFilePresenter];
        _userPlistFilePresenter = nil;
    }
#endif
}

- (void)recachePlistFromFile;
{
    NSURL *plistURL = [_plistBundle URLForResource:[_plistName stringByAppendingString:@"Appearance"] withExtension:OUIAppearancePlistExtension];
    if (!plistURL)
        plistURL = [_plistBundle URLForResource:_plistName withExtension:OUIAppearancePlistExtension];
    
    if (plistURL) {
        OB_AUTORELEASING NSError *error;
        _plist = [NSPropertyListSerialization propertyListWithData:[NSData dataWithContentsOfURL:plistURL] options:0 format:NULL error:&error];
        
        if (!_plist)
            NSLog(@"%@ failed to load appearance at URL %@: %@", NSStringFromClass([self class]), plistURL, error);
    }
    
    if (_plist == nil)
        _plist = [NSDictionary new];
    
    // Look for user overrides
    NSString *userPlistPath = [[self userPlistURL] path];
    if (userPlistPath != nil) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:userPlistPath]) {

#if OUI_PERFORM_FILE_PRESENTATION
            __block NSData *userData = nil;
            OB_AUTORELEASING NSError *coordinatedReadError = nil;
            NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
            [coordinator coordinateReadingItemAtURL:[self userPlistURL] options:0 error:&coordinatedReadError byAccessor:^(NSURL *newURL) {
                userData = [NSData dataWithContentsOfFile:userPlistPath];
            }];
#else
            NSData *userData = [NSData dataWithContentsOfFile:userPlistPath];
#endif
            
            if (userData != nil) {
                OB_AUTORELEASING NSError *plistParsingError = nil;
                NSDictionary *userPlist = [NSPropertyListSerialization propertyListWithData:userData options:0 format:NULL error:&plistParsingError];
                if (userPlist != nil && [userPlist isKindOfClass:[NSDictionary class]]) {
                    NSMutableDictionary *mutablePlist = [_plist deepMutableCopy];
                    [mutablePlist setValuesForKeysWithDictionary:userPlist];
                    _plist = [mutablePlist copy];
                }
            }
        }
    }
    
    _cacheInvalidationCount ++;
}

/// Returns the URL for the user override appearance plist.
- (NSURL *)userPlistURL;
{
    if (_OUIAppearanceUserOverrideFolder == nil)
        return nil;

    NSString *userPlistPath = [[_OUIAppearanceUserOverrideFolder stringByAppendingPathComponent:_plistName] stringByAppendingPathExtension:OUIAppearancePlistExtension];
    
    return [NSURL fileURLWithPath:userPlistPath];
}

#pragma mark - Static accessors

- (id)_objectOfClass:(Class)cls forPlistKeyPath:(NSString *)keyPath;
{
    // Can enable this to check if appearance values are being looked up on commonly hit drawing paths.
#if 0 && defined(DEBUG)
    NSLog(@"Looking up %@/%@ in %@", NSStringFromClass(cls), keyPath, self);
#endif
    
    id obj = _plist;
    
    NSArray *keys = OFKeysForKeyPath(keyPath);

    NSUInteger keyCount = keys.count;
    for (NSUInteger idx = 0; idx < keyCount; idx++) {
        NSString *key = keys[idx];
        id parentObj = obj;
        obj = [obj objectForKey:key];
        Class expectedClass = (idx == keyCount - 1) ? cls : [NSDictionary class];
        
        if (!obj) {
            // First try to find an alias for the given key
            NSDictionary *aliases = [parentObj objectForKey:OUIAppearanceAliasesKey];
            if (aliases != nil) {
                NSString *alias = [aliases objectForKey:key];
                if (alias != nil) {
                    // Found an alias; restart the search at the top level for the resultant target key path
                    NSString *dereferencedKeyPath = nil;
                    if (idx == keyCount - 1) {
                        dereferencedKeyPath = alias;
                    } else {
                        NSArray *remainingKeys = [keys subarrayWithRange:NSMakeRange(idx + 1, keyCount - (idx + 1))];
                        dereferencedKeyPath = [alias stringByAppendingFormat:@".%@", [remainingKeys componentsJoinedByString:@"."]];
                    }
                    
                    return [self _objectOfClass:cls forPlistKeyPath:dereferencedKeyPath];
                }
            }
            
            // If no alias exists, either fall back to the superclass or throw, depending on what class this is
            if ([self class] == [OUIAppearance class])
                @throw [NSException exceptionWithName:NSInvalidArgumentException reason:[NSString stringWithFormat:@"No object found for key path component '%@'", key] userInfo:nil];
            else
                return [[[self class] appearanceForClass:[self superclass]] _objectOfClass:cls forPlistKeyPath:keyPath];
        } else if (![obj isKindOfClass:expectedClass]) {
            @throw [NSException exceptionWithName:NSInvalidArgumentException reason:[NSString stringWithFormat:@"Object for key path component '%@' in appearance '%@' is not an instance of expected class '%@'", key, NSStringFromClass([self class]), NSStringFromClass(expectedClass)] userInfo:@{key:obj}];
        }
    };
    
    return obj;
}

- (NSString *)stringForKeyPath:(NSString * )keyPath;
{
    return [self _objectOfClass:[NSString class] forPlistKeyPath:keyPath];
}

- (NSDictionary *)dictionaryForKeyPath:(NSString *)keyPath;
{
    return [self _objectOfClass:[NSDictionary class] forPlistKeyPath:keyPath];
}

- (OUI_SYSTEM_COLOR_CLASS *)colorForKeyPath:(NSString *)keyPath;
{
    return [OUI_SYSTEM_COLOR_CLASS colorFromPropertyListRepresentation:[self _objectOfClass:[NSDictionary class] forPlistKeyPath:keyPath]];
}

- (OQColor *)OQColorForKeyPath:(NSString *)keyPath;
{
    return [OQColor colorWithPlatformColor:[self colorForKeyPath:keyPath]];
}

- (NSInteger)integerForKeyPath:(NSString *)keyPath;
{
    return [(NSNumber *)[self _objectOfClass:[NSNumber class] forPlistKeyPath:keyPath] integerValue];
}

- (float)floatForKeyPath:(NSString *)keyPath;
{
    return [(NSNumber *)[self _objectOfClass:[NSNumber class] forPlistKeyPath:keyPath] floatValue];
}

- (double)doubleForKeyPath:(NSString *)keyPath;
{
    return [(NSNumber *)[self _objectOfClass:[NSNumber class] forPlistKeyPath:keyPath] doubleValue];
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

- (CGSize)sizeForKeyPath:(NSString *)keyPath;
{
    NSDictionary *sizeDescription = [self _objectOfClass:[NSDictionary class] forPlistKeyPath:keyPath];
    
    static NSNumber *zero;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        zero = [NSNumber numberWithCGFloat:0];
    });
    
    CGSize result;
    result.width = [[sizeDescription objectForKey:@"width" defaultObject:zero] cgFloatValue];
    result.height = [[sizeDescription objectForKey:@"height" defaultObject:zero] cgFloatValue];
    
    return result;
}

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
- (UIImage *)imageForKeyPath:(NSString *)keyPath;
{
    id value = [self _objectOfClass:[NSObject class] forPlistKeyPath:keyPath];
    
    // Not going to define unique exception format strings for every problem; just 'break' out to a common failure.
    do {
        if ([value isKindOfClass:[NSString class]]) {
            return [UIImage imageNamed:value];
        }
        
        if ([value isKindOfClass:[NSDictionary class]]) {
            NSDictionary *plist = value;
            
            NSString *name = plist[@"name"];
            if (!name) {
                break;
            }
            
            NSBundle *bundle = nil;
            NSString *bundleIdentifier = plist[@"bundle"];
            if (bundleIdentifier) {
                if (![bundleIdentifier isKindOfClass:[NSString class]]) {
                    break;
                }
                if ([bundleIdentifier isEqual:@"self"]) {
                    bundle = [NSBundle bundleForClass:[self class]];
                } else if ([bundleIdentifier isEqual:@"main"]) {
                    bundle = [NSBundle mainBundle];
                } else {
                    bundle = [NSBundle bundleWithIdentifier:bundleIdentifier];
                }
                if (!bundle) {
                    // Bundle specified, but not found
                    break;
                }
            }
            
            UIImage *image;
            if (bundle) {
                image = [UIImage imageNamed:name inBundle:bundle compatibleWithTraitCollection:nil];
            } else {
                image = [UIImage imageNamed:name];
            }
            if (!image) {
                break;
            }
            
            return image;
        }
    } while (0);
    
    @throw [NSException exceptionWithName:NSInvalidArgumentException reason:[NSString stringWithFormat:@"Unexpected value for image at key path component '%@' in appearance '%@': %@", keyPath, NSStringFromClass([self class]), value] userInfo:nil];
}

#else // !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
- (NSImage *)imageForKeyPath:(NSString *)keyPath;
{
    id value = [self _objectOfClass:[NSObject class] forPlistKeyPath:keyPath];

    // Not going to define unique exception format strings for every problem; just 'break' out to a common failure.
    do {
        if ([value isKindOfClass:[NSString class]]) {
            return [NSImage imageNamed:value];
        }
        
        if ([value isKindOfClass:[NSDictionary class]]) {
            NSDictionary *plist = value;
            
            NSString *name = plist[@"name"];
            if (!name)
                break;

            NSBundle *bundle = nil;
            NSString *bundleIdentifier = plist[@"bundle"];
            if (bundleIdentifier) {
                if (![bundleIdentifier isKindOfClass:[NSString class]])
                    break;
                if ([bundleIdentifier isEqual:@"self"])
                    bundle = [NSBundle bundleForClass:[self class]];
                else if ([bundleIdentifier isEqual:@"main"])
                    bundle = [NSBundle mainBundle];
                else
                    bundle = [NSBundle bundleWithIdentifier:bundleIdentifier];
                if (!bundle) {
                    // Bundle specified, but not found
                    break;
                }
            }
            
            NSImage *image;
            if (bundle)
                image = [bundle imageForResource:name];
            else
                image = [NSImage imageNamed:name];
            if (!image)
                break;
            
            id colorValue = plist[@"color"];
            if (colorValue) {
                OUI_SYSTEM_COLOR_CLASS *color = nil;
                
                if ([colorValue isKindOfClass:[NSString class]]) {
                    color = [self colorForKeyPath:colorValue];
                } else if ([colorValue isKindOfClass:[NSDictionary class]]) {
                    color = [[OQColor colorFromPropertyListRepresentation:colorValue] toColor];
                }
                
                if (!color)
                    break;
                
                return [image imageByTintingWithColor:color];
            }
        }
    } while (0);
    
    @throw [NSException exceptionWithName:NSInvalidArgumentException reason:[NSString stringWithFormat:@"Unexpected value for image at key path component '%@' in appearance '%@': %@", keyPath, NSStringFromClass([self class]), value] userInfo:nil];
}
#endif

#pragma mark - Dynamic accessors

static objc_property_t _propertyForSelectorInClass(SEL invocationSel, Class cls)
{
    unsigned int propertyCount;
    objc_property_t *allProperties = class_copyPropertyList(cls, &propertyCount);
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

+ (objc_property_t)_propertyForSelector:(SEL)invocationSel;
{
    objc_property_t backingProp = NULL;
    Class cls = self;
    do {
        backingProp = _propertyForSelectorInClass(invocationSel, cls);
        cls = class_getSuperclass(cls);
    } while (backingProp == NULL && (cls != Nil));
    
    return backingProp;
}

+ (void)_synthesizeGetter:(SEL)invocationSel forProperty:(objc_property_t)backingProp;
{
    const char *backingPropName = property_getName(backingProp);
    
    char *backingPropReadonly = property_copyAttributeValue(backingProp, "R");
    if (!backingPropReadonly)
        @throw [NSException exceptionWithName:NSInvalidArgumentException reason:[NSString stringWithFormat:@"Property declaration for '%@' must be readonly.", [NSString stringWithUTF8String:backingPropName]] userInfo:nil];
    free(backingPropReadonly);
    
    char *backingPropType = property_copyAttributeValue(backingProp, "T");
    
    IMP getterImp;
    char *getterTypes;
    
    MakeImpForProperty(self, [NSString stringWithUTF8String:backingPropName], backingPropType, invocationSel, &getterImp, &getterTypes);
    free(backingPropType);
    
    class_addMethod(self, invocationSel, getterImp, getterTypes);
    
    free(getterTypes);
}

/*! outImpTypes must be free()d. */
static void MakeImpForProperty(Class implementationCls, NSString *backingPropName, const char *type, SEL invocationSel, IMP *outImp, char **outImpTypes)
{
    
    // This function provides a variety of very similar dynamic getter implementations for the different return types that OUIAppearance supports (color, edge inset, size, float, bool, etc.). Each implementation has built-in caching for the fetched object, so that the caller can avoid doing its own (potentially incorrect) caching work.
    // For performance reasons, we avoid NSCache and NSMutableDictionary. The former has unreasonably high time overhead, and the latter was still suffering degraded speeds (compared to a call-site dispatch_once() cache).
    // Instead, this function uses __block variables to provide storage for cached values, which are then captured by the block provided to imp_implementationWithBlock(). That function, in turn, is documented to Block_copy() the provided block, extending the lifetime of those __block variables past the end of a call to this function.
    // For a more thorough discussion of __block variables, see "The __block Storage Type" at https://developer.apple.com/library/ios/documentation/Cocoa/Conceptual/Blocks/Articles/bxVariables.html#//apple_ref/doc/uid/TP40007502-CH6-SW6. (Note that Apple's discussion of "lexical scope" can be confusing – the __block variables here are preserved past the end of a single call to this function by the implementation block, but subsequent calls to this function will allocate new storage for the new implementation block being created.)
    
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
        Class valueClass = objc_getClass(className);
        
        if (!valueClass) {
            @throw [NSException exceptionWithName:NSInvalidArgumentException reason:[NSString stringWithFormat:@"Unknown class '%@' for key '%@'", [NSString stringWithUTF8String:className], backingPropName] userInfo:nil];
        } else if (valueClass == [OUI_SYSTEM_COLOR_CLASS class]) {
            __block OUI_SYSTEM_COLOR_CLASS *cachedColor = nil;
            __block NSUInteger localInvalidationCount = 0;
            
            *outImp = imp_implementationWithBlock(^(id self) {
                NSUInteger globalInvalidationCount = ((OUIAppearance *)self)->_cacheInvalidationCount;
                if (localInvalidationCount < globalInvalidationCount) {
                    OUI_SYSTEM_COLOR_CLASS *color = [self colorForKeyPath:backingPropName];
                    DEBUG_DYNAMIC_GETTER(@"colorForKeyPath:%@ --> %@", backingPropName, color);
                    cachedColor = color;
                    localInvalidationCount = globalInvalidationCount;
                }
                
                return cachedColor;
            });
        } else if (valueClass == [OQColor class]){
            __block OQColor *cachedColor = nil;
            __block NSUInteger localInvalidationCount = 0;
            
            *outImp = imp_implementationWithBlock(^(id self) {
                NSUInteger globalInvalidationCount = ((OUIAppearance *)self)->_cacheInvalidationCount;
                if (localInvalidationCount < globalInvalidationCount) {
                    OQColor *color = [self OQColorForKeyPath:backingPropName];
                    DEBUG_DYNAMIC_GETTER(@"OQColorForKeyPath:%@ --> %@", backingPropName, color);
                    cachedColor = color;
                    localInvalidationCount = globalInvalidationCount;
                }
                
                return cachedColor;
            });
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
        } else if (valueClass == [UIImage class]) {
            __block UIImage *cachedImage = nil;
            __block NSUInteger localInvalidationCount = 0;
            
            *outImp = imp_implementationWithBlock(^(id self) {
                NSUInteger globalInvalidationCount = ((OUIAppearance *)self)->_cacheInvalidationCount;
                if (localInvalidationCount < globalInvalidationCount) {
                    UIImage *image = [self imageForKeyPath:backingPropName];
                    DEBUG_DYNAMIC_GETTER(@"imageForKeyPath:%@ --> %@", backingPropName, image);
                    cachedImage = image;
                    localInvalidationCount = globalInvalidationCount;
                }
                
                return cachedImage;
            });
#else // !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
        } else if (valueClass == [NSImage class]) {
            __block NSImage *cachedImage = nil;
            __block NSUInteger localInvalidationCount = 0;
            
            *outImp = imp_implementationWithBlock(^(id self) {
                NSUInteger globalInvalidationCount = ((OUIAppearance *)self)->_cacheInvalidationCount;
                if (localInvalidationCount < globalInvalidationCount) {
                    NSImage *image = [self imageForKeyPath:backingPropName];
                    DEBUG_DYNAMIC_GETTER(@"imageForKeyPath:%@ --> %@", backingPropName, image);
                    cachedImage = image;
                    localInvalidationCount = globalInvalidationCount;
                }
                
                return cachedImage;
            });
#endif
        } else {
            __block id cachedObject = nil;
            __block NSUInteger localInvalidationCount = 0;
            
            *outImp = imp_implementationWithBlock(^(id self) {
                NSUInteger globalInvalidationCount = ((OUIAppearance *)self)->_cacheInvalidationCount;
                if (localInvalidationCount < globalInvalidationCount) {
                    id object = [self _objectOfClass:valueClass forPlistKeyPath:backingPropName];
                    DEBUG_DYNAMIC_GETTER(@"_objectOfClass:%@ forPlistKeyPath:%@ --> %@", NSStringFromClass(cls), backingPropName, object);
                    cachedObject = object;
                    localInvalidationCount = globalInvalidationCount;
                }
                
                return cachedObject;
            });
        }
        
        free(className);
    } else if (strcmp(type, @encode(float)) == 0) {
        returnType = @encode(float);
        
        __block float cachedResult = 0;
        __block NSUInteger localInvalidationCount = 0;
        
        *outImp = imp_implementationWithBlock(^(id self) {
            NSUInteger globalInvalidationCount = ((OUIAppearance *)self)->_cacheInvalidationCount;
            if (localInvalidationCount < globalInvalidationCount) {
                float val = [self floatForKeyPath:backingPropName];
                DEBUG_DYNAMIC_GETTER(@"floatForKeyPath:%@ --> %f", backingPropName, val);
                cachedResult = val;
                localInvalidationCount = globalInvalidationCount;
            }
            
            return cachedResult;
        });
    } else if (strcmp(type, @encode(double)) == 0) {
        returnType = @encode(double);
        
        __block double cachedResult = 0;
        __block NSUInteger localInvalidationCount = 0;
        
        *outImp = imp_implementationWithBlock(^(id self) {
            NSUInteger globalInvalidationCount = ((OUIAppearance *)self)->_cacheInvalidationCount;
            if (localInvalidationCount < globalInvalidationCount) {
                double val = [self doubleForKeyPath:backingPropName];
                DEBUG_DYNAMIC_GETTER(@"doubleForKeyPath:%@ --> %f", backingPropName, val);
                cachedResult = val;
                localInvalidationCount = globalInvalidationCount;
            }
            
            return cachedResult;
        });
    } else if (strcmp(type, @encode(BOOL)) == 0) {
        returnType = "c";

        __block BOOL cachedBool = NO;
        __block NSUInteger localInvalidationCount = 0;

        *outImp = imp_implementationWithBlock(^(id self) {
            NSUInteger globalInvalidationCount = ((OUIAppearance *)self)->_cacheInvalidationCount;
            if (localInvalidationCount < globalInvalidationCount) {
                BOOL val = [self boolForKeyPath:backingPropName];
                DEBUG_DYNAMIC_GETTER(@"boolForKeyPath:%@ --> %@", backingPropName, val ? @"YES" : @"NO");
                cachedBool = val;
                localInvalidationCount = globalInvalidationCount;
            }
            
            return cachedBool;
        });
    } else if (strcmp(type, @encode(OUI_SYSTEM_EDGE_INSETS_STRUCT)) == 0) {
        returnType = @encode(OUI_SYSTEM_EDGE_INSETS_STRUCT);
        
        __block OUI_SYSTEM_EDGE_INSETS_STRUCT cachedInsets = {0};
        __block NSUInteger localInvalidationCount = 0;
        
        *outImp = imp_implementationWithBlock(^(id self) {
            NSUInteger globalInvalidationCount = ((OUIAppearance *)self)->_cacheInvalidationCount;
            if (localInvalidationCount < globalInvalidationCount) {
                OUI_SYSTEM_EDGE_INSETS_STRUCT insets = [self edgeInsetsForKeyPath:backingPropName];
                DEBUG_DYNAMIC_GETTER(@"edgeInsetsForKeyPath:%@ --> %@", backingPropName, [NSValue valueWithBytes:&insets objCType:returnType]);
                cachedInsets = insets;
                localInvalidationCount = globalInvalidationCount;
            }
            
            return cachedInsets;
        });
    } else if (strcmp(type, @encode(CGSize)) == 0) {
        returnType = @encode(CGSize);
        
        __block CGSize cachedSize = {0};
        __block NSUInteger localInvalidationCount = 0;
        
        *outImp = imp_implementationWithBlock(^(id self) {
            NSUInteger globalInvalidationCount = ((OUIAppearance *)self)->_cacheInvalidationCount;
            if (localInvalidationCount < globalInvalidationCount) {
                CGSize size = [self sizeForKeyPath:backingPropName];
                DEBUG_DYNAMIC_GETTER(@"sizeForKeyPath:%@ --> %@", backingPropName, [NSValue valueWithBytes:&size objCType:returnType]);
                cachedSize = size;
                localInvalidationCount = globalInvalidationCount;
            }
            
            return cachedSize;
        });
    } else if (strcmp(type, @encode(long)) == 0) {
        returnType = @encode(long);

        // Check if there is a class method that defines an enum name table.
        NSString *enumNameTableProperty = [[NSString alloc] initWithFormat:@"%@EnumNameTable", backingPropName];
        OFEnumNameTable *nameTable = nil;
        if ([implementationCls respondsToSelector:NSSelectorFromString(enumNameTableProperty)]) {
            nameTable = [implementationCls valueForKey:enumNameTableProperty];
        }

        __block long cachedValue = {0};
        __block NSUInteger localInvalidationCount = 0;
        
        *outImp = imp_implementationWithBlock(^(id self) {
            NSUInteger globalInvalidationCount = ((OUIAppearance *)self)->_cacheInvalidationCount;
            if (localInvalidationCount < globalInvalidationCount) {
                long value;
                if (nameTable) {
                    NSString *name = [self stringForKeyPath:backingPropName];
                    value = [nameTable enumForName:name];
                    DEBUG_DYNAMIC_GETTER(@"stringForKeyPath:%@ --> %@", backingPropName, name);
                } else {
                    value = [self integerForKeyPath:backingPropName];
                    DEBUG_DYNAMIC_GETTER(@"integerForKeyPath:%@ --> %ld", backingPropName, value);
                }
                cachedValue = value;
                localInvalidationCount = globalInvalidationCount;
            }
            
            return cachedValue;
        });
    } else {
        @throw [NSException exceptionWithName:NSInvalidArgumentException reason:[NSString stringWithFormat:@"Unsupported type encoding '%@' for plist key '%@'", [NSString stringWithUTF8String:type], backingPropName] userInfo:nil];
    }
    
    size_t returnTypeLength = strlen(returnType);
    char *buf = malloc(returnTypeLength + 3);
    strncpy(buf, returnType, returnTypeLength);
    strncpy(buf + returnTypeLength, "@:", 2);
    buf[returnTypeLength + 2] = '\0';
    *outImpTypes = buf;
}

+ (BOOL)resolveInstanceMethod:(SEL)name
{
    objc_property_t backingProperty = [self _propertyForSelector:name];
    if (backingProperty) {
        [self _synthesizeGetter:name forProperty:backingProperty];
        return YES;
    } else {
        return [super resolveInstanceMethod:name];
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

#pragma mark - Subclass Conveniences

@implementation OUIAppearance (Subclasses)

+ (OUIAppearance *)appearanceForClass:(Class)cls;
{
    OBASSERT([cls isSubclassOfClass:[OUIAppearance class]]);
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        ClassToAppearanceMap = [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsObjectPointerPersonality valueOptions:NSPointerFunctionsObjectPersonality];
    });
    
    OUIAppearance *appearance = [ClassToAppearanceMap objectForKey:cls];
    if (!appearance) {
        appearance = [[cls alloc] _initWithPlistName:NSStringFromClass(cls) inBundle:[NSBundle bundleForClass:cls]];
        OBASSERT_NOTNULL(appearance);
        
        [appearance beginPresentingUserPlistIfNecessary];
        
        [ClassToAppearanceMap setObject:appearance forKey:cls];
    }
    
    return appearance;
}

@end

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE

#pragma mark - Mac Convenience Accessors

static NSColor *SelectionBorderColor;
static id SystemColorsObserver;

static void EnsureSystemColorsObserver(OUIAppearance *self)
{
    if (!SystemColorsObserver) {
        SystemColorsObserver = [[NSNotificationCenter defaultCenter] addObserverForName:NSSystemColorsDidChangeNotification object:nil queue:nil usingBlock:^(NSNotification *unused){
            [[NSNotificationCenter defaultCenter] postNotificationName:OUIAppearanceValuesWillChangeNotification object:self];

            SelectionBorderColor = nil;
            
            [[NSNotificationCenter defaultCenter] postNotificationName:OUIAppearanceValuesDidChangeNotification object:self];
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
    EnsureSystemColorsObserver(nil);
    
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

@implementation OUIAppearance (OmniUIAppearance)
@dynamic emptyOverlayViewLabelMaxWidthRatio;
@dynamic overlayInspectorWindowHeightFraction;
@dynamic overlayInspectorTopSeparatorColor;
@dynamic navigationBarTextFieldBackgroundImageInsets;
@dynamic navigationBarTextFieldLineHeightMultiplier;
@end

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

/// Soft-deprecated. Use [OUIAppearanceColors appearance].omniRedColor
+ (UIColor *)omniRedColor;
{
    return [OUIAppearanceDefaultColors appearance].omniRedColor;
}

/// Soft-deprecated. Use [OUIAppearanceColors appearance].omniOrangeColor
+ (UIColor *)omniOrangeColor;
{
    return [OUIAppearanceDefaultColors appearance].omniOrangeColor;
}

/// Soft-deprecated. Use [OUIAppearanceColors appearance].omniYellowColor
+ (UIColor *)omniYellowColor;
{
    return [OUIAppearanceDefaultColors appearance].omniYellowColor;
}

/// Soft-deprecated. Use [OUIAppearanceColors appearance].omniGreenColor
+ (UIColor *)omniGreenColor;
{
    return [OUIAppearanceDefaultColors appearance].omniGreenColor;
}

/// Soft-deprecated. Use [OUIAppearanceColors appearance].omniTealColor
+ (UIColor *)omniTealColor;
{
    return [OUIAppearanceDefaultColors appearance].omniTealColor;
}

/// Soft-deprecated. Use [OUIAppearanceColors appearance].omniBlueColor
+ (UIColor *)omniBlueColor;
{
    return [OUIAppearanceDefaultColors appearance].omniBlueColor;
}

/// Soft-deprecated. Use [OUIAppearanceColors appearance].omniPurpleColor
+ (UIColor *)omniPurpleColor;
{
    return [OUIAppearanceDefaultColors appearance].omniPurpleColor;
}

/// Soft-deprecated. Use [OUIAppearanceColors appearance].omniGraphiteColor
+ (UIColor *)omniGraphiteColor;
{
    return [OUIAppearanceDefaultColors appearance].omniGraphiteColor;
}

/// Soft-deprecated. Use [OUIAppearanceColors appearance].omniCremaColor
+ (UIColor *)omniCremaColor;
{
    return [OUIAppearanceDefaultColors appearance].omniCremaColor;
}

/// Soft-deprecated. Use [OUIAppearanceColors appearance].omniAlternateRedColor
+ (UIColor *)omniAlternateRedColor;
{
    return [OUIAppearanceDefaultColors appearance].omniAlternateRedColor;
}

/// Soft-deprecated. Use [OUIAppearanceColors appearance].omniAlternateYellowColor
+ (UIColor *)omniAlternateYellowColor;
{
    return [OUIAppearanceDefaultColors appearance].omniAlternateYellowColor;
}

/// Soft-deprecated. Use [OUIAppearanceColors appearance].omniNeutralDeemphasizedColor
+ (UIColor *)omniNeutralDeemphasizedColor;
{
    return [OUIAppearanceDefaultColors appearance].omniNeutralDeemphasizedColor;
}

/// Soft-deprecated. Use [OUIAppearanceColors appearance].omniNeutralPlaceholderColor
+ (UIColor *)omniNeutralPlaceholderColor;
{
    return [OUIAppearanceDefaultColors appearance].omniNeutralPlaceholderColor;
}

/// Soft-deprecated. Use [OUIAppearanceColors appearance].omniNeutralLightweightColor
+ (UIColor *)omniNeutralLightweightColor;
{
    return [OUIAppearanceDefaultColors appearance].omniNeutralLightweightColor;
}

/// Soft-deprecated. Use [OUIAppearanceColors appearance].omniDeleteColor
+ (UIColor *)omniDeleteColor;
{
    return [OUIAppearanceDefaultColors appearance].omniDeleteColor;
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

#pragma mark -

#if OUI_PERFORM_FILE_PRESENTATION

@implementation OUIAppearanceUserPlistFilePresenter

- (instancetype)initWithOwner:(OUIAppearance *)owner;
{
    self = [super init];
    if (self == nil) {
        return nil;
    }
    
    _weak_owner = owner;
    
    _userPlistPresentationQueue = [[NSOperationQueue alloc] init];
    _userPlistPresentationQueue.maxConcurrentOperationCount = 1;

    return self;
}

- (NSURL *)presentedItemURL;
{
    return [_weak_owner userPlistURL];
}

- (NSOperationQueue *)presentedItemOperationQueue;
{
    OBPRECONDITION(_userPlistPresentationQueue != nil, @"Should have set up an operation queue in our intializer.");
    return _userPlistPresentationQueue;
}

- (void)presentedItemDidChange;
{
    // This is called on the `_userPlistPresentationQueue` queue. Invalidate and recache back on the main queue.
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        [_weak_owner invalidateCachedValues];
    }];
}

- (void)presentedItemDidMoveToURL:(NSURL *)newURL;
{
    // We deliberately continue presenting the same file URL here so that if the file comes back, we will continue receiving notifications
    // This is called on the `_userPlistPresentationQueue` queue. Invalidate and recache back on the main queue.
    
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        [_weak_owner invalidateCachedValues];
    }];
}

- (void)accommodatePresentedItemDeletionWithCompletionHandler:(void (^)(NSError *))completionHandler;
{
    // We deliberately continue presenting the same file URL here so that if the file comes back, we will continue receiving notifications
    // This is called on the `_userPlistPresentationQueue` queue. Invalidate and recache back on the main queue.
    
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        [_weak_owner invalidateCachedValues];
    }];
    
    completionHandler(nil);
}

@end

#endif // OUI_PERFORM_FILE_PRESENTATION
