// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OAAppearance.h>

@import OmniFoundation;

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
#import <OmniAppKit/OAAppearanceColors.h>
#import <UIKit/UIKit.h>
#else
#import <OmniAppKit/NSColor-OAExtensions.h>
#import <OmniAppKit/NSImage-OAExtensions.h>
#endif

#import "OAAppearance-Internal.h"

#import <OmniAppKit/OAColor-Archiving.h>
#import <objc/runtime.h>
#import <OmniBase/rcsid.h>
#import <OmniBase/OBUtilities.h>

NSString * const OAAppearanceAliasesKey = @"OAAppearanceAliases";
NSString * const OAAppearancePlistExtension = @"plist";
NSString * const OAAppearanceValuesWillChangeNotification = @"com.omnigroup.framework.OmniAppKit.Appearance.ValuesWillChange";
NSString * const OAAppearanceValuesDidChangeNotification = @"com.omnigroup.framework.OmniAppKit.Appearance.ValuesDidChange";
NSString * const OAAppearancePrivateClassNamePrefix = @"__PrivateReifying_";

NSString * const OAAppearanceErrorDomain = @"com.omnigroup.OmniAppKit.OAAppearance";

typedef NS_ENUM(NSUInteger, OAAppearanceSupportedType) {
    OAAppearanceSupportedTypeSystemColor,
    OAAppearanceSupportedTypeOAColor,
    OAAppearanceSupportedTypeSystemImage,
    OAAppearanceSupportedTypeObject,
    OAAppearanceSupportedTypeFloat,
    OAAppearanceSupportedTypeDouble,
    OAAppearanceSupportedTypeBool,
    OAAppearanceSupportedTypeSystemEdgeInsets,
    OAAppearanceSupportedTypeSize,
    OAAppearanceSupportedTypeLong,
};

static NSString *nameForSupportedType(OAAppearanceSupportedType type, Class cls)
{
    // intentionally not localized as tags in the plist are not localized
    switch (type) {
        case OAAppearanceSupportedTypeSystemColor: return @"color";
        case OAAppearanceSupportedTypeOAColor: return @"color";
        case OAAppearanceSupportedTypeSystemImage: return @"image name";
        case OAAppearanceSupportedTypeObject: return NSStringFromClass(cls);
        case OAAppearanceSupportedTypeFloat: return @"real";
        case OAAppearanceSupportedTypeDouble: return @"real";
        case OAAppearanceSupportedTypeBool: return @"boolean";
        case OAAppearanceSupportedTypeSystemEdgeInsets: return @"edge insets";
        case OAAppearanceSupportedTypeSize: return @"size";
        case OAAppearanceSupportedTypeLong: return @"int";
    }
}

#define OA_PERFORM_FILE_PRESENTATION (!defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE)

#if OA_PERFORM_FILE_PRESENTATION

@interface OAAppearanceUserPlistFilePresenter : NSObject <NSFilePresenter> {
  @private
    __weak OAAppearance *_weak_owner;
    NSOperationQueue *_userPlistPresentationQueue;
}

- (instancetype)initWithOwner:(OAAppearance *)owner;

@end

#endif // OA_PERFORM_FILE_PRESENTATION

RCS_ID("$Id$")

static NSMapTable *PublicClassToAppearanceMap = nil;
static NSMapTable *PrivateReifyingClassToAppearanceMap = nil;
static NSMutableSet *InvalidatedClassesForSwitchedPlistURLDirectories = nil;

@interface OAAppearance () {
  @private
    BOOL _isInvalidatingCachedValues;
    NSDictionary *_plist;
#if OA_PERFORM_FILE_PRESENTATION
    OAAppearanceUserPlistFilePresenter *_userPlistFilePresenter;
#endif
}

@property (nonatomic, copy) NSString *plistName;
@property (nonatomic, strong) NSBundle *plistBundle;
@property (nonatomic, strong) NSURL *optionalPlistDirectoryURL;

/// A collection of weak pointers to known subclass singletons. Used to propagate invalidations when a superclass plist changes.
@property (nonatomic, strong) NSPointerArray *subclassSingletons;

@end

@implementation OAAppearance

+ (void)initialize
{
    OBINITIALIZE;
    InvalidatedClassesForSwitchedPlistURLDirectories = [NSMutableSet new];
}

#pragma mark - Lifecycle

- (id)_initWithPlistName:(NSString *)plistName inBundle:(NSBundle *)bundle;
{
    if (!(self = [super init]))
        return nil;

    _plistName = [plistName copy];
    _plistBundle = bundle;
    _optionalPlistDirectoryURL = [[self class] directoryURLForSwitchablePlist];
    
    [self recachePlistFromFile];

    return self;
}

