// Copyright 2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFileExchange/OFXAgentActivity.h>

#import <OmniFileExchange/OFXAgent.h>
#import <OmniFileExchange/OFXServerAccount.h>
#import <OmniFileExchange/OFXAccountActivity.h>
#import <OmniFoundation/OFBackgroundActivity.h>

RCS_ID("$Id$")

@interface OFXAgentActivity ()
@property(nonatomic,readwrite) BOOL isActive;
@property(nonatomic,readwrite,copy) NSSet *accountUUIDsWithErrors;
@end

@implementation OFXAgentActivity
{
    NSMutableDictionary *_accountUUIDToActivity;
    
    // Used to keep iOS apps running while background fetching is going on.
    OFBackgroundActivity *_backgroundActivity;
    NSTimer *_backgroundActivityFinishedTimer;
}

static unsigned AgentContext;
static unsigned AccountContext;

- initWithAgent:(OFXAgent *)agent;
{
    OBPRECONDITION(agent);
    
    if (!(self = [super init]))
        return nil;
    
    _agent = agent;
    _accountUUIDToActivity = [NSMutableDictionary new];
    
    [_agent addObserver:self forKeyPath:OFValidateKeyPath(_agent, runningAccounts) options:0 context:&AgentContext];
    [self _updateAccounts];
    
    return self;
}

- (void)dealloc;
{
    [_agent removeObserver:self forKeyPath:OFValidateKeyPath(_agent, runningAccounts) context:&AgentContext];
    [_accountUUIDToActivity enumerateKeysAndObjectsUsingBlock:^(NSString *uuid, OFXAccountActivity *accountActivity, BOOL *stop) {
        _stopObservingAccountActivity(self, accountActivity);
    }];
    
    [_backgroundActivityFinishedTimer invalidate];
    [_backgroundActivity finished];
}

- (OFXAccountActivity *)activityForAccount:(OFXServerAccount *)account;
{
    OBPRECONDITION([NSThread isMainThread], @"Do KVO and globals access on the main thread only");
    
    return [_accountUUIDToActivity objectForKey:account.uuid];
}

- (void)eachAccountActivityWithError:(void (^)(OFXAccountActivity *accountActivity))applier;
{
    OBPRECONDITION([NSThread isMainThread]);

    if (!applier)
        return;
    for (NSString *uuid in _accountUUIDsWithErrors) {
        OFXAccountActivity *accountActivity = _accountUUIDToActivity[uuid];
        OBASSERT(accountActivity.lastError);
        applier(accountActivity);
    }
}

#pragma mark - NSKeyValueObserving

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    if (object == _agent && context == &AgentContext) {
        [self _updateAccounts];
        return;
    }
    if (context == &AccountContext) {
        [self _activityStateChanged];
        return;
    }
    
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

#pragma mark - Private

static void _startObservingAccountActivity(OFXAgentActivity *self, OFXAccountActivity *accountActivity)
{
    [accountActivity addObserver:self forKeyPath:OFValidateKeyPath(accountActivity, isActive) options:0 context:&AccountContext];
    [accountActivity addObserver:self forKeyPath:OFValidateKeyPath(accountActivity, lastError) options:0 context:&AccountContext];
}

static void _stopObservingAccountActivity(OFXAgentActivity *self, OFXAccountActivity *accountActivity)
{
    [accountActivity removeObserver:self forKeyPath:OFValidateKeyPath(accountActivity, isActive) context:&AccountContext];
    [accountActivity removeObserver:self forKeyPath:OFValidateKeyPath(accountActivity, lastError) context:&AccountContext];
}

- (void)_updateAccounts;
{
    OBPRECONDITION([NSThread isMainThread], @"Do KVO and globals access on the main thread only");
    
    __block BOOL additionsOrRemovals = NO;
    
    NSMutableDictionary *remainingAccountUUIDToActivity = [_accountUUIDToActivity mutableCopy];
    
    for (OFXServerAccount *account in _agent.runningAccounts) {
        OFXAccountActivity *activity = [_accountUUIDToActivity objectForKey:account.uuid];
        if (activity) {
            [remainingAccountUUIDToActivity removeObjectForKey:account.uuid];
        } else {
            activity = [[OFXAccountActivity alloc] initWithRunningAccount:account agent:_agent];
            _startObservingAccountActivity(self, activity);
            [_accountUUIDToActivity setObject:activity forKey:account.uuid];
            additionsOrRemovals = YES;
        }
    }
    [remainingAccountUUIDToActivity enumerateKeysAndObjectsUsingBlock:^(NSString *uuid, OFXAccountActivity *activity, BOOL *stop) {
        _stopObservingAccountActivity(self, activity);
        [_accountUUIDToActivity removeObjectForKey:uuid];
        additionsOrRemovals = YES;
    }];
    
    if (additionsOrRemovals)
        [self _activityStateChanged];
}

- (void)_activityStateChanged;
{
    OBPRECONDITION([NSThread isMainThread], @"Do KVO and globals access on the main thread only");
    
    NSMutableSet *accountUUIDsWithErrors = [NSMutableSet new];
    BOOL isActive = NO;
    
    for (OFXAccountActivity *activity in [_accountUUIDToActivity allValues]) {
        if (activity.lastError)
            [accountUUIDsWithErrors addObject:activity.account.uuid];
        if (activity.isActive)
            isActive = YES;
    }
    if (_isActive != isActive) {
        self.isActive = isActive;
        DEBUG_ACTIVITY(1, "active:%d", self.isActive);
        
        // The goal here is to stay away for 3 seconds until after our last observed activity on any account (since we don't have a good notion of 'completion' for sync operations).

        if (_isActive) {
            [_backgroundActivityFinishedTimer invalidate];
            _backgroundActivityFinishedTimer = nil;
            if (!_backgroundActivity)
                _backgroundActivity = [OFBackgroundActivity backgroundActivityWithIdentifier:@"com.omnigroup.OmniFileExchange.OFXAgentActivity"];
        } else if (!_isActive && _backgroundActivity && !_backgroundActivityFinishedTimer) {
            _backgroundActivityFinishedTimer = [NSTimer scheduledTimerWithTimeInterval:3 target:self selector:@selector(_finishBackgroundActivityTimerFired:) userInfo:nil repeats:NO];
#if (defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE) || (defined(MAC_OS_X_VERSION_10_9) && MAC_OS_X_VERSION_10_9 >= MAC_OS_X_VERSION_MIN_REQUIRED)
            if ([_backgroundActivityFinishedTimer respondsToSelector:@selector(setTolerance:)])
                [_backgroundActivityFinishedTimer setTolerance:1];
#endif
        }
    }
    if (OFNOTEQUAL(_accountUUIDsWithErrors, accountUUIDsWithErrors)) {
        self.accountUUIDsWithErrors = accountUUIDsWithErrors;
        DEBUG_ACTIVITY(1, "uuids with errors:%@", [[self.accountUUIDsWithErrors allObjects] sortedArrayUsingSelector:@selector(compare:)]);
    }
}

- (void)_finishBackgroundActivityTimerFired:(NSTimer *)timer;
{
    OBPRECONDITION(timer == _backgroundActivityFinishedTimer);
    OBPRECONDITION(_isActive == NO, "Timer should have been cancelled if new activity started");
    
    OFBackgroundActivity *activity = _backgroundActivity;
    _backgroundActivity = nil;
    
    [activity finished];
}

@end
