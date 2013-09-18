// Copyright 2005-2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniBase/NSError-OBExtensions.h>

#import <OmniBase/rcsid.h>
#import <OmniBase/assertions.h>
#import <OmniBase/OBUtilities.h>
#import <OmniBase/OBObject.h>

#import <Foundation/NSUserDefaults.h>
#import <Foundation/FoundationErrors.h>

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
#import <Security/Authorization.h> // for errAuthorizationCanceled
#endif

RCS_ID("$Id$");

// This might be useful for non-debug builds too.  These are only included in our errors, not Cocoa's, but if we use OBChainError when our code fails due to a Mac OS X framework call failing, we'll get information there.
#if 0 && defined(DEBUG)
    #define INCLUDE_BACKTRACE_IN_ERRORS 1
#else
    #define INCLUDE_BACKTRACE_IN_ERRORS 0
#endif

#if INCLUDE_BACKTRACE_IN_ERRORS
    #include <execinfo.h>  // For backtrace()
    static NSString * const OBBacktraceAddressesErrorKey = @"com.omnigroup.framework.OmniBase.ErrorDomain.BacktraceAddresses";
    static NSString * const OBBacktraceNamesErrorKey = @"com.omnigroup.framework.OmniBase.ErrorDomain.Backtrace";
#endif

static BOOL OBLogErrorCreations = NO;
static id (*original_initWithDomainCodeUserInfo)(NSError *self, SEL _cmd, NSString *domain, NSInteger code, NSDictionary *dict) = NULL;

@implementation NSError (OBExtensions)

static id _replacement_initWithDomain_code_userInfo(NSError *self, SEL _cmd, NSString *domain, NSInteger code, NSDictionary *dict)
{
#if INCLUDE_BACKTRACE_IN_ERRORS
    {
        const int maxFrames = 200;
        void *frames[maxFrames];
        int frameCount = backtrace(frames, maxFrames);
        if (frameCount > 0) {
            NSData *frameData = [[NSData alloc] initWithBytes:frames length:sizeof(frames[0]) * frameCount];
            if (dict) {
                NSMutableDictionary *updatedInfo = [[NSMutableDictionary alloc] initWithDictionary:dict];
                updatedInfo[OBBacktraceAddressesErrorKey] = frameData;
                dict = updatedInfo;
            } else {
                dict = @{OBBacktraceAddressesErrorKey:frameData};
            }
        }
    }
#endif
    if (!(self = original_initWithDomainCodeUserInfo(self, _cmd, domain, code, dict)))
        return nil;
    
    if (OBLogErrorCreations)
        NSLog(@"Error created: %@", [self toPropertyList]);
    
    return self;
}

+ (void)performPosing;
{
    OBLogErrorCreations = [[NSUserDefaults standardUserDefaults] boolForKey:@"OBLogErrorCreations"];
    
    if (OBLogErrorCreations || INCLUDE_BACKTRACE_IN_ERRORS) {
        original_initWithDomainCodeUserInfo = (typeof(original_initWithDomainCodeUserInfo))OBReplaceMethodImplementation(self, @selector(initWithDomain:code:userInfo:), (IMP)_replacement_initWithDomain_code_userInfo);
    }
}

- (NSError *)underlyingErrorWithDomain:(NSString *)domain;
{
    NSError *error = self;
    while (error) {
	if ([[error domain] isEqualToString:domain])
	    return error;
	error = [[error userInfo] objectForKey:NSUnderlyingErrorKey];
    }
    return nil;
}

- (NSError *)underlyingErrorWithDomain:(NSString *)domain code:(NSInteger)code;
{
    NSError *error = self;
    while (error) {
	if ([[error domain] isEqualToString:domain] && [error code] == code)
	    return error;
	error = [[error userInfo] objectForKey:NSUnderlyingErrorKey];
    }
    return nil;
}

// Returns YES if the error or any of its underlying errors has the indicated domain and code.
- (BOOL)hasUnderlyingErrorDomain:(NSString *)domain code:(NSInteger)code;
{
    return ([self underlyingErrorWithDomain:domain code:code] != nil);
}