- (id)_initForValidationWithDirectoryURL:(NSURL *)url;
{
    if (!(self = [super init]))
        return nil;
    
    _plistName = NSStringFromClass([self class]);
    _plistBundle = nil;
    _optionalPlistDirectoryURL = url;
    
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

+ (instancetype)sharedAppearance;
{
    return [self appearance];
}

static NSString *_OUIAppearanceUserOverrideFolder = nil;

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE

void OAAppearanceSetUserOverrideFolder(NSString * _Nullable userOverrideFolder)
{
    if (OFNOTEQUAL(_OUIAppearanceUserOverrideFolder, userOverrideFolder)) {
        _OUIAppearanceUserOverrideFolder = [userOverrideFolder copy];
        
        for (Class cls in PublicClassToAppearanceMap) {
            OAAppearance *appearance = [PublicClassToAppearanceMap objectForKey:cls];
            [appearance endPresentingUserPlistIfNecessary];
        }

        [[OAAppearance appearance] invalidateCachedValues];
        
        for (Class cls in PublicClassToAppearanceMap) {
            OAAppearance *appearance = [PublicClassToAppearanceMap objectForKey:cls];
            [appearance beginPresentingUserPlistIfNecessary];
        }
    }
}

#endif

#pragma mark - NSObject subclass

/// Returns whether we should defer to `-[NSObject valueForKey:]` when looking up the value for the `keyPathComponents.
///
/// We want to do so when there is a corresponding property, because the NSObject implementation will defer to the property, hitting our cached value and using the property's declared type.
- (BOOL)_shouldUseImplementedPropertyForValueForKeyPathComponents:(NSArray <NSString *>*)keyPathComponents;
{
    if (keyPathComponents.count != 1) {
        return NO;
    }
    
    // If there is a matching property declaration, then use it.
    objc_property_t backingProperty = [[self class] _propertyForSelector:NSSelectorFromString(keyPathComponents[0]) matchGetter:NO];
    
    return (backingProperty != NULL);
}

- (id)valueForKey:(NSString *)key;
{
    NSArray <NSString *>*keyPathComponents = @[key];
    if ([self _shouldUseImplementedPropertyForValueForKeyPathComponents:keyPathComponents]) {
        return [super valueForKey:key];
    }
    
    id result = [self _valueForPlistKeyPathComponents:keyPathComponents error:NULL];
    if (result == nil) {
        result = [super valueForKey:key];
    }
    
    return result;
}

- (id)valueForKeyPath:(NSString *)keyPath;
{
    NSArray <NSString *> *keyPathComponents = OFKeysForKeyPath(keyPath);

    if ([self _shouldUseImplementedPropertyForValueForKeyPathComponents:keyPathComponents]) {
        OBASSERT(keyPathComponents.count == 1);
        NSString *key = keyPath;
        return [super valueForKey:key];
    }

    id result = [self _valueForPlistKeyPathComponents:keyPathComponents error:NULL];
    if (result == nil) {
        result = [super valueForKeyPath:keyPath];
    }

    return result;
}


#pragma mark Helpers

- (void)invalidateCachedValues;
{
    OBPRECONDITION([NSThread isMainThread]);
    if (_isInvalidatingCachedValues) {
        return;
    }
    
    _isInvalidatingCachedValues = YES;
    [[NSNotificationCenter defaultCenter] postNotificationName:OAAppearanceValuesWillChangeNotification object:self];
    [self recachePlistFromFile]; // also handles bumping cacheInvalidationCount
    [self performRelatedInvalidation];
    [[NSNotificationCenter defaultCenter] postNotificationName:OAAppearanceValuesDidChangeNotification object:self];
    _isInvalidatingCachedValues = NO;
}

- (void)beginPresentingUserPlistIfNecessary;
{
#if OA_PERFORM_FILE_PRESENTATION
    // N.B. Note that if the user plist doesn't exist when we start presenting, we won't get any notification when it does appear, but we will get one for the first change to it after it does appear.
    
    if (_userPlistFilePresenter == nil && _plistName != nil) {
        _userPlistFilePresenter = [[OAAppearanceUserPlistFilePresenter alloc] initWithOwner:self];
        [NSFileCoordinator addFilePresenter:_userPlistFilePresenter];
    }
#endif
}

- (void)endPresentingUserPlistIfNecessary;
{
#if OA_PERFORM_FILE_PRESENTATION
    if (_userPlistFilePresenter != nil) {
        [NSFileCoordinator removeFilePresenter:_userPlistFilePresenter];
        _userPlistFilePresenter = nil;
    }
#endif
}

static NSURL *urlIfExists(NSURL *url)
{
    NSError *existanceCheckError = nil;
    if (![url checkResourceIsReachableAndReturnError:&existanceCheckError]) {
        url = nil;
    }
    return url;
}

- (NSURL *)_plistURL
{
    NSArray <NSString *> *possibleNames = @[[_plistName stringByAppendingString:@"Appearance"], _plistName];
    NSURL *plistURL = nil;
    if (_optionalPlistDirectoryURL != nil) {
        for (NSString *name in possibleNames) {
            plistURL = urlIfExists([[_optionalPlistDirectoryURL URLByAppendingPathComponent:name] URLByAppendingPathExtension:OAAppearancePlistExtension].filePathURL);
            if (plistURL != nil) {
                return plistURL;
            }
        }
    }
    
    for (NSString *name in possibleNames) {
        plistURL = [_plistBundle URLForResource:name withExtension:OAAppearancePlistExtension];
        if (plistURL != nil) {
            return plistURL;
        }
    }
    
    return nil;
}

- (void)recachePlistFromFile;
{
    if (_plistName == nil) {
        _plist = @{};
        _cacheInvalidationCount ++;
        return;
    }
    
    NSURL *plistURL = [self _plistURL];
    
    if (plistURL != nil) {
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

#if OA_PERFORM_FILE_PRESENTATION
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
    
#ifdef OMNI_ASSERTIONS_ON
    [self validateDynamicPropertyDeclarations];
#endif
    
    _cacheInvalidationCount ++;
}

#ifdef OMNI_ASSERTIONS_ON
- (NSMutableSet <NSString *> *)_nonDynamicPropertyNames;
{
    NSMutableSet *result = [NSMutableSet new];
    
    Class cls = self.class;
    do {
        unsigned int propertyCount;
        objc_property_t *allProperties = class_copyPropertyList(cls, &propertyCount);
        
        for (unsigned int i = 0; i < propertyCount; i++) {
            objc_property_t property = allProperties[i];
            SEL selector = sel_getUid(property_getName(property));
            char *propertyIsDynamic = property_copyAttributeValue(property, "D");
            if (propertyIsDynamic == NULL) {
                // not dynamic
                NSString *propertyName = NSStringFromSelector(selector);
                [result addObject:propertyName];
            }
            free(propertyIsDynamic);
        }
        
        free(allProperties);
        
        cls = [cls superclass];
    } while (cls != Nil);
    
    return result;
}

- (void)validateDynamicPropertyDeclarations
{
    OBASSERT_NOTNULL(_plist);
    
    NSMutableSet *propertyNames = [self _nonDynamicPropertyNames];
    NSSet *plistKeys = [NSSet setWithArray:[_plist allKeys]];
    
    [propertyNames intersectSet:plistKeys];
    if (propertyNames.count != 0) {
        for (NSString *propertyName in propertyNames) {
            NSLog(@"%@ missing @dynamic declaration for declared property “%@“ that has a corresponding plist key.", NSStringFromClass([self class]), propertyName);
        }
        OBASSERT_NOT_REACHED(@"Expect the declared properties on an OAAppearance class to be dynamic if they have corresponding keys in the plist. See details logged above.");
        assert(propertyNames.count == 0);
    }
}
#endif


/// Returns the URL for the user override appearance plist.
- (NSURL *)userPlistURL;
{
    if (_OUIAppearanceUserOverrideFolder == nil)
        return nil;

    NSString *userPlistPath = [[_OUIAppearanceUserOverrideFolder stringByAppendingPathComponent:_plistName] stringByAppendingPathExtension:OAAppearancePlistExtension];
    
    return [NSURL fileURLWithPath:userPlistPath];
}

#pragma mark - Static accessors

- (id)_valueForPlistKeyPathComponents:(NSArray <NSString *> *)keyPathComponents error:(NSError **)error;
{
    // Can enable this to check if appearance values are being looked up on commonly hit drawing paths.
#if 0 && defined(DEBUG)
    NSLog(@"Looking up %@ in %@", keyPathComponents, self);
#endif
    
    id obj = _plist;
    NSUInteger keyCount = keyPathComponents.count;
    for (NSUInteger idx = 0; idx < keyCount; idx++) {
        NSString *key = keyPathComponents[idx];
        id parentObj = obj;
        obj = [obj objectForKey:key];
        BOOL isLastPathComponent = idx == keyCount - 1;
        Class expectedClass = isLastPathComponent ? [NSObject class] : [NSDictionary class];
        
        if (!obj) {
            // First try to find an alias for the given key
            NSDictionary *aliases = [parentObj objectForKey:OAAppearanceAliasesKey];
            if (aliases != nil) {
                NSString *alias = [aliases objectForKey:key];
                if (alias != nil) {
                    // Found an alias; restart the search at the top level for the resultant target key path.
                    // We allow aliases inside other structures, treating them as absolute references. We also allow aliases to themselves be keypaths. So, the new key path is the alias followed by the portion of the original keypath not yet traversed. For example, if the original path is A.B.C and A.B is the path to an alias with value X.Y, then our new path should be X.Y.C.
                    NSArray <NSString *> *newKeyPathComponents = OFKeysForKeyPath(alias);
                    if (!isLastPathComponent) {
                        NSUInteger nextIndex = idx + 1;
                        NSArray <NSString *> *remainingKeyPathComponents = [keyPathComponents subarrayWithRange:NSMakeRange(nextIndex, keyCount - nextIndex)];
                        newKeyPathComponents = [newKeyPathComponents arrayByAddingObjectsFromArray:remainingKeyPathComponents];
                    }
                    
                    return [self _valueForPlistKeyPathComponents:newKeyPathComponents error:error];
                }
            }
            
            // If no alias exists, either fall back to the superclass or throw, depending on what class this is
            if ([self class] == [OAAppearance class]) {
                if (error != NULL) {
                    NSDictionary *info = @{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"No object found for key path component '%@'", key]};
                    *error = [NSError errorWithDomain:OAAppearanceErrorDomain code:OAAppearanceErrorCodeKeyNotFound userInfo:info];
                }
                return nil;
            } else {
                // Recurse into the actual hierarchy, where the plists live
                OAAppearance *superApperance = [[self class] _appearanceForClass:[self superclass] reifyingInstance:NO];
                return [superApperance _valueForPlistKeyPathComponents:keyPathComponents error:error];
            }
        } else if (![obj isKindOfClass:expectedClass]) {
            if (error != NULL) {
                NSDictionary *info = @{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Object for key path component '%@' in appearance '%@' is not an instance of expected class '%@'", key, NSStringFromClass([self class]), NSStringFromClass(expectedClass)]};
                *error = [NSError errorWithDomain:OAAppearanceErrorDomain code:OAAppearanceErrorCodeUnexpectedValueType userInfo:info];
            }
            return nil;
        }
    };
    
    return obj;
}

- (id)_objectOfClass:(Class)cls forPlistKeyPath:(NSString *)keyPath;
{
    NSArray *keyPathComponents = OFKeysForKeyPath(keyPath);
    NSError *error = nil;
    id result = [self _valueForPlistKeyPathComponents:keyPathComponents error:&error];
    if (result == nil) {
        @throw [NSException exceptionWithName:NSInvalidArgumentException reason:error.localizedDescription userInfo:nil];
    } else if (![result isKindOfClass:cls]) {
        @throw [NSException exceptionWithName:NSInvalidArgumentException reason:[NSString stringWithFormat:@"Object for keyPath '%@' in appearance '%@' is not an instance of expected class '%@'", keyPath, NSStringFromClass([self class]), NSStringFromClass(cls)] userInfo:nil];
    }
    
    return result;
}

- (OAAppearanceValueEncoding)valueEncodingForKeyPath:(NSString *)keyPath;
{
    static NSSet <NSString *> *sizeEncodingKeys;
    static NSSet <NSString *> *edgeInsetsEncodingKeys;
    static Class platformImageClass;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sizeEncodingKeys = [NSSet setWithArray:@[@"width", @"height"]];
        edgeInsetsEncodingKeys = [NSSet setWithArray:@[@"top", @"left", @"bottom", @"right"]];
#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
        platformImageClass = [NSImage class];
#else
        platformImageClass = [UIImage class];
#endif
    });
    
    // Use the type of the value at the keyPath as a first approximation of the encoding, looking at the underlying representation in the plist to differentiate if necessary.
    NSObject *currentValue = [self valueForKeyPath:keyPath];
    NSObject *currentEncoding = [self _objectOfClass:[NSObject class] forPlistKeyPath:keyPath];
    NSDictionary *currentEncodingDictionary = nil;
    if ([currentEncoding isKindOfClass:[NSDictionary class]]) {
        currentEncodingDictionary = (NSDictionary *)currentEncoding;
    }
    
    if ([currentValue isKindOfClass:[OA_SYSTEM_COLOR_CLASS class]]) {
        OAColorSpace colorSpace;
        BOOL colorSpaceDetected = currentEncodingDictionary != nil && [OAColor colorSpaceOfPropertyListRepresentation:currentEncodingDictionary colorSpace:&colorSpace];
        if (colorSpaceDetected) {
            switch (colorSpace) {
                case OAColorSpaceWhite: return OAAppearanceValueEncodingWhiteColor;
                case OAColorSpaceRGB: return OAAppearanceValueEncodingRGBColor;
                case OAColorSpaceHSV:
                case OAColorSpaceCMYK:
                    // both HSV and CMYK are written in HSB
                    return OAAppearanceValueEncodingHSBColor;
                default:
                    OBASSERT_NOT_REACHED(@"unimplemented color space conversion for keyPath: %@, colorSpace: %@", keyPath, @(colorSpace));
                    break;
            }
        }
        // default to HSB
        return OAAppearanceValueEncodingHSBColor;
    } else if ([currentValue isKindOfClass:[NSDictionary class]]) {
        return OAAppearanceValueEncodingRaw;
    } else if ([currentValue isKindOfClass:platformImageClass]) {
        return OAAppearanceValueEncodingCustom;
    } else if ([currentValue isKindOfClass:[NSValue class]] && currentEncodingDictionary != nil) {
        NSSet <NSString *> *currentEncodingKeys = [NSSet setWithArray:[currentEncodingDictionary allKeys]];
        if ([currentEncodingKeys isEqualToSet:sizeEncodingKeys]) {
            return OAAppearanceValueEncodingSize;
        } else if ([currentEncodingKeys isEqualToSet:edgeInsetsEncodingKeys]) {
            return OAAppearanceValueEncodingEdgeInsets;
        }
        OBASSERT_NOT_REACHED(@"Unexpected encoding for keyPath “%@” with NSValue type: %@", keyPath, currentEncodingDictionary);
        return OAAppearanceValueEncodingRaw;
    }
    
    // Having failed to draw any other conclusion, fall back to just a raw property list encoding.
    return OAAppearanceValueEncodingRaw;
}

