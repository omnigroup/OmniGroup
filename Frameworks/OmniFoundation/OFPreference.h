// Copyright 2001-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>

#import <Foundation/NSDate.h>

NS_ASSUME_NONNULL_BEGIN

@class OFEnumNameTable;
@class NSArray, NSDictionary, NSData, NSSet, NSString;

// OFPreference is KVO compliant for the objectValue key.
// Like +addObserver:selector:forPreference:, the notification will be delivered on the thread where the preference was changed.
extern NSString * const OFPreferenceObjectValueBinding;

typedef NS_OPTIONS(NSUInteger, OFPreferenceRegistrationOptions) {
    OFPreferenceRegistrationOptionNone                      = 0,
    OFPreferenceRegistrationPreserveExistingRegistrations   = 1 << 0,
};

// OFPreference instances should be readable in a thread-safe way from any queue, but writing to them should happen on the main queue.
// See <bug:///122290> (Bug: OFPreference deadlock) and _setValueUnderlyingValue from implementation.
@interface OFPreference : OBObject

// API

+ (nullable id)coerceStringValue:(nullable NSString *)stringValue toTypeOfPropertyListValue:(id)propertyListValue error:(NSError **)outError;

@property(nonatomic,readonly) NSString *key;
@property(nonatomic,readonly,nullable) OFEnumNameTable *enumeration;

@property(nonatomic,readonly) id controller;
@property(nonatomic,readonly) NSString *controllerKey;

- (void)setController:(id)controller key:(NSString *)controllerKey;

@property(nonatomic,readonly) id defaultObjectValue;
@property(nonatomic,readonly) BOOL hasNonDefaultValue;

- (void) restoreDefaultValue;

@property(nonatomic,readonly) BOOL hasPersistentValue;

@property(nonatomic,strong,nullable) id objectValue;
@property(nonatomic,copy,nullable) NSString *stringValue;
@property(nonatomic,copy,nullable) NSArray *arrayValue;
@property(nonatomic,copy,nullable) NSDictionary *dictionaryValue;
@property(nonatomic,copy,nullable) NSData *dataValue;
@property(nonatomic,copy,nullable) NSURL *bookmarkURLValue;
@property(nonatomic,copy,readonly,nullable) NSArray <NSString *> *stringArrayValue;

@property(nonatomic,assign) int intValue;
@property(nonatomic,assign) NSInteger integerValue;
@property(nonatomic,assign) unsigned int unsignedIntValue;
@property(nonatomic,assign) NSUInteger unsignedIntegerValue;
@property(nonatomic,assign) float floatValue;
@property(nonatomic,assign) double doubleValue;
@property(nonatomic,assign) BOOL boolValue;
@property(nonatomic,assign) NSInteger enumeratedValue;

@end

// Wrappers that call through to the shared OFPreferenceWrapper
@interface OFPreference ()
+ (BOOL)hasPreferenceForKey:(NSString *)key;
+ (OFPreference *)preferenceForKey:(NSString *)key;
+ (OFPreference *)preferenceForKey:(NSString *)key enumeration:(OFEnumNameTable * _Nullable)enumeration;
+ (OFPreference *)preferenceForKey:(NSString *)key defaultValue:(id)value;

@property(class, nonatomic, readonly) NSSet <NSString *> *registeredKeys;
+ (void)recacheRegisteredKeys;

+ (void)registerDefaultValue:(id)value forKey:(NSString *)key options:(OFPreferenceRegistrationOptions)options;
+ (void)registerDefaults:(NSDictionary<NSString *, id> *)registrationDictionary options:(OFPreferenceRegistrationOptions)options;

+ (void)addObserver:(id)anObserver selector:(SEL)aSelector forPreference:(OFPreference * _Nullable)aPreference;
+ (id)addObserverForPreference:(nullable OFPreference *)preference usingBlock:(void (^)(OFPreference *preference))block;
+ (void)removeObserver:(id)anObserver forPreference:(OFPreference * _Nullable)aPreference;

