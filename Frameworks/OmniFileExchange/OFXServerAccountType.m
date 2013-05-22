// Copyright 2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFileExchange/OFXServerAccountType.h>

// Hard coding the account types for now.
#import "OFXOmniSyncServerAccountType.h"
#import "OFXDAVServerAccountType.h"
#import "OFXiTunesLocalDocumentsServerAccountType.h"

RCS_ID("$Id$")

@implementation OFXServerAccountType

static NSMutableArray *AccountTypes = nil;

+ (void)initialize;
{
    OBINITIALIZE;
    
    AccountTypes = [[NSMutableArray alloc] init];
    
    OFXServerAccountType *type;
    
    type = [[OFXOmniSyncServerAccountType alloc] init];
    [self registerAccountType:type];
    
    type = [[OFXDAVServerAccountType alloc] init];
    [self registerAccountType:type];
    
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    type = [[OFXiTunesLocalDocumentsServerAccountType alloc] init];
    [self registerAccountType:type];
#endif
}

+ (void)registerAccountType:(OFXServerAccountType *)type;
{
    OBPRECONDITION([self accountTypeWithIdentifier:type.identifier] == nil);
    OBPRECONDITION([type conformsToProtocol:@protocol(OFXConcreteServerAccountType)]);
    
    [AccountTypes insertObject:type inArraySortedUsingSelector:@selector(_compareByPresentationPriority:)];
}

+ (NSArray *)accountTypes;
{
    return AccountTypes;
}

+ (OFXServerAccountType *)accountTypeWithIdentifier:(NSString *)identifier;
{
    for (OFXServerAccountType *type in AccountTypes)
        if ([type.identifier isEqualToString:identifier])
            return type;
    return nil;
}

- (NSString *)importTitleForDisplayName:(NSString *)displayName;
{
    if ([NSString isEmptyString:displayName])
        displayName = self.displayName;
    
    return displayName;
}

- (NSString *)exportTitleForDisplayName:(NSString *)displayName;
{
    if ([NSString isEmptyString:displayName])
        displayName = self.displayName;
    
    return [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Export to \"%@\"", @"OmniFileExchange", OMNI_BUNDLE, @"Server account export title format"), displayName];
}

- (NSURL *)baseURLForServerURL:(NSURL *)serverURL username:(NSString *)username;
{
    return serverURL;
}

#pragma mark - Private
            
- (NSComparisonResult)_compareByPresentationPriority:(OFXServerAccountType *)otherType;
{
    float priority = self.presentationPriority;
    float otherPriority = otherType.presentationPriority;
    OBASSERT(priority != otherPriority);
    
    if (priority < otherPriority)
        return NSOrderedAscending;
    return NSOrderedDescending;
}

@end