- (NSObject *)customEncodingForKeyPath:(NSString *)keyPath;
{
    OBPRECONDITION([self valueEncodingForKeyPath:keyPath] == OAAppearanceValueEncodingCustom);
    
    // We should only get here for images, whose encoding could be either a string or a dictionary.
    NSObject *currentEncoding = [self _objectOfClass:[NSObject class] forPlistKeyPath:keyPath];
    OBASSERT([currentEncoding isKindOfClass:[NSDictionary class]] || [currentEncoding isKindOfClass:[NSString class]], @"Unexpected encoding for keyPath “%@”: %@", keyPath, currentEncoding);

    // Just return the current encoding, skipping the normalization that -[OAAppearancePropertyListCoder _encodedValueForKeyPath:] provides for other value encodings.
    return currentEncoding;
}

- (BOOL)validateValueAtKeyPath:(NSString *)keyPath error:(NSError **)error;
{
    // Attempt a look-up. If it raises, then the data was bad
    // These are used for error reporting in the `catch` block, so need to be declared before the `try`.
    NSString *backingPropName = nil;
    NSString *expectedTypeName = nil;
    
    @try {
        NSArray *components = OFKeysForKeyPath(keyPath);
        if (components.count > 1) {
            // We don't have a great way to check the expected type of keyPath with this architecture. For now, check that we can at least get some value. If this becomes a problem in practice, we may need to pass in an expected type somehow.
            // For example, the coder, which calls us, could use a known good codeable plus an instance of the thing to be validated. The known good codeable could be queried for a value, then the type of that value could be passed in to this method on the object to be validated.
            id value = [self _valueForPlistKeyPathComponents:components error:error];
            BOOL result = (value != nil);
            return result;
        }

        NSString *key = components.firstObject;
        OBASSERT(key != nil);

        objc_property_t backingProperty = [[self class] _propertyForSelector:NSSelectorFromString(key) matchGetter:YES];
        OAAppearanceSupportedType type;
        Class optionalTypeClass;
        backingPropName = nameForBackingProp(backingProperty, &type, &optionalTypeClass);
        expectedTypeName = nameForSupportedType(type, optionalTypeClass);
        
        switch (type) {
            case OAAppearanceSupportedTypeSystemColor: {
                [self colorForKeyPath:backingPropName];
                break;
            }
            case OAAppearanceSupportedTypeOAColor: {
                [self OAColorForKeyPath:backingPropName];
                break;
            }
            case OAAppearanceSupportedTypeSystemImage: {
                [self imageForKeyPath:backingPropName];
                break;
            }
            case OAAppearanceSupportedTypeObject: {
                OBASSERT_NOTNULL(optionalTypeClass);
                [self _objectOfClass:optionalTypeClass forPlistKeyPath:backingPropName];
                break;
            }
            case OAAppearanceSupportedTypeFloat: {
                [self floatForKeyPath:backingPropName];
                break;
            }
            case OAAppearanceSupportedTypeDouble: {
                [self doubleForKeyPath:backingPropName];
                break;
            }
            case OAAppearanceSupportedTypeBool: {
                [self boolForKeyPath:backingPropName];
                break;
            }
            case OAAppearanceSupportedTypeSystemEdgeInsets: {
                [self edgeInsetsForKeyPath:backingPropName];
                break;
            }
            case OAAppearanceSupportedTypeSize: {
                [self sizeForKeyPath:backingPropName];
                break;
            }
            case OAAppearanceSupportedTypeLong: {
                // Check if there is a class method that defines an enum name table.
                NSString *enumNameTableProperty = [[NSString alloc] initWithFormat:@"%@EnumNameTable", backingPropName];
                OFEnumNameTable *nameTable = nil;
                if ([[self class] respondsToSelector:NSSelectorFromString(enumNameTableProperty)]) {
                    nameTable = [[self class] valueForKey:enumNameTableProperty];
                }
                
                if (nameTable) {
                    expectedTypeName = @"enumeration name"; // intentionally not localized as tags in the plist are not localized
                    NSString *name = [self stringForKeyPath:backingPropName];
                    [nameTable enumForName:name];
                } else {
                    [self integerForKeyPath:backingPropName];
                }
                break;
            }
        }
        
        return YES;
    }
    @catch (NSException *exception) {
        if (error != NULL) {
            *error = [[self class] validationErrorForExpectedTypeName:expectedTypeName keyPath:backingPropName];
        }
        return NO;
    }
}