/// Adds an entry to the OFPreference's OFPreferenceWrapper private notification center dispatch table. This is appropriate for use when the OFPreference was registered to a suiteName other than the standard registration domain. In all other cases, `+[OFPreference addObserver:selector:forPreference:]` is approprate.
/// @param anObserver Object registering as an observer.
/// @param aSelector Selector that specifies the message the receiver sends observer to notify it of the notification posting.
- (void)addObserver:(id)anObserver selector:(SEL)aSelector;

/// Removes all entries specifying a given observer from the OFPreference's OFPreferenceWrapper private notification center dispatch table. This is appropriate for use when the OFPreference was registered to a suiteName other than the standard registration domain. In all other cases, `+[OFPreference removeObserver:forPreference:]` is approprate.
/// @param anObserver Object registering as an observer.
- (void)removeObserver:(id)anObserver;

@end

// This provides an API that is much like NSUserDefaults but goes through the thread-safe OFPreference layer
@interface OFPreferenceWrapper : NSObject

/// Returns a shared instance of OFPreferenceWrapper that operates on the process's standard user defaults domain.
+ (OFPreferenceWrapper *)sharedPreferenceWrapper;

/// Returns a shared instance of OFPreferenceWrapper that operates on the given suite.
+ (OFPreferenceWrapper *)preferenceWrapperWithSuiteName:(NSString *)suiteName;

/// For preference domains that should be stored in a group container. This should be the base identifer ("com.mycompany.appname") and the appropriate prefix will be added to the suite name for the current platform.
+ (OFPreferenceWrapper *)preferenceWrapperWithGroupIdentifier:(NSString *)suiteName;

- init NS_UNAVAILABLE;

@property(nullable,nonatomic,readonly) NSString *suiteName;

- (BOOL)hasPreferenceForKey:(NSString *)key;
- (OFPreference *)preferenceForKey:(NSString *)key;
- (OFPreference *)preferenceForKey:(NSString *)key enumeration:(OFEnumNameTable * _Nullable)enumeration;
- (OFPreference *)preferenceForKey:(NSString *)key defaultValue:(id)value;

@property(nonatomic, readonly) NSSet <NSString *> *registeredKeys;
- (void)recacheRegisteredKeys;

- (void)registerDefaultValue:(id)value forKey:(NSString *)key options:(OFPreferenceRegistrationOptions)options;
- (void)registerDefaults:(NSDictionary<NSString *, id> *)registrationDictionary options:(OFPreferenceRegistrationOptions)options;

- (void)addObserver:(id)anObserver selector:(SEL)aSelector forPreference:(OFPreference * _Nullable)aPreference;
/** Registers the block to be invoked when the given preference changes.

 The returned object is an opaque reference that can be passed to removeObserver:forPreference: to stop observing. The block passed in is copied.
*/
- (id)addObserverForPreference:(nullable OFPreference *)preference usingBlock:(void (^)(OFPreference *preference))block;
- (void)removeObserver:(id)anObserver forPreference:(OFPreference * _Nullable)aPreference;

- (_Nullable id)objectForKey:(NSString *)defaultName;
- (void)setObject:(_Nullable id)value forKey:(NSString *)defaultName;
- (void)removeObjectForKey:(NSString *)defaultName;
- (NSString * _Nullable)stringForKey:(NSString *)defaultName;
- (NSArray * _Nullable)arrayForKey:(NSString *)defaultName;
- (NSDictionary * _Nullable)dictionaryForKey:(NSString *)defaultName;
- (NSData * _Nullable)dataForKey:(NSString *)defaultName;
- (NSURL * _Nullable)bookmarkURLForKey:(NSString *)defaultName;
- (NSArray * _Nullable)stringArrayForKey:(NSString *)defaultName;
- (int)intForKey:(NSString *)defaultName;
- (NSInteger)integerForKey:(NSString *)defaultName;
- (float)floatForKey:(NSString *)defaultName; 
- (double)doubleForKey:(NSString *)defaultName; 
- (BOOL)boolForKey:(NSString *)defaultName;  
- (void)setInt:(int)value forKey:(NSString *)defaultName;
- (void)setInteger:(NSInteger)value forKey:(NSString *)defaultName;
- (void)setFloat:(float)value forKey:(NSString *)defaultName;
- (void)setDouble:(double)value forKey:(NSString *)defaultName;
- (void)setBool:(BOOL)value forKey:(NSString *)defaultName;

