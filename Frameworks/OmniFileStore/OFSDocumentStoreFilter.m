// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFileStore/OFSDocumentStoreFilter.h>

#import <OmniFileStore/OFSDocumentStore.h>
#import <OmniFileStore/OFSDocumentStoreScope.h>
#import <OmniFoundation/OFBinding.h>

RCS_ID("$Id$");

static NSString * const UnfilteredTopLevelItems = @"unfilteredTopLevelItems";

@interface OFSDocumentStoreFilter ()
@property(nonatomic,copy) NSSet *unfilteredTopLevelItems;
@end

@implementation OFSDocumentStoreFilter
{
    OFSDocumentStore *_documentStore;
    OFSDocumentStoreScope *_scope;
    
    // The incoming items from the document store
    OFSetBinding *_unfilteredTopItemsBinding;
    NSSet *_unfilteredTopLevelItems;
    
    NSPredicate *_filterPredicate;
}

- (id)initWithDocumentStore:(OFSDocumentStore *)documentStore scope:(OFSDocumentStoreScope *)scope;
{
    OBPRECONDITION(documentStore);
    OBPRECONDITION(scope.documentStore == documentStore);
    
    if (!(self = [super init]))
        return nil;
    
    _documentStore = documentStore;
    _scope = scope;
        
    _unfilteredTopItemsBinding = [[OFSetBinding alloc] initWithSourcePoint:OFBindingKeyPath(_scope, topLevelItems)
                                                          destinationPoint:OFBindingKeyPath(self, unfilteredTopLevelItems)];
    [_unfilteredTopItemsBinding propagateCurrentValue];

    return self;
}

- (void)dealloc;
{
    [_unfilteredTopItemsBinding invalidate];
}

- (void)setScope:(OFSDocumentStoreScope *)scope;
{
    OBPRECONDITION(scope.documentStore == _documentStore);
    
    if (scope == _scope)
        return;
    
    _scope = scope;
    
    [_unfilteredTopItemsBinding invalidate];
    _unfilteredTopItemsBinding = [[OFSetBinding alloc] initWithSourcePoint:OFBindingKeyPath(_scope, topLevelItems)
                                                          destinationPoint:OFBindingKeyPath(self, unfilteredTopLevelItems)];
    
    [_unfilteredTopItemsBinding propagateCurrentValue];
}

- (void)setFilterPredicate:(NSPredicate *)filterPredicate;
{
    OBPRECONDITION([NSThread isMainThread]); // We want to fire KVO only on the main thread
    
    if (filterPredicate == _filterPredicate)
        return;
    
    [self willChangeValueForKey:OFValidateKeyPath(self, filteredTopLevelItems)];
    
    _filterPredicate = filterPredicate;
    
    [self didChangeValueForKey:OFValidateKeyPath(self, filteredTopLevelItems)];
}


+ (NSSet *)keyPathsForValuesAffectingFilteredTopLevelItems;
{
    return [NSSet setWithObject:UnfilteredTopLevelItems];
}

- (NSSet *)filteredTopLevelItems;
{
    OBPRECONDITION([NSThread isMainThread]); // We want to fire KVO only on the main thread

    if (_filterPredicate)
        return [_unfilteredTopLevelItems filteredSetUsingPredicate:_filterPredicate];
    else
        return _unfilteredTopLevelItems;
}

#pragma mark - Private

+ (BOOL)automaticallyNotifiesObserversOfUnfilteredTopLevelItems;
{
    return NO; // We do it in the setter (which we have so we can have the main thread assertion).
}

@synthesize unfilteredTopLevelItems = _unfilteredTopLevelItems;
- (void)setUnfilteredTopLevelItems:(NSSet *)unfilteredTopLevelItems;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    if (OFISEQUAL(_unfilteredTopLevelItems, unfilteredTopLevelItems))
        return;
    
    [self willChangeValueForKey:UnfilteredTopLevelItems];
    _unfilteredTopLevelItems = [unfilteredTopLevelItems copy];
    [self didChangeValueForKey:UnfilteredTopLevelItems];
}

@end