+ (NSError *)validationErrorForExpectedTypeName:(NSString *)expectedTypeName keyPath:(NSString *)keyPath;
{
    NSString *descriptionFormat = NSLocalizedStringFromTableInBundle(@"Unexpected value for key “%@”", @"OmniAppKit", [OAAppearance bundle], @"style validation error message for {key}");
    NSString *description = [NSString stringWithFormat:descriptionFormat, keyPath];
    NSString *reasonFormat = NSLocalizedStringFromTableInBundle(@"Expected value of type “%@”", @"OmniAppKit", [OAAppearance bundle], @"style validation error message for expected {type}");
    NSString *reason = [NSString stringWithFormat:reasonFormat, expectedTypeName];
    NSDictionary *userInfo = @{
        NSLocalizedDescriptionKey: description,
        NSLocalizedFailureReasonErrorKey: reason,
        NSLocalizedRecoverySuggestionErrorKey: reason,
    };
    return [NSError errorWithDomain:OAAppearanceErrorDomain code:OAAppearanceErrorCodeInvalidValueInPropertyList userInfo:userInfo];
}

- (NSString *)stringForKeyPath:(NSString * )keyPath;
{
    return [self _objectOfClass:[NSString class] forPlistKeyPath:keyPath];
}

- (NSDictionary *)dictionaryForKeyPath:(NSString *)keyPath;
{
    return [self _objectOfClass:[NSDictionary class] forPlistKeyPath:keyPath];
}

- (BOOL)isLightLuma:(CGFloat)luma;
{
    static CGFloat lightColorLimit;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        OAAppearance *appearance = [OAAppearance appearance];
        lightColorLimit = ([appearance CGFloatForKeyPath:@"OALightColorLumaLimit"]);
    });

    if (luma < lightColorLimit)
        return NO;
    else
        return YES;
}

- (OA_SYSTEM_COLOR_CLASS *)colorForKeyPath:(NSString *)keyPath;
{
    NSDictionary *archiveDictionary = [self _objectOfClass:[NSDictionary class] forPlistKeyPath:keyPath];
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    return [UIColor colorFromPropertyListRepresentation:archiveDictionary];
#else
    return [NSColor colorFromPropertyListRepresentation:archiveDictionary withColorSpaceManager:nil shouldDefaultToGenericSpace:NO];
#endif
}

- (OAColor *)OAColorForKeyPath:(NSString *)keyPath;
{
    return [OAColor colorWithPlatformColor:[self colorForKeyPath:keyPath]];
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

- (OA_SYSTEM_EDGE_INSETS_STRUCT)edgeInsetsForKeyPath:(NSString *)keyPath;
{
    NSDictionary *insetsDescription = [self _objectOfClass:[NSDictionary class] forPlistKeyPath:keyPath];
    
    static NSNumber *zero;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        zero = [NSNumber numberWithCGFloat:0];
    });
    
    OA_SYSTEM_EDGE_INSETS_STRUCT result;
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
                    Class classForBundleLookup = [self class];
                    if ([OAAppearance isReifyingClass:classForBundleLookup]) {
                        classForBundleLookup = [classForBundleLookup superclass];
                    }
                    bundle = [NSBundle bundleForClass:classForBundleLookup];
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
                if (![bundleIdentifier isKindOfClass:[NSString class]]) {
                    break;
                } else if ([bundleIdentifier isEqual:@"self"]) {
                    Class classForBundleLookup = [self class];
                    if ([OAAppearance isReifyingClass:classForBundleLookup]) {
                        classForBundleLookup = [classForBundleLookup superclass];
                    }
                    bundle = [NSBundle bundleForClass:classForBundleLookup];
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
            
            NSImage *image;
            if (bundle)
                image = [bundle imageForResource:name];
            else
                image = [NSImage imageNamed:name];
            if (!image)
                break;
            
            id colorValue = plist[@"color"];
            if (colorValue) {
                OA_SYSTEM_COLOR_CLASS *color = nil;
                
                if ([colorValue isKindOfClass:[NSString class]]) {
                    color = [self colorForKeyPath:colorValue];
                } else if ([colorValue isKindOfClass:[NSDictionary class]]) {
                    color = [[OAColor colorFromPropertyListRepresentation:colorValue] toColor];
                }
                
                if (!color)
                    break;
                
                return [image imageByTintingWithColor:color];
            }
            
            return image;
        }
    } while (0);
    
    @throw [NSException exceptionWithName:NSInvalidArgumentException reason:[NSString stringWithFormat:@"Unexpected value for image at key path component '%@' in appearance '%@': %@", keyPath, NSStringFromClass([self class]), value] userInfo:nil];
}
#endif

