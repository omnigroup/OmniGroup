// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>

NS_ASSUME_NONNULL_BEGIN

@interface OBObject : NSObject
@end


@class NSDictionary, NSMutableDictionary;

@interface NSObject (OBDebuggingExtensions)

@property(nonatomic,readonly) NSMutableDictionary *debugDictionary;
@property(nonatomic,readonly) NSString *shortDescription;

#ifdef DEBUG

// Runtime introspection
@property(nonatomic,readonly) NSString *ivars; // "po [value ivars]" to get a runtime dump of ivars
@property(nonatomic,readonly) NSString *methods; // "po [value methods]" to get a runtime dump of methods
+ (NSString *)instanceMethods;
+ (NSString *)classMethods;
+ (NSString *)protocols;
+ (NSArray *)subclasses;

// Leak/retain cycle warnings
- (void)expectDeallocationSoon;

#endif

@end

@interface OBObject (OBDebugging)
- (NSString *)descriptionWithLocale:(nullable NSDictionary *)locale indent:(NSUInteger)level;
- (NSString *)description;
@end

// CF callback for -shortDescription (here instead of in OFCFCallbacks since this is where -shortDescription gets defined).
extern CFStringRef OBNSObjectCopyShortDescription(const void *value);

NS_ASSUME_NONNULL_END

