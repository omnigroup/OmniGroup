// Copyright 2007-2009 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFErrorRecovery.h>

RCS_ID("$Id$");

@implementation OFErrorRecovery

+ (NSError *)errorRecoveryErrorWithError:(NSError *)error;
{
    return [self errorRecoveryErrorWithError:error object:nil];
}

+ (NSError *)errorRecoveryErrorWithError:(NSError *)error object:(id)object;
{
    return [self errorRecoveryErrorWithError:error localizedRecoveryOption:nil object:object];
}

// Returns a new error with an instance of the receiving class as the error recovery.
+ (NSError *)errorRecoveryErrorWithError:(NSError *)error localizedRecoveryOption:(NSString *)localizedRecoveryOption object:(id)object;
{
    OFErrorRecovery *recovery = [[[self alloc] initWithLocalizedRecoveryOption:localizedRecoveryOption object:object] autorelease];

    NSMutableDictionary *userInfo = [[[error userInfo] mutableCopy] autorelease];
    if (!userInfo)
        userInfo = [NSMutableDictionary dictionary];
    [userInfo setObject:[NSArray arrayWithObject:[recovery localizedRecoveryOption]] forKey:NSLocalizedRecoveryOptionsErrorKey];
    [userInfo setObject:recovery forKey:NSRecoveryAttempterErrorKey];
    
    return [NSError errorWithDomain:[error domain] code:[error code] userInfo:userInfo];
}

- initWithLocalizedRecoveryOption:(NSString *)localizedRecoveryOption object:(id)object;
{
    if (![super init])
        return nil;

    if (!localizedRecoveryOption)
        localizedRecoveryOption = [[self class] defaultLocalizedRecoveryOption];
    
    _localizedRecoveryOption = [localizedRecoveryOption copy];
    _object = [object retain];
    
    return self;
}

- (void)dealloc;
{
    [_localizedRecoveryOption release];
    [_object release];
    [super dealloc];
}

- (NSString *)localizedRecoveryOption;
{
    return _localizedRecoveryOption;
}

- (id)object;
{
    return _object;
}

- (id)firstRecoveryOfClass:(Class)cls;
{
    if ([self isKindOfClass:cls])
        return self;
    return nil;
}

#pragma mark -
#pragma mark Subclass responsibility

+ (NSString *)defaultLocalizedRecoveryOption;
{
    OBRequestConcreteImplementation(self, _cmd);
    return @"Attempt Recovery"; // Not localized since subclasses should really do this
}

- (BOOL)isApplicableToError:(NSError *)error;
{
    return YES;
}

- (BOOL)attemptRecoveryFromError:(NSError *)error;
{
    return [self attemptRecovery];
}

- (BOOL)attemptRecovery;
{
    return NO;
}

#pragma mark -
#pragma mark NSObject (NSErrorRecoveryAttempting)

- (void)attemptRecoveryFromError:(NSError *)error optionIndex:(NSUInteger)recoveryOptionIndex delegate:(id)delegate didRecoverSelector:(SEL)didRecoverSelector contextInfo:(void *)contextInfo;
{
    OBPRECONDITION(recoveryOptionIndex == 0); // Use OFMultipleOptionErrorRecovery if you need multiple options
    
    BOOL didRecover = [self attemptRecoveryFromError:error];
    
    if (delegate && didRecoverSelector) {
        NSMethodSignature *signature = [delegate methodSignatureForSelector:didRecoverSelector];
        if (!signature) {
            NSLog(@"%@ doesn't implement %@; ignoring", [delegate shortDescription], NSStringFromSelector(didRecoverSelector));
        } else {
            NSInvocation *invoke = [NSInvocation invocationWithMethodSignature:signature];
            [invoke setSelector:didRecoverSelector];
            [invoke setArgument:(void *)&didRecover atIndex:2];
            [invoke invokeWithTarget:delegate];
        }
    }
}

- (BOOL)attemptRecoveryFromError:(NSError *)error optionIndex:(NSUInteger)recoveryOptionIndex;
{
    OBPRECONDITION(recoveryOptionIndex == 0); // Use OFMultipleOptionErrorRecovery if you need multiple options
    return [self attemptRecoveryFromError:error];
}


@end