#pragma mark - Dynamic accessors

static objc_property_t _propertyForSelectorInClass(SEL invocationSel, Class cls, BOOL matchGetter)
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
        
        if (getterSel == invocationSel) {
            backingProp = allProperties[i];
            break;
        }
    }
    
    free(allProperties);
    
    return backingProp;
}

+ (objc_property_t)_propertyForSelector:(SEL)invocationSel matchGetter:(BOOL)matchGetter;
{
    objc_property_t backingProp = NULL;
    Class cls = self;
    do {
        backingProp = _propertyForSelectorInClass(invocationSel, cls, matchGetter);
        cls = class_getSuperclass(cls);
    } while (backingProp == NULL && (cls != Nil));
    
    return backingProp;
}

/// Looks up the name, type, and (if type is an object type) class for the given property.
static NSString *nameForBackingProp(objc_property_t backingProp, OAAppearanceSupportedType *outType, Class *outClass)
{
    const char *backingPropName = property_getName(backingProp);
    char *type = property_copyAttributeValue(backingProp, "T");
    NSString *nameString = [NSString stringWithUTF8String:backingPropName];
    *outClass = Nil;
    @try {
        if (type[0] == '@') {
            Class valueClass = classFromTypeEncoding(type);
            if (!valueClass) {
                @throw [NSException exceptionWithName:NSInvalidArgumentException reason:[NSString stringWithFormat:@"Unknown class type '%@' for key '%@'", [NSString stringWithUTF8String:type], nameString] userInfo:nil];
            } else if (valueClass == [OA_SYSTEM_COLOR_CLASS class]) {
                *outType = OAAppearanceSupportedTypeSystemColor;
            } else if (valueClass == [OAColor class]){
                *outType = OAAppearanceSupportedTypeOAColor;
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
            } else if (valueClass == [UIImage class]) {
                *outType = OAAppearanceSupportedTypeSystemImage;
#else // !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
            } else if (valueClass == [NSImage class]) {
                *outType = OAAppearanceSupportedTypeSystemImage;
#endif
            } else {
                *outType = OAAppearanceSupportedTypeObject;
            }
            *outClass = valueClass;
        } else if (strcmp(type, @encode(float)) == 0) {
            *outType = OAAppearanceSupportedTypeFloat;
        } else if (strcmp(type, @encode(double)) == 0) {
            *outType = OAAppearanceSupportedTypeDouble;
        } else if (strcmp(type, @encode(BOOL)) == 0) {
            *outType = OAAppearanceSupportedTypeBool;
        } else if (strcmp(type, @encode(OA_SYSTEM_EDGE_INSETS_STRUCT)) == 0) {
            *outType = OAAppearanceSupportedTypeSystemEdgeInsets;
        } else if (strcmp(type, @encode(CGSize)) == 0) {
            *outType = OAAppearanceSupportedTypeSize;
        } else if (strcmp(type, @encode(long)) == 0) {
            *outType = OAAppearanceSupportedTypeLong;
        } else {
            @throw [NSException exceptionWithName:NSInvalidArgumentException reason:[NSString stringWithFormat:@"Unsupported type encoding '%@' for plist key '%@'", [NSString stringWithUTF8String:type], nameString] userInfo:nil];
        }
        
        return nameString;
    }
    @finally {
        free(type);
    }
}

+ (void)_synthesizeGetter:(SEL)invocationSel forProperty:(objc_property_t)backingProp;
{
    if (![OAAppearance isReifyingClass:self]) {
        @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:[NSString stringWithFormat:@"Synthesizing getter %@: should only synthesize getters for private reifying class instances, not for %@", NSStringFromSelector(invocationSel), NSStringFromClass(self)] userInfo:nil];
    }
    
    OAAppearanceSupportedType backingPropType;
    Class optionalBackingPropTypeClass;
    NSString *backingPropName = nameForBackingProp(backingProp, &backingPropType, &optionalBackingPropTypeClass);
    
    char *backingPropReadonly = property_copyAttributeValue(backingProp, "R");
    if (!backingPropReadonly)
        @throw [NSException exceptionWithName:NSInvalidArgumentException reason:[NSString stringWithFormat:@"Property declaration for '%@' must be readonly.", backingPropName] userInfo:nil];
    free(backingPropReadonly);
    
    
    IMP getterImp;
    char *getterTypes;
    
    MakeImpForProperty(self, backingPropName, backingPropType, optionalBackingPropTypeClass, invocationSel, &getterImp, &getterTypes);
    
    class_addMethod(self, invocationSel, getterImp, getterTypes);
    
    free(getterTypes);
}

static Class classFromTypeEncoding(const char *type)
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