- (BOOL)synchronize;

@end

/*
 Internal configuration value support.
 
 These configuration values are defined in code and not intended to be changed by users typically, so we don't register them in plists like we do for user defaults. See also the OmniAppKit function OAHandleChangeConfigurationValueURL() for running a confirmation alert.
 */

@class OFConfigurationValue;
typedef void (^OFConfigurationValueObserver)(OFConfigurationValue *configurationValue);

@interface OFConfigurationValue : NSObject

- initWithKey:(NSString *)key integral:(BOOL)integral defaultValue:(double)defaultValue minimumValue:(double)minimumValue maximumValue:(double)maximumValue;

+ (NSArray *)configurationValues;
+ (void)restoreAllConfigurationValuesToDefaults;

+ (void)setConfigurationValuesURLScheme:(NSString *)scheme;
+ (NSURL *)URLForConfigurationValues:(NSArray *)configurationValues;

@property(nonatomic,readonly) NSString *key;

- (void)addValueObserver:(OFConfigurationValueObserver)observer;

@property(nonatomic,readonly) double currentValue; // KVO observable, but probably only OAChangeConfigurationValuesWindowController should observe (really this whole class is not for general use).
@property(nonatomic,readonly) double defaultValue;
@property(nonatomic,readonly) double minimumValue;
@property(nonatomic,readonly) double maximumValue;

@property(nonatomic,readonly) BOOL hasNonDefaultValue;
- (void)restoreDefaultValue;
- (void)setValueFromString:(NSString *)stringValue;
- (void)setValueFromDouble:(double)value;

@end

extern void _OFRegisterIntegerConfigurationValue(NSInteger *outLevel, NSString *name, double defaultValue, double minimumValue, double maximumValue);
extern void _OFRegisterTimeIntervalConfigurationValue(NSTimeInterval *outLevel, NSString *name, double defaultValue, double minimumValue, double maximumValue);
#define _OFDeclareConfigurationValue_(kind, name, counter, defaultValue, minimumValue, maximumValue) \
NS ## kind name = defaultValue;  \
static void _InitializeConfigurationValue ## counter(void) __attribute__((constructor)); \
static void _InitializeConfigurationValue ## counter(void) { \
  _OFRegister ## kind ## ConfigurationValue(&name, @#name, defaultValue, minimumValue, maximumValue); \
}
#define _OFDeclareConfigurationValue(kind, name, counter, defaultValue, minimumValue, maximumValue) _OFDeclareConfigurationValue_(kind, name, counter, defaultValue, minimumValue, maximumValue)

// If you want your log level/time interval variable to be static, you can insert 'static' before using these macros.
// Declare the debug log level for <name> in your project scheme to enable logging.
#define OFDeclareDebugLogLevel(name) _OFDeclareConfigurationValue(Integer, name, __COUNTER__, 0, 0, 10)
#define OFDeclareTimeInterval(name, default_value, min_value, max_value) _OFDeclareConfigurationValue(TimeInterval, name, __COUNTER__, (default_value), (min_value), (max_value))

#define OFDeclareIntegerConfigurationValue(name, value, min, max) _OFDeclareConfigurationValue(Integer, name, __COUNTER__, (value), (min), (max))

// Handle URLs of the form "scheme:///change-configuration-value?name=level. We ignore the scheme each app will have their own scheme.
typedef void (^OFConfigurationValueChangeConfirmationCallback)(BOOL confirmed, NSError * _Nullable confirmError);
typedef void (^OFConfigurationValueChangeConfirmation)(NSString *title, NSString *message, OFConfigurationValueChangeConfirmationCallback callback);
extern NSString * const OFChangeConfigurationValueURLPath;
extern BOOL OFHandleChangeConfigurationValueURL(NSURL *url, NSError **outError, OFConfigurationValueChangeConfirmation confirm);

NS_ASSUME_NONNULL_END

