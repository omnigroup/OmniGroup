// Copyright 2001-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>

@class OFEnumNameTable;
@class NSArray, NSDictionary, NSData, NSSet, NSString;

// OFPreference is KVO compliant for the objectValue key.
// Like +addObserver:selector:forPreference:, the notification will be delivered on the thread where the preference was changed.
extern NSString * const OFPreferenceObjectValueBinding;

@interface OFPreference : NSObject

// API

+ (OFPreference *) preferenceForKey: (NSString *) key;
+ (OFPreference *) preferenceForKey: (NSString *) key enumeration: (OFEnumNameTable *)enumeration;

+ (NSSet *)registeredKeys;
+ (void)recacheRegisteredKeys;

+ (void)addObserver:(id)anObserver selector:(SEL)aSelector forPreference:(OFPreference *)aPreference;
+ (void)removeObserver:(id)anObserver forPreference:(OFPreference *)aPreference;

+ (id)coerceStringValue:(NSString *)stringValue toTypeOfPropertyListValue:(id)propertyListValue;

- (NSString *) key;
- (OFEnumNameTable *) enumeration;

- (id)controller;
- (NSString *)controllerKey;
- (void)setController:(id)controller key:(NSString *)controllerKey;

- (id) defaultObjectValue;
- (BOOL) hasNonDefaultValue;
- (void) restoreDefaultValue;

- (BOOL) hasPersistentValue;

- (id)objectValue;
- (NSString *)stringValue;
- (NSArray *)arrayValue;
- (NSDictionary *)dictionaryValue;
- (NSData *)dataValue;
- (int)intValue;
- (NSInteger)integerValue;
- (unsigned int)unsignedIntValue;
- (NSUInteger)unsignedIntegerValue;
- (float)floatValue;
- (double)doubleValue;
- (BOOL)boolValue;
- (NSArray *)stringArrayValue;
- (NSInteger)enumeratedValue;

- (void)setObjectValue:(id)value;
- (void)setStringValue:(NSString *)value;
- (void)setArrayValue:(NSArray *)value;
- (void)setDictionaryValue:(NSDictionary *)value;
- (void)setDataValue:(NSData *)value;
- (void)setIntValue:(int)value;
- (void)setIntegerValue:(NSInteger)value;
- (void)setUnsignedIntValue:(unsigned int)value;
- (void)setUnsignedIntegerValue:(NSUInteger)value;
- (void)setFloatValue:(float)value;
- (void)setDoubleValue:(double)value;
- (void)setBoolValue:(BOOL)value;
- (void)setEnumeratedValue:(NSInteger)value;

@end

// This provides an API that is much like NSUserDefaults but goes through the thread-safe OFPreference layer
@interface OFPreferenceWrapper : NSObject
+ (OFPreferenceWrapper *)sharedPreferenceWrapper;

- (OFPreference *) preferenceForKey: (NSString *) key;

- (id)objectForKey:(NSString *)defaultName;
- (void)setObject:(id)value forKey:(NSString *)defaultName;
- (void)removeObjectForKey:(NSString *)defaultName;
- (NSString *)stringForKey:(NSString *)defaultName;
- (NSArray *)arrayForKey:(NSString *)defaultName;
- (NSDictionary *)dictionaryForKey:(NSString *)defaultName;
- (NSData *)dataForKey:(NSString *)defaultName;
- (NSArray *)stringArrayForKey:(NSString *)defaultName;
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

#import <Foundation/NSDate.h>

@interface OFConfigurationValue : NSObject

+ (NSArray *)configurationValues;
+ (void)restoreAllConfigurationValuesToDefaults;

+ (void)setConfigurationValuesURLScheme:(NSString *)scheme;
+ (NSURL *)URLForConfigurationValues:(NSArray *)configurationValues;

@property(nonatomic,readonly) NSString *key;
@property(nonatomic,readonly) const char *objcType;

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
#define OFDeclareDebugLogLevel(name) _OFDeclareConfigurationValue(Integer, name, __COUNTER__, 0, 0, 10)
#define OFDeclareTimeInterval(name, default_value, min_value, max_value) _OFDeclareConfigurationValue(TimeInterval, name, __COUNTER__, (default_value), (min_value), (max_value))

// Handle URLs of the form "scheme:///change-configuration-value?name=level. We ignore the scheme each app will have their own scheme.
typedef void (^OFConfigurationValueChangeConfirmationCallback)(BOOL confirmed, NSError *confirmError);
typedef void (^OFConfigurationValueChangeConfirmation)(NSString *title, NSString *message, OFConfigurationValueChangeConfirmationCallback callback);
extern NSString * const OFChangeConfigurationValueURLPath;
extern BOOL OFHandleChangeConfigurationValueURL(NSURL *url, NSError **outError, OFConfigurationValueChangeConfirmation confirm);