/// Constructs and returns, via `outImp` and `outImpTypes`, the implementation and type signature for an accessor for `backingPropName` in `implementationCls`.
///
/// If `type` is an object type, then `optionalTypeClass` should be the Class of the object type. Otherwise it should be Nil.
///
/// *outImpTypes must be free()d.*
static void MakeImpForProperty(Class implementationCls, NSString *backingPropName, OAAppearanceSupportedType type, Class optionalTypeClass, SEL invocationSel, IMP *outImp, char **outImpTypes)
{
    
    // This function provides a variety of very similar dynamic getter implementations for the different return types that OAAppearance supports (color, edge inset, size, float, bool, etc.). Each implementation has built-in caching for the fetched object, so that the caller can avoid doing its own (potentially incorrect) caching work.
    // For performance reasons, we avoid NSCache and NSMutableDictionary. The former has unreasonably high time overhead, and the latter was still suffering degraded speeds (compared to a call-site dispatch_once() cache).
    // Instead, this function uses __block variables to provide storage for cached values, which are then captured by the block provided to imp_implementationWithBlock(). That function, in turn, is documented to Block_copy() the provided block, extending the lifetime of those __block variables past the end of a call to this function.
    // For a more thorough discussion of __block variables, see "The __block Storage Type" at https://developer.apple.com/library/ios/documentation/Cocoa/Conceptual/Blocks/Articles/bxVariables.html#//apple_ref/doc/uid/TP40007502-CH6-SW6. (Note that Apple's discussion of "lexical scope" can be confusing – the __block variables here are preserved past the end of a single call to this function by the implementation block, but subsequent calls to this function will allocate new storage for the new implementation block being created.)
    
#if 0 && defined(DEBUG)
#define DEBUG_DYNAMIC_GETTER(...) NSLog(@"%@", [[NSString stringWithFormat:@"DYNAMIC OAAPPEARANCE GETTER: -%@ ", [self class]] stringByAppendingFormat:__VA_ARGS__]);
#else
#define DEBUG_DYNAMIC_GETTER(...)
#endif
    char *returnType;
    
    switch (type) {
        case OAAppearanceSupportedTypeSystemColor: {
            returnType = "@";
            __block OA_SYSTEM_COLOR_CLASS *cachedColor = nil;
            __block NSUInteger localInvalidationCount = 0;
            
            *outImp = imp_implementationWithBlock(^(id self) {
                NSUInteger globalInvalidationCount = ((OAAppearance *)self)->_cacheInvalidationCount;
                if (localInvalidationCount < globalInvalidationCount) {
                    OA_SYSTEM_COLOR_CLASS *color = [self colorForKeyPath:backingPropName];
                    DEBUG_DYNAMIC_GETTER(@"colorForKeyPath:%@ --> %@", backingPropName, color);
                    cachedColor = color;
                    localInvalidationCount = globalInvalidationCount;
                }
                
                return cachedColor;
            });
            break;
        }
        case OAAppearanceSupportedTypeOAColor: {
            returnType = "@";
            __block OAColor *cachedColor = nil;
            __block NSUInteger localInvalidationCount = 0;
            
            *outImp = imp_implementationWithBlock(^(id self) {
                NSUInteger globalInvalidationCount = ((OAAppearance *)self)->_cacheInvalidationCount;
                if (localInvalidationCount < globalInvalidationCount) {
                    OAColor *color = [self OAColorForKeyPath:backingPropName];
                    DEBUG_DYNAMIC_GETTER(@"OAColorForKeyPath:%@ --> %@", backingPropName, color);
                    cachedColor = color;
                    localInvalidationCount = globalInvalidationCount;
                }
                
                return cachedColor;
            });
            break;
        }
        case OAAppearanceSupportedTypeSystemImage: {
            returnType = "@";
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
            __block UIImage *cachedImage = nil;
            __block NSUInteger localInvalidationCount = 0;
            
            *outImp = imp_implementationWithBlock(^(id self) {
                NSUInteger globalInvalidationCount = ((OAAppearance *)self)->_cacheInvalidationCount;
                if (localInvalidationCount < globalInvalidationCount) {
                    UIImage *image = [self imageForKeyPath:backingPropName];
                    DEBUG_DYNAMIC_GETTER(@"imageForKeyPath:%@ --> %@", backingPropName, image);
                    cachedImage = image;
                    localInvalidationCount = globalInvalidationCount;
                }
                
                return cachedImage;
            });
#else // !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
            __block NSImage *cachedImage = nil;
            __block NSUInteger localInvalidationCount = 0;
            
            *outImp = imp_implementationWithBlock(^(id self) {
                NSUInteger globalInvalidationCount = ((OAAppearance *)self)->_cacheInvalidationCount;
                if (localInvalidationCount < globalInvalidationCount) {
                    NSImage *image = [self imageForKeyPath:backingPropName];
                    DEBUG_DYNAMIC_GETTER(@"imageForKeyPath:%@ --> %@", backingPropName, image);
                    cachedImage = image;
                    localInvalidationCount = globalInvalidationCount;
                }
                
                return cachedImage;
            });
#endif
            break;
        }
        case OAAppearanceSupportedTypeObject: {
            OBASSERT_NOTNULL(optionalTypeClass);
            returnType = "@";
            __block id cachedObject = nil;
            __block NSUInteger localInvalidationCount = 0;
            
            *outImp = imp_implementationWithBlock(^(id self) {
                NSUInteger globalInvalidationCount = ((OAAppearance *)self)->_cacheInvalidationCount;
                if (localInvalidationCount < globalInvalidationCount) {
                    id object = [self _objectOfClass:optionalTypeClass forPlistKeyPath:backingPropName];
                    DEBUG_DYNAMIC_GETTER(@"_objectOfClass:%@ forPlistKeyPath:%@ --> %@", NSStringFromClass(valueClass), backingPropName, object);
                    cachedObject = object;
                    localInvalidationCount = globalInvalidationCount;
                }
                
                return cachedObject;
            });
            break;
        }
        case OAAppearanceSupportedTypeFloat: {
            returnType = @encode(float);
            
            __block float cachedResult = 0;
            __block NSUInteger localInvalidationCount = 0;
            
            *outImp = imp_implementationWithBlock(^(id self) {
                NSUInteger globalInvalidationCount = ((OAAppearance *)self)->_cacheInvalidationCount;
                if (localInvalidationCount < globalInvalidationCount) {
                    float val = [self floatForKeyPath:backingPropName];
                    DEBUG_DYNAMIC_GETTER(@"floatForKeyPath:%@ --> %f", backingPropName, val);
                    cachedResult = val;
                    localInvalidationCount = globalInvalidationCount;
                }
                
                return cachedResult;
            });
            break;
        }
        case OAAppearanceSupportedTypeDouble: {
            returnType = @encode(double);
            
            __block double cachedResult = 0;
            __block NSUInteger localInvalidationCount = 0;
            
            *outImp = imp_implementationWithBlock(^(id self) {
                NSUInteger globalInvalidationCount = ((OAAppearance *)self)->_cacheInvalidationCount;
                if (localInvalidationCount < globalInvalidationCount) {
                    double val = [self doubleForKeyPath:backingPropName];
                    DEBUG_DYNAMIC_GETTER(@"doubleForKeyPath:%@ --> %f", backingPropName, val);
                    cachedResult = val;
                    localInvalidationCount = globalInvalidationCount;
                }
                
                return cachedResult;
            });
            break;
        }
        case OAAppearanceSupportedTypeBool: {
            returnType = "c";
            
            __block BOOL cachedBool = NO;
            __block NSUInteger localInvalidationCount = 0;
            
            *outImp = imp_implementationWithBlock(^(id self) {
                NSUInteger globalInvalidationCount = ((OAAppearance *)self)->_cacheInvalidationCount;
                if (localInvalidationCount < globalInvalidationCount) {
                    BOOL val = [self boolForKeyPath:backingPropName];
                    DEBUG_DYNAMIC_GETTER(@"boolForKeyPath:%@ --> %@", backingPropName, val ? @"YES" : @"NO");
                    cachedBool = val;
                    localInvalidationCount = globalInvalidationCount;
                }
                
                return cachedBool;
            });
            break;
        }
        case OAAppearanceSupportedTypeSystemEdgeInsets: {
            returnType = @encode(OA_SYSTEM_EDGE_INSETS_STRUCT);
            
            __block OA_SYSTEM_EDGE_INSETS_STRUCT cachedInsets = {0};
            __block NSUInteger localInvalidationCount = 0;
            
            *outImp = imp_implementationWithBlock(^(id self) {
                NSUInteger globalInvalidationCount = ((OAAppearance *)self)->_cacheInvalidationCount;
                if (localInvalidationCount < globalInvalidationCount) {
                    OA_SYSTEM_EDGE_INSETS_STRUCT insets = [self edgeInsetsForKeyPath:backingPropName];
                    DEBUG_DYNAMIC_GETTER(@"edgeInsetsForKeyPath:%@ --> %@", backingPropName, [NSValue valueWithBytes:&insets objCType:returnType]);
                    cachedInsets = insets;
                    localInvalidationCount = globalInvalidationCount;
                }
                
                return cachedInsets;
            });
            break;
        }
        case OAAppearanceSupportedTypeSize: {
            returnType = @encode(CGSize);
            
            __block CGSize cachedSize = {0};
            __block NSUInteger localInvalidationCount = 0;
            
            *outImp = imp_implementationWithBlock(^(id self) {
                NSUInteger globalInvalidationCount = ((OAAppearance *)self)->_cacheInvalidationCount;
                if (localInvalidationCount < globalInvalidationCount) {
                    CGSize size = [self sizeForKeyPath:backingPropName];
                    DEBUG_DYNAMIC_GETTER(@"sizeForKeyPath:%@ --> %@", backingPropName, [NSValue valueWithBytes:&size objCType:returnType]);
                    cachedSize = size;
                    localInvalidationCount = globalInvalidationCount;
                }
                
                return cachedSize;
            });
            break;
        }
        case OAAppearanceSupportedTypeLong: {
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
                NSUInteger globalInvalidationCount = ((OAAppearance *)self)->_cacheInvalidationCount;
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
            break;
        }
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
    // Don't attempt to resolve dynamic methods unless the class is the private reifying class.
    BOOL isReifyingClassInstance = [OAAppearance isReifyingClass:self];
    if (!isReifyingClassInstance) {
        return [super resolveInstanceMethod:name];
    }
    
    objc_property_t backingProperty = [self _propertyForSelector:name matchGetter:YES];
    if (backingProperty) {
        [self _synthesizeGetter:name forProperty:backingProperty];
        return YES;
    } else {
        return [super resolveInstanceMethod:name];
    }
}

#pragma mark - Private API

static Class GetPrivateReifyingClassForPublicClass(Class cls)
{
    NSString *reifyingClassNameString = [OAAppearancePrivateClassNamePrefix stringByAppendingString:NSStringFromClass(cls)];
    Class extantReifyingClass = NSClassFromString(reifyingClassNameString);
    if (extantReifyingClass != Nil) {
        return extantReifyingClass;
    }
    
    const char *reifyingClassName = [reifyingClassNameString cStringUsingEncoding:[NSString defaultCStringEncoding]];
    Class result = objc_allocateClassPair(cls, reifyingClassName, 0);
    if (result == Nil) {
        @throw [NSException exceptionWithName:NSInvalidArgumentException reason:[NSString stringWithFormat:@"Unable to generate reifying class '%@'", reifyingClassNameString] userInfo:nil];
    }
    // -- if we needed to add any ivars to the new class, we'd do that here --
    objc_registerClassPair(result);
    return result;
}

/// Returns the appearance singleton for the given class.
/// Somewhat paradoxically, the private, dynamically generated reifying instances are what we vend to clients. This ensures that our dynamically generated caching getter methods are reified for subclasses regardless of order of access.
/// The actual class instance singletons are only used internally, so that plist look-up climbs the defined appearance class hierarchy.
/// @param cls the class to lookup or instantiate
/// @param reifyingInstance if true, then return a singleton instance of a private, dynamically generated subclass of `cls` to which dynamically reified methods will be added; otherwise, return a singleton instance of `cls`.
/// @returns the appearance singleton for the given class
/// @see <bug:///118253> (Bug: OAAppearance's inheritance model so that subclasses can predictably override base class appearance properties [OUIAppearance])
+ (OAAppearance *)_appearanceForClass:(Class)cls reifyingInstance:(BOOL)reifyingInstance
{
    OBPRECONDITION([cls isSubclassOfClass:[OAAppearance class]]);
    OBPRECONDITION(![OAAppearance isReifyingClass:cls], @"Should only call with public class. Called with class %@", NSStringFromClass(cls));
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        PublicClassToAppearanceMap = [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsObjectPointerPersonality valueOptions:NSPointerFunctionsObjectPersonality];
        PrivateReifyingClassToAppearanceMap = [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsObjectPointerPersonality valueOptions:NSPointerFunctionsObjectPersonality];
    });
    
    NSMapTable *mapTable = (reifyingInstance ? PrivateReifyingClassToAppearanceMap : PublicClassToAppearanceMap);
    OAAppearance *appearance = [mapTable objectForKey:cls];
    if (!appearance) {
        if (reifyingInstance) {
            Class reifyingClass = GetPrivateReifyingClassForPublicClass(cls);
            appearance = [[reifyingClass alloc] _initWithPlistName:nil inBundle:nil];
        } else {
            appearance = [[cls alloc] _initWithPlistName:NSStringFromClass(cls) inBundle:[cls bundleForPlist]];
        }
        OBASSERT_NOTNULL(appearance);
        
        if ([appearance class] != [OAAppearance class]) {
            // proper subclass, so get superclass singleton and register with it for cache invalidation
            OAAppearance *superAppearance = [self _appearanceForClass:[appearance superclass] reifyingInstance:NO];
            [superAppearance registerSubclassSingleton:appearance];
            
            if (reifyingInstance) {
                IMP performRelatedInvalidationOverride = imp_implementationWithBlock(^(id _self) {
                    // N.B., private reifying instances need to defer to the public instance so we can walk down the real subclass tree.
                    [superAppearance invalidateCachedValues];
                });
                Method overriddenMethod = class_getInstanceMethod([OAAppearance class], @selector(performRelatedInvalidation));
                OBASSERT_NOTNULL(overriddenMethod, @"couldn't find performRelatedInvalidation method on OAAppearance");
                if (overriddenMethod != NULL) {
                    const char *types = method_getTypeEncoding(overriddenMethod);
                    BOOL success = class_addMethod([appearance class], @selector(performRelatedInvalidation), performRelatedInvalidationOverride, types);
                    OB_UNUSED_VALUE(success);
                    OBASSERT(success, @"Unable to dynamically override performRelatedInvalidation for %@", NSStringFromClass([appearance class]));
                }
            }
        }
        
        [appearance beginPresentingUserPlistIfNecessary];
        
        [mapTable setObject:appearance forKey:cls];
    }
    
    if ([InvalidatedClassesForSwitchedPlistURLDirectories containsObject:cls]) {
        [InvalidatedClassesForSwitchedPlistURLDirectories removeObject:cls];
        OAAppearance *appearanceToInvalidate = appearance;
        if (reifyingInstance) {
            // Need to invalidate the public instance. That will recursively invalidate `appearance`.
            appearanceToInvalidate = [self _appearanceForClass:[appearance superclass] reifyingInstance:NO];
        }
        NSURL *directoryURLForSwitchablePlist = [[appearanceToInvalidate class] directoryURLForSwitchablePlist];
        appearanceToInvalidate.optionalPlistDirectoryURL = directoryURLForSwitchablePlist;
        [appearanceToInvalidate invalidateCachedValues];
    }
    
    return appearance;
}

