// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFileStore/OFSDocumentStoreFilter.h>

#if OFS_DOCUMENT_STORE_SUPPORTED

#import <OmniFileStore/OFSDocumentStore.h>
#import <OmniFoundation/OFBinding.h>

RCS_ID("$Id$");

NSString * const OFSFilteredDocumentStoreTopLevelItemsBinding = @"filteredTopLevelItems";
static NSString * const UnfilteredTopLevelItems = @"unfilteredTopLevelItems";

@interface OFSDocumentStoreFilter ()
@property(nonatomic,copy) NSSet *unfilteredTopLevelItems;
@end

@implementation OFSDocumentStoreFilter
{
    OFSDocumentStore *_documentStore;

    // The incoming items from the document store
    OFSetBinding *_unfilteredTopItemsBinding;
    NSSet *_unfilteredTopLevelItems;
    
    NSPredicate *_filterPredicate;
}

- (id)initWithDocumentStore:(OFSDocumentStore *)docStore;
{
    if (!(self = [super init]))
        return nil;
    
    _documentStore = [docStore retain];
    
    _unfilteredTopItemsBinding = [[OFSetBinding alloc] initWithSourcePoint:OFBindingPointMake(_documentStore, OFSDocumentStoreTopLevelItemsBinding)
                                                          destinationPoint:OFBindingPointMake(self, UnfilteredTopLevelItems)];
    [_unfilteredTopItemsBinding propagateCurrentValue];
    
    // by default take all comers.
    _filterPredicate = [NSPredicate predicateWithValue:YES];
    return self;
}

- (void)dealloc;
{
    [_documentStore release];
    [_unfilteredTopItemsBinding invalidate];
    [_unfilteredTopItemsBinding release];
    [_unfilteredTopLevelItems release];
    [_filterPredicate release];
    
    [super dealloc];
}

@synthesize documentStore = _documentStore;

@synthesize filterPredicate = _filterPredicate;

- (void)setFilterPredicate:(NSPredicate *)filterPredicate;
{
    OBPRECONDITION([NSThread isMainThread]); // We want to fire KVO only on the main thread
    
    if (filterPredicate == _filterPredicate)
        return;
    
    [self willChangeValueForKey:OFSFilteredDocumentStoreTopLevelItemsBinding];
    
    [_filterPredicate release];
    _filterPredicate = [filterPredicate retain];
    
    [self didChangeValueForKey:OFSFilteredDocumentStoreTopLevelItemsBinding];
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
    [_unfilteredTopLevelItems release];
    _unfilteredTopLevelItems = [unfilteredTopLevelItems copy];
    [self didChangeValueForKey:UnfilteredTopLevelItems];
}

@end

#endif // OFS_DOCUMENT_STORE_SUPPORTED
