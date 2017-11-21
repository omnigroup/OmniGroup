// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniDocumentStore/ODSFilter.h>

#import <OmniDocumentStore/ODSStore.h>
#import <OmniDocumentStore/ODSScope.h>
#import <OmniDocumentStore/ODSFolderItem.h>
#import <OmniFoundation/OFBinding.h>

RCS_ID("$Id$");

static NSString * const UnfilteredSourceItems = @"unfilteredSourceItems";

@interface ODSFilter ()
@property(nonatomic,copy) NSSet *unfilteredSourceItems;
@property (nonatomic, readwrite) NSSet *filteredItems;
@end

@implementation ODSFilter
{
    // The incoming items from the document store
    OFSetBinding *_sourceItemsBinding;
    NSSet *_sourceItems;
}

- (instancetype)_initWithBindingSourcePoint:(OFBindingPoint *)sourceBindingPoint;
{
    if (!(self = [super init]))
        return nil;
    
    _sourceItemsBinding = [[OFSetBinding alloc] initWithSourcePoint:sourceBindingPoint
                                                   destinationPoint:OFBindingKeyPath(self, unfilteredSourceItems)];
    [_sourceItemsBinding propagateCurrentValue];
    
    return self;

}

- (instancetype)initWithStore:(ODSStore *)store;
{
    OBPRECONDITION(store);
    return [self _initWithBindingSourcePoint:OFBindingKeyPath(store, mergedFileItems)];
}

- (instancetype)initWithTopLevelOfScope:(ODSScope *)scope;
{
    OBPRECONDITION(scope);
    return [self _initWithBindingSourcePoint:OFBindingKeyPath(scope, topLevelItems)];
}

- (instancetype)initWithFileItemsInScope:(ODSScope *)scope;
{
    OBPRECONDITION(scope);
    return [self _initWithBindingSourcePoint:OFBindingKeyPath(scope, fileItems)];
}

- (instancetype)initWithFolderItem:(ODSFolderItem *)folder;
{
    OBPRECONDITION(folder);
    return [self _initWithBindingSourcePoint:OFBindingKeyPath(folder, childItems)];
}

- (void)dealloc;
{
    [_sourceItemsBinding invalidate];
}

- (ODSScope *)scope;
{
    id bindingSource = _sourceItemsBinding.sourceObject;
    
    if ([bindingSource isKindOfClass:[ODSFolderItem class]])
        return ((ODSFolderItem *)bindingSource).scope;
    else {
        OBASSERT([bindingSource isKindOfClass:[ODSScope class]]);
        return bindingSource;
    }
}

- (void)setFilterPredicate:(NSPredicate *)filterPredicate;
{
    OBPRECONDITION([NSThread isMainThread]); // We want to fire KVO only on the main thread
    
    if (filterPredicate == _filterPredicate)
        return;
    _filterPredicate = filterPredicate;
    [self _updateFilteredItems];
}

- (void)_updateFilteredItems
{
    OBPRECONDITION([NSThread isMainThread]); // We want to fire KVO only on the main thread
    if (_filterPredicate)
        self.filteredItems = [_sourceItems filteredSetUsingPredicate:_filterPredicate];
    else
        self.filteredItems = _sourceItems;
}

#pragma mark - Private

+ (BOOL)automaticallyNotifiesObserversOfUnfilteredSourceItems;
{
    return NO; // We do it in the setter (which we have so we can have the main thread assertion).
}

@synthesize unfilteredSourceItems = _sourceItems;
- (void)setUnfilteredSourceItems:(NSSet *)newItems;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    if (OFISEQUAL(_sourceItems, newItems))
        return;
    
    [self willChangeValueForKey:UnfilteredSourceItems];
    _sourceItems = [newItems copy];
    [self didChangeValueForKey:UnfilteredSourceItems];
    [self _updateFilteredItems];
}

@end