- (BOOL)causedByUserCancelling;
{    
    if ([self hasUnderlyingErrorDomain:NSCocoaErrorDomain code:NSUserCancelledError])
        return YES;

    // N.B. Don't consider NSURLErrorDomain/NSURLErrorUserCancelledAuthentication a generic user cancelled case.
    // We added this in r164657, but it turns out that this can bubble out of the URL connection system both by programatic and user cancels.
    // These errors will have to be filtered closer to the source, as necessary
#if 0
    if ([self hasUnderlyingErrorDomain:NSURLErrorDomain code:NSURLErrorUserCancelledAuthentication])
        return YES;
#endif

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
    if ([self hasUnderlyingErrorDomain:NSOSStatusErrorDomain code:errAuthorizationCanceled])
        return YES;

    if ([self hasUnderlyingErrorDomain:NSOSStatusErrorDomain code:userCanceledErr])
        return YES;
#endif
    
    return NO;
}

- (BOOL)causedByMissingFile;
{
    return [self hasUnderlyingErrorDomain:NSPOSIXErrorDomain code:ENOENT] || [self hasUnderlyingErrorDomain:NSCocoaErrorDomain code:NSFileNoSuchFileError];
}


- (BOOL)causedByUnreachableHost;
{
    NSError *urlError = [self underlyingErrorWithDomain:NSURLErrorDomain];
    if (urlError == nil)
         return NO;

    switch ([urlError code]) {
        case NSURLErrorTimedOut:
        case NSURLErrorCannotFindHost:
        case NSURLErrorNetworkConnectionLost:
        case NSURLErrorDNSLookupFailed:
        case NSURLErrorNotConnectedToInternet:
        case NSURLErrorCannotConnectToHost:
            return YES;

        default:
            return NO;
    }
}

- initWithPropertyList:(NSDictionary *)propertyList;
{
    NSString *domain = [propertyList objectForKey:@"domain"];
    NSNumber *code = [propertyList objectForKey:@"code"];
    
    OBASSERT(domain);
    OBASSERT(code);
    
    NSDictionary *userInfo = [propertyList objectForKey:@"userInfo"];
    if (userInfo) {
        NSMutableDictionary *mappedUserInfo = [NSMutableDictionary dictionary];
        for (NSString *key in userInfo) {
            id valueObject = [userInfo objectForKey:key];
            
            // This is lossy, but once something is plist-ified, we can't be sure where it came from.
            if ([key isEqualToString:NSUnderlyingErrorKey])
                valueObject = [[NSError alloc] initWithPropertyList:valueObject];
            else if ([key isEqualToString:NSRecoveryAttempterErrorKey] && [valueObject isKindOfClass:[NSString class]])
                continue; // We can't turn an NSString back into a valid -recoveryAttempter object
            
            [mappedUserInfo setObject:valueObject forKey:key];
        }

        userInfo = mappedUserInfo;
    }
    
    return [self initWithDomain:domain code:[code intValue] userInfo:userInfo];
}

