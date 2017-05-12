// Copyright 2007-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFMultipleOptionErrorRecovery.h>

#import <OmniBase/rcsid.h>

#import <OmniFoundation/OFErrorRecovery.h>

RCS_ID("$Id$")

@implementation OFMultipleOptionErrorRecovery

+ (NSError *)errorRecoveryErrorWithError:(NSError *)error object:(id)object options:(id)option1, ...;
{
    OBPRECONDITION(option1);
    
    va_list args;
    va_start(args, option1);
    
    NSMutableArray *titles = [NSMutableArray array];
    NSMutableArray *recoveries = [NSMutableArray array];
    
    id option = option1;
    NSString *nextTitle = nil;
    
    while (option) {
        if ([option isKindOfClass:[NSString class]]) {
            OBASSERT(nextTitle == nil);
            nextTitle = option;
        } else if (OBPointerIsClass(option) && OBClassIsSubclassOfClass(option, [OFErrorRecovery class])) {
            Class recoveryClass = option;
            OFErrorRecovery *recovery = [[recoveryClass alloc] initWithLocalizedRecoveryOption:nextTitle object:object];
            if ([recovery isApplicableToError:error]) {
                [titles addObject:[recovery localizedRecoveryOption]];
                [recoveries addObject:recovery];
            }
            [recovery release];
            
            // Title is now consumed
            nextTitle = nil;
        } else {
            OBASSERT_NOT_REACHED("Unsupported option");
        }
        
        option = va_arg(args, id);
    }

    // The last option should not have been a string
    OBASSERT(nextTitle == nil);
    
    // Must have gotten at least one title/recovery pair
    if ([recoveries count] == 0) {
        OBASSERT([recoveries count] > 0);
        return error;
    }
    
    OFMultipleOptionErrorRecovery *recovery = [[[self alloc] initWithRecoveries:recoveries] autorelease];

    NSMutableDictionary *userInfo = [[[error userInfo] mutableCopy] autorelease];
    if (!userInfo)
        userInfo = [NSMutableDictionary dictionary];
    [userInfo setObject:titles forKey:NSLocalizedRecoveryOptionsErrorKey];
    [userInfo setObject:recovery forKey:NSRecoveryAttempterErrorKey];
    
    return [NSError errorWithDomain:[error domain] code:[error code] userInfo:userInfo];
}

- initWithRecoveries:(NSArray *)recoveries;
{
    if (!(self = [super init]))
        return nil;

    _recoveries = [recoveries copy];
    return self;
}

- (NSArray *)recoveries;
{
    return _recoveries;
}

- (id)firstRecoveryOfClass:(Class)cls;
{
    for (OFErrorRecovery *recovery in _recoveries) {
        recovery = [recovery firstRecoveryOfClass:cls];
        if (recovery)
            return recovery;
    }
    
    return nil;
}

- (void)dealloc;
{
    [_recoveries release];
    [super dealloc];
}

#pragma mark -
#pragma mark NSObject (NSErrorRecoveryAttempting)

- (void)attemptRecoveryFromError:(NSError *)error optionIndex:(NSUInteger)recoveryOptionIndex delegate:(id)delegate didRecoverSelector:(SEL)didRecoverSelector contextInfo:(void *)contextInfo;
{
    OBPRECONDITION(recoveryOptionIndex < [_recoveries count]);
    if (recoveryOptionIndex < [_recoveries count]) {
        [_recoveries[recoveryOptionIndex] attemptRecoveryFromError:error optionIndex:0 delegate:delegate didRecoverSelector:didRecoverSelector contextInfo:contextInfo];
    }
}

- (BOOL)attemptRecoveryFromError:(NSError *)error optionIndex:(NSUInteger)recoveryOptionIndex;
{
    // We used to have an OBPRECONDITION here that the recoveryOptionIndex was within the range of the _recoveries array, but had to let it go – this path can occur on quit, and when called, the recoveryOptionIndex inexplicably has value 8880. Instead, check the index and perform recovery using the indicated attempter if possible, or claim that recovery failed otherwise.
    // For more details, see bug:///135893 (Mac-OmniFocus Crasher: Crash closing if OmniFocus thinks we are still syncing)
    if (recoveryOptionIndex < [_recoveries count]) {
        return [_recoveries[recoveryOptionIndex] attemptRecoveryFromError:error];
    } else {
        return NO;
    }
}

@end
