// Copyright 2016-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>
#import <OmniAppKit/OAAppearance.h> // for OAAppearanceValueEncoding

@protocol OAAppearancePropertyListCodeable;

NS_ASSUME_NONNULL_BEGIN

extern NSString * const OAAppearanceUnknownKeyKey;
extern NSString * const OAAppearanceMissingKeyKey;

@interface OAAppearancePropertyListCoder : NSObject
- (instancetype)initWithCodeable:(NSObject <OAAppearancePropertyListCodeable> *)codeable;
- (NSDictionary <NSString *, NSObject *> *)propertyList;

/// Queries this coder's codeable object for every key path, returning YES if all queries are successful.
- (BOOL)validatePropertyListValuesWithError:(NSError **)error;

/// Validates the keys present in the given property list against this coder's codeable object.
///
/// - returns: nil if all keys are valid, otherwise a dictionary with the keys `OAAppearanceUnknownKeyKey` and `OAAppearanceMissingKeyKey` mapping to arrays of the unknown and missing keys respectively.
- (NSDictionary <NSString *, NSArray <NSString *> *> * _Nullable)invalidKeysInPropertyList:(NSDictionary <NSString *, NSObject *> *)propertyList;
@end

/// This protocol is a bit odd. The questions about key paths and hierarchy are answered on a class-basis and we need to walk the class hierarchy to find valid key paths. However OAAppearancePropertyListCoder needs an instance of a conforming class, because we'll do valueForKeyPath: lookups on the instance to populate the values in the resulting property list.
@protocol OAAppearancePropertyListCodeable <NSObject>
- (OAAppearanceValueEncoding)valueEncodingForKeyPath:(NSString *)keyPath;

/// Validates that the *value* at the given keyPath is encoded correctly.
- (BOOL)validateValueAtKeyPath:(NSString *)keyPath error:(NSError **)error;

@optional
- (NSObject *)customEncodingForKeyPath:(NSString *)keyPath;
+ (NSSet <NSString *> *)additionalLocalKeyPaths;
+ (NSSet <NSString *> *)localDynamicPropertyNamesToOmit;
+ (BOOL)includeSuperclassKeyPaths;
@end

NS_ASSUME_NONNULL_END