static id _mapUserInfoValueToPlistValue(id valueObject)
{
    if (!valueObject)
        return @"<nil>";
    
    // Handle some specific non-plist values
    if ([valueObject isKindOfClass:[NSError class]])
        return [(NSError *)valueObject toPropertyList];
    
    if ([valueObject isKindOfClass:[NSURL class]])
        return [valueObject absoluteString];
    
    // Handle containers explicitly since they might contain non-plist values
    // Map sets to arrays since NSSet isn't a plist type.
    if ([valueObject isKindOfClass:[NSArray class]] || [valueObject isKindOfClass:[NSSet class]]) {
        NSMutableArray *mapped = [NSMutableArray array];
        for (id unmappedValue in (id <NSFastEnumeration>)valueObject) {
            id mappedValue = _mapUserInfoValueToPlistValue(unmappedValue);
            OBASSERT(mappedValue); // mapping returns something for nil
            [mapped addObject:mappedValue];
        }
        return mapped;
    }

    if ([valueObject isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *mapped = [NSMutableDictionary dictionary];
        [(NSDictionary *)valueObject enumerateKeysAndObjectsUsingBlock:^(NSString  *key, id unmappedValue, BOOL *stop) {

            if ([key isEqualToString:NSRecoveryAttempterErrorKey]) {
                // Convert to a minimal plist value for logging/debugging
                [mapped setObject:[valueObject shortDescription] forKey:NSRecoveryAttempterErrorKey];
                return;
            }
            
#if INCLUDE_BACKTRACE_IN_ERRORS
            if ([key isEqualToString:OBBacktraceAddressesErrorKey]) {
                // Transform this to symbol names when actually interested in it.
                NSData *frameData = unmappedValue;
                const void* const* frames = [frameData bytes];
                NSUInteger frameCount = [frameData length] / sizeof(frames[0]);

                OBASSERT(frameCount < INT_MAX); // since backtrace_symbols only takes int.
                char **names = backtrace_symbols((void* const* )frames, (int)frameCount);
                if (names) {
                    NSMutableArray *namesArray = [NSMutableArray array];
                    for (NSUInteger nameIndex = 0; nameIndex < frameCount; nameIndex++)
                        [namesArray addObject:[NSString stringWithCString:names[nameIndex] encoding:NSUTF8StringEncoding]];
                    free(names);
                    
                    [mapped setObject:namesArray forKey:OBBacktraceNamesErrorKey];
                    return;
                }
            }
#endif
            
            id mappedValue = _mapUserInfoValueToPlistValue(unmappedValue);
            [mapped setObject:mappedValue forKey:key];
        }];
        return mapped;
    }
    
    // We can only bring along plist-able values (so, for example, no NSRecoveryAttempterErrorKey).
    if (![NSPropertyListSerialization propertyList:valueObject isValidForFormat:NSPropertyListXMLFormat_v1_0]) {
#ifdef DEBUG
        NSLog(@"'%@' of class '%@' is not a property list value.", valueObject, [valueObject class]);
#endif
        return [valueObject description];
    }
    
    return valueObject;
}

- (NSDictionary *)toPropertyList;
{
    NSMutableDictionary *plist = [NSMutableDictionary dictionary];
    
    [plist setObject:[self domain] forKey:@"domain"];
    [plist setObject:[NSNumber numberWithInteger:[self code]] forKey:@"code"];
    
    NSDictionary *userInfo = [self userInfo];
    if (userInfo)
        [plist setObject:_mapUserInfoValueToPlistValue(userInfo) forKey:@"userInfo"];
    
    return plist;
}

static NSString * const OFSuppressedErrorStack = @"com.omnigroup.OmniFoundation.SuppressedErrorStack"; // array of dictionaries
static NSString * const OFSuppressedErrorDomain = @"domain";
static NSString * const OFSuppressedErrorCode = @"code";

+ (void)suppressingLogsWithUnderlyingDomain:(NSString *)domain code:(NSInteger)code action:(void (^)(void))action;
{
    NSMutableDictionary *threadInfo = [[NSThread currentThread] threadDictionary];
    NSMutableArray *suppressionStack = threadInfo[OFSuppressedErrorStack];
    if (!suppressionStack) {
        suppressionStack = [NSMutableArray new];
        threadInfo[OFSuppressedErrorStack] = suppressionStack;
    }
    NSDictionary *suppression = @{OFSuppressedErrorDomain:domain, OFSuppressedErrorCode:@(code)};
    [suppressionStack addObject:suppression];
    
    action();
    
    OBASSERT([suppressionStack lastObject] == suppression);
    [suppressionStack removeLastObject];
    
    if ([suppressionStack count] == 0)
        [threadInfo removeObjectForKey:OFSuppressedErrorStack];
}

- (void)log:(NSString *)format, ...;
{
    va_list args;
    va_start(args, format);
    [self log:format arguments:args];
    va_end(args);
}

- (void)log:(NSString *)format arguments:(va_list)arguments;
{
    NSString *reason = [[NSString alloc] initWithFormat:format arguments:arguments];
    [self logWithReason:reason];
}

- (void)logWithReason:(NSString *)reason;
{
    if ([self causedByUserCancelling])
        return;
    
    NSMutableArray *suppressionStack = [[NSThread currentThread] threadDictionary][OFSuppressedErrorStack];
    if (suppressionStack) {
        NSString *domain = self.domain;
        NSNumber *code = @(self.code);
        for (NSDictionary *suppression in suppressionStack) {
            if ([domain isEqual:suppression[OFSuppressedErrorDomain]] && [code isEqual:suppression[OFSuppressedErrorCode]])
                return;
        }
    }
    
    NSLog(@"%@: %@", reason, [self toPropertyList]);
}

@end

