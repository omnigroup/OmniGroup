// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIDocumentSyncActivityObserver.h"

@import OmniFileExchange;

@implementation OUIDocumentSyncActivityObserver
{
    OFXAgentActivity *_agentActivity;
    
    NSArray <OFXServerAccount *> *_orderedServerAccounts;
    NSMapTable <OFXServerAccount *, OFXAccountActivity *> *_observedAccountActivityByAccount;
}

static void *ServerAccountsObservationContext = &ServerAccountsObservationContext;
static void *AccountObservationContext = &AccountObservationContext; // Keys that don't affect ordering

- (instancetype)initWithAgentActivity:(OFXAgentActivity *)agentActivity;
{
    _agentActivity = agentActivity;
    
    _observedAccountActivityByAccount = [NSMapTable strongToStrongObjectsMapTable];
    
    OFXServerAccountRegistry *accountRegistry = _agentActivity.agent.accountRegistry;
    [accountRegistry addObserver:self forKeyPath:OFValidateKeyPath(accountRegistry, allAccounts) options:NSKeyValueObservingOptionInitial context:ServerAccountsObservationContext];
    
    return self;
}

- (void)dealloc;
{
    for (OFXServerAccount *account in _orderedServerAccounts) {
        [self _stopObservingServerAccount:account];
    }
    
    OFXServerAccountRegistry *accountRegistry = _agentActivity.agent.accountRegistry;
    [accountRegistry removeObserver:self forKeyPath:OFValidateKeyPath(accountRegistry, allAccounts) context:ServerAccountsObservationContext];
}

- (nullable OFXAccountActivity *)accountActivityForServerAccount:(OFXServerAccount *)account;
{
    return [_observedAccountActivityByAccount objectForKey:account];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context;
{
    if (context == ServerAccountsObservationContext) {
        [self _updateOrderedServerAccounts];
    } else if (context == AccountObservationContext) {
        if (_accountChanged) {
            OFXServerAccount *account;
            if ([object isKindOfClass:[OFXServerAccount class]]) {
                account = object;
            } else if ([object isKindOfClass:[OFXRegistrationTable class]]) {
                account = [_orderedServerAccounts first:^BOOL(OFXServerAccount *candidate) {
                    return [[_agentActivity activityForAccount:candidate] registrationTable] == object;
                }];
            } else {
                OBASSERT_NOT_REACHED("Unrecognized object");
                return;
            }
            _accountChanged(account);
        }
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

- (void)_accountActivityForAccountChangedNotification:(NSNotification *)note;
{
    OFXServerAccount *account = OB_CHECKED_CAST(OFXServerAccount, note.object);
    OFXAccountActivity *accountActivity = [_agentActivity activityForAccount:account];
    [self _updateAccountActivity:accountActivity forServerAccount:account];
    _accountChanged(account);
}

- (void)_updateAccountActivity:(OFXAccountActivity *)newAccountActivity forServerAccount:(OFXServerAccount *)account;
{
    OFXAccountActivity *oldAccountActivity = [_observedAccountActivityByAccount objectForKey:account];
    
    if (oldAccountActivity == newAccountActivity) {
        return;
    }
    if (oldAccountActivity) {
        OFXRegistrationTable *table = oldAccountActivity.registrationTable;
        [table removeObserver:self forKeyPath:OFValidateKeyPath(table, values) context:AccountObservationContext];
        [_observedAccountActivityByAccount removeObjectForKey:account];
    }
    if (newAccountActivity) {
        [_observedAccountActivityByAccount setObject:newAccountActivity forKey:account];
        OFXRegistrationTable *table = newAccountActivity.registrationTable;
        [table addObserver:self forKeyPath:OFValidateKeyPath(table, values) options:0 context:AccountObservationContext];
    }
}

- (void)_startObservingServerAccount:(OFXServerAccount *)account;
{
    OBASSERT([_observedAccountActivityByAccount objectForKey:account] == nil);
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_accountActivityForAccountChangedNotification:) name:OFXAgentActivityActivityForAccountDidChangeNotification object:account];

    OFXAccountActivity *accountActivity = [_agentActivity activityForAccount:account];
    [self _updateAccountActivity:accountActivity forServerAccount:account];
    
    [account addObserver:self forKeyPath:OFValidateKeyPath(account, displayName) options:0 context:AccountObservationContext];
}

- (void)_stopObservingServerAccount:(OFXServerAccount *)account;
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:OFXAgentActivityActivityForAccountDidChangeNotification object:account];

    [self _updateAccountActivity:nil forServerAccount:account];

    [account removeObserver:self forKeyPath:OFValidateKeyPath(account, displayName) context:AccountObservationContext];
}

- (void)_updateOrderedServerAccounts;
{
    OFXServerAccountRegistry *accountRegistry = _agentActivity.agent.accountRegistry;
    NSMutableArray <OFXServerAccount *> *accountsToRemove = [_orderedServerAccounts mutableCopy];
    NSMutableArray <OFXServerAccount *> *accountsToAdd = [[NSMutableArray alloc] initWithArray: accountRegistry.allAccounts];
    
    NSMutableArray *newOrderedServerAccounts = [accountsToAdd mutableCopy];
    [newOrderedServerAccounts sortUsingComparator:^NSComparisonResult(OFXServerAccount *accountA, OFXServerAccount *accountB){
        return [accountA.displayName localizedStandardCompare:accountB.displayName];
    }];
    
    for (OFXServerAccount *account in accountsToAdd)
        [accountsToRemove removeObject:account];

    for (OFXServerAccount *account in _orderedServerAccounts)
        [accountsToAdd removeObject:account];

    for (OFXServerAccount *account in accountsToRemove) {
        [self _stopObservingServerAccount:account];
    }
    for (OFXServerAccount *account in accountsToAdd) {
        [self _startObservingServerAccount:account];
    }

    _orderedServerAccounts = [newOrderedServerAccounts copy];

    if (_accountsUpdated) {
        _accountsUpdated(newOrderedServerAccounts, accountsToAdd, accountsToRemove);
    }
}

@end
