// Copyright 2013-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>

NS_ASSUME_NONNULL_BEGIN

@class OFXServerAccount;
@protocol OFXServerAccountValidator;

@interface OFXServerAccountType : NSObject

+ (void)registerAccountType:(OFXServerAccountType *)type;
+ (NSArray *)accountTypes;
+ (nullable OFXServerAccountType *)accountTypeWithIdentifier:(NSString *)identifier;

- (NSString *)importTitleForDisplayName:(NSString *)displayName;
- (NSString *)exportTitleForDisplayName:(NSString *)displayName;

- (nullable NSURL *)baseURLForServerURL:(nullable NSURL *)serverURL username:(NSString *)username;

@end

typedef void (^OFXServerAccountValidationHandler)(NSError *errorOrNil);

@protocol OFXConcreteServerAccountType <NSObject>

@property(nonatomic,readonly) NSString *identifier;
@property(nonatomic,readonly) NSString *displayName;
@property(nonatomic,readonly) float presentationPriority;
@property(nonatomic,readonly) BOOL requiresServerURL;
- (NSString *)accountDetailsStringForAccount:(OFXServerAccount *)account;
@property(nonatomic,readonly) NSString *addAccountTitle;
@property(nonatomic,readonly) NSString *addAccountDescription;
@property(nonatomic,readonly) NSString *setUpAccountTitle;

- (id <OFXServerAccountValidator>)validatorWithAccount:(OFXServerAccount *)account username:(NSString *)username password:(NSString *)password;

@end

// Not implemented; subclasses must conform
@interface OFXServerAccountType (OFXConcreteServerAccountType) <OFXConcreteServerAccountType>
@end

// Identifiers for well known types
extern NSString * const OFXOmniSyncServerAccountTypeIdentifier;
extern NSString * const OFXWebDAVServerAccountTypeIdentifier;

NS_ASSUME_NONNULL_END