- (void)registerSubclassSingleton:(OAAppearance *)singletonInstance
{
    OBPRECONDITION([NSThread isMainThread], @"the pointer array isn't thread-safe currently, either make it so or call this on the main thread");
    OBASSERT(singletonInstance != self, @"can't register self as a subclass instance"); // this would create an infinite regress in invalidateCachedValues
    
    if (self.subclassSingletons == nil) {
        self.subclassSingletons = [NSPointerArray weakObjectsPointerArray];
    }

#ifdef OMNI_ASSERTIONS_ON
    for (id instance in self.subclassSingletons.allObjects) {
        OBASSERT(singletonInstance != instance, @"shouldn't register a subclass more than once");
    }
#endif
    
    [self.subclassSingletons addPointer:(void *)singletonInstance];
}

- (void)performRelatedInvalidation;
{
    for (OAAppearance *subclassSingletonInstance in self.subclassSingletons.allObjects) {
        [subclassSingletonInstance invalidateCachedValues];
    }
}

@end

#pragma mark - Internal API

@implementation OAAppearance (Internal)

+ (BOOL)isReifyingClass:(Class)cls;
{
    if (![cls isSubclassOfClass:[OAAppearance class]]) {
        return NO;
    }
    
    BOOL result = [NSStringFromClass(cls) hasPrefix:OAAppearancePrivateClassNamePrefix];
    return result;
}

