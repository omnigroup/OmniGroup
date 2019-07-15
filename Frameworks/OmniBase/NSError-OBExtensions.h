// Copyright 2005-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSError.h>

// This header was split out; import for backwards compatibility
#import <OmniBase/NSError-OBUtilities.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSError (OBExtensions)

- (nullable NSError *)underlyingErrorWithDomain:(NSString *)domain;
- (nullable NSError *)underlyingErrorWithDomain:(NSString *)domain code:(NSInteger)code;
- (BOOL)hasUnderlyingErrorDomain:(NSString *)domain code:(NSInteger)code;

@property(nonatomic,readonly) BOOL causedByUserCancelling;
@property(nonatomic,readonly) BOOL causedByMissingFile;
@property(nonatomic,readonly) BOOL causedByExistingFile;
@property(nonatomic,readonly) BOOL causedByUnreachableHost;
@property(nonatomic,readonly) BOOL causedByAppTransportSecurity;

#if !defined(TARGET_OS_WATCH) || !TARGET_OS_WATCH
@property(nonatomic,readonly) BOOL causedByNetworkConnectionLost;
#endif

- (id)initWithPropertyList:(NSDictionary *)propertyList;
- (NSDictionary<NSString *, id> *)toPropertyList;

// Useful for test cases that intentionally provoke errors that might be logged to the console as well as being reported to the user via other means (if UI was hooked up). Only suppresses the error for the duration of the given action, and only on the calling thread.
+ (void)suppressingLogsWithUnderlyingDomain:(NSString *)domain code:(NSInteger)code action:(void (^ NS_NOESCAPE)(void))action;

// If the error isn't being suppressed, the format and arguments are turned into a string and logged, along with the property list version of the error.
- (void)log:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2);
- (void)log:(NSString *)format arguments:(va_list)arguments;
- (void)logWithReason:(NSString *)reason;

@end

NS_ASSUME_NONNULL_END