@end


#pragma mark - Subclass Conveniences

@implementation OAAppearance (Subclasses)

+ (instancetype)appearanceForClass:(Class)cls;
{
    OAAppearance *appearance = [self _appearanceForClass:cls reifyingInstance:YES];
    return appearance;
}

// If you always want to use a different bundle for this plist.
+ (NSBundle *)bundleForPlist
{
    return [NSBundle bundleForClass:self];
}

// If you want to hot-swap your directory at runtime.
+ (NSURL * _Nullable)directoryURLForSwitchablePlist;
{
    return nil;
}

+ (void)invalidateDirectoryURLForSwitchablePlist;
{
    Class cls = self;
    if ([OAAppearance isReifyingClass:cls]) {
        cls = [cls superclass];
    }
    [InvalidatedClassesForSwitchedPlistURLDirectories addObject:cls];
}

+ (instancetype _Nullable)appearanceForValidatingPropertyListInDirectory:(NSURL *)directoryURL forClass:(Class)cls;
{
    OAAppearance *appearance = [[cls alloc] _initForValidationWithDirectoryURL:directoryURL];
    NSURL *plistURL = [appearance _plistURL];
    NSURL *plistDirectory = [plistURL URLByDeletingLastPathComponent];
    if (OFURLEqualsURL(directoryURL, plistDirectory)) {
        return appearance;
    }
    return nil;
}

@end

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE

#pragma mark - Mac Convenience Accessors

static NSColor *SelectionBorderColor;
static id SystemColorsObserver;

static void EnsureSystemColorsObserver(OAAppearance *self)
{
    if (!SystemColorsObserver) {
        SystemColorsObserver = [[NSNotificationCenter defaultCenter] addObserverForName:NSSystemColorsDidChangeNotification object:nil queue:nil usingBlock:^(NSNotification *unused){
            [[NSNotificationCenter defaultCenter] postNotificationName:OAAppearanceValuesWillChangeNotification object:self];

            SelectionBorderColor = nil;
            
            [[NSNotificationCenter defaultCenter] postNotificationName:OAAppearanceValuesDidChangeNotification object:self];
        }];
    }
}

@implementation NSColor (OAAppearance)

+ (NSColor *)OASidebarBackgroundColor;
{
    static NSColor *color;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        color = [[OAAppearance appearance] colorForKeyPath:@"OASidebarBackgroundColor"];
    });
    
    return color;
}

+ (NSColor *)OASidebarFontColor;
{
    static NSColor *color;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        color = [[OAAppearance appearance] colorForKeyPath:@"OASidebarFontColor"];
    });
    
    return color;
}

+ (NSColor *)OASelectionBorderColor;
{
    EnsureSystemColorsObserver(nil);
    
    if (!SelectionBorderColor) {
        SelectionBorderColor = [[NSColor alternateSelectedControlColor] colorWithAlphaComponent:([[OAAppearance appearance] CGFloatForKeyPath:@"OASelectionBorderColorAlphaPercentage"] / 100.0)];
    }
    
    return SelectionBorderColor;
}

+ (NSColor *)OAInactiveSelectionBorderColor;
{
    static NSColor *color;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        color = [[OAAppearance appearance] colorForKeyPath:@"OAInactiveSelectionBorderColor"];
    });
    
    return color;
}

- (BOOL)isLightColor;
{
    OAColor *aColor = [OAColor colorWithPlatformColor:self];
    CGFloat luma = OAGetRGBAColorLuma([aColor toRGBA]);

    return [[OAAppearance appearance] isLightLuma:luma];
}

@end


#else // defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE

#pragma mark - iOS Convenience Accessors

@implementation OAAppearance (OAAppearance)
@dynamic emptyOverlayViewLabelMaxWidthRatio;
@dynamic overlayInspectorWindowHeightFraction;
@dynamic overlayInspectorTopSeparatorColor;
@dynamic overlayInspectorWindowMaxHeight;
@dynamic navigationBarTextFieldBackgroundImageInsets;
@dynamic navigationBarTextFieldLineHeightMultiplier;
@end

@implementation UIColor (OAAppearance)

#if OB_ARC
    #define DO_RETAIN(x) // assign to global does it
#else
    #define DO_RETAIN(x) OBStrongRetain(x);
#endif

#define CACHED_COLOR(key) do { \
    static UIColor *color; \
    static dispatch_once_t onceToken; \
    dispatch_once(&onceToken, ^{ \
        color = [[OAAppearance appearance] colorForKeyPath:key]; \
        DO_RETAIN(color); \
    }); \
    return color; \
} while(0);

- (BOOL)isLightColor;
{
    OAColor *aColor = [OAColor colorWithPlatformColor:self];
    CGFloat luma = OAGetRGBAColorLuma([aColor toRGBA]);

    return [[OAAppearance appearance] isLightLuma:luma];
}

@end

#endif

#pragma mark -

#if OA_PERFORM_FILE_PRESENTATION

@implementation OAAppearanceUserPlistFilePresenter

- (instancetype)initWithOwner:(OAAppearance *)owner;
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

#endif // OA_PERFORM_FILE_PRESENTATION
