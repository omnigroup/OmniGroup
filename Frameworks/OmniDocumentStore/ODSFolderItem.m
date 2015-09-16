// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniDocumentStore/ODSFolderItem.h>

#import <OmniFoundation/OFNull.h>
#import <OmniFoundation/OFPreference.h>
#import <OmniFoundation/NSSet-OFExtensions.h>
#import <OmniFoundation/NSString-OFPathExtensions.h>

#import "ODSItem-Internal.h"
#import "ODSFileItem-Internal.h"
#import "ODSScope-Internal.h"

RCS_ID("$Id$");

NSString * const ODSFileItemRelativePathBinding = @"relativePath";
NSString * const ODSFolderItemChildItemsBinding = @"childItems";

@interface ODSFolderItem ()
@property(nonatomic,copy) NSDate *userModificationDate;
@property(nonatomic) BOOL isDownloaded;
@property(nonatomic) BOOL isDownloading;
@property(nonatomic) BOOL isUploaded;
@property(nonatomic) BOOL isUploading;
@property(nonatomic) uint64_t totalSize;
@property(nonatomic) uint64_t downloadedSize;
@property(nonatomic) uint64_t uploadedSize;
@end

@implementation ODSFolderItem
{
    NSString *_filename;
    NSString *_displayName;
    NSArray *_childItemsSortedByName;
}

- (void)dealloc;
{
    for (ODSItem *child in _childItems)
        [self _stopObservingChildItem:child];
}

- (void)setRelativePath:(NSString *)relativePath;
{
    if (OFISEQUAL(_relativePath, relativePath))
        return;
    
    [self willChangeValueForKey:ODSFileItemRelativePathBinding];
    _relativePath = [relativePath copy];
    _filename = [[_relativePath lastPathComponent] copy];
    
    // We tack on an explicit path extension, but if the user's OmniPresence directory had '2013.01' as a folder name, don't strip the '01'.
    if ([[_filename pathExtension] isEqual:OFDirectoryPathExtension])
        _displayName = [[_filename stringByDeletingPathExtension] copy];
    else
        _displayName = [_filename copy];
    
    [self didChangeValueForKey:ODSFileItemRelativePathBinding];
}

- (void)setChildItems:(NSSet *)childItems;
{
    if (OFISEQUAL(_childItems, childItems))
        return;
    
    for (ODSItem *child in childItems) {
        if ([_childItems member:child] == nil)
            [self _startObservingChildItem:child];
    }
    for (ODSItem *child in _childItems) {
        if ([childItems member:child] == nil)
            [self _stopObservingChildItem:child];
    }
    
    _childItems = [childItems copy];
    
    // We don't clear the parent point on children that are no longer in our set; we assume they'll be moved by the tree updating or invalidated
    for (ODSItem *child in _childItems)
        [child _setParentFolder:self];
    
    // Clear this for next time.
    _childItemsSortedByName = nil;
    
    [self _updateDerivedValues];
}

- (NSArray *)childItemsSortedByName;
{
    if (_childItemsSortedByName == nil)
        _childItemsSortedByName = [[_childItems allObjects] sortedArrayUsingComparator:^NSComparisonResult(ODSItem *child1, ODSItem *child2) {
            return [child1.name localizedStandardCompare:child2.name];
        }];
    return _childItemsSortedByName;
}

- (NSSet *)childrenContainingItems:(NSSet *)items;
{
    return [_childItems select:^BOOL(ODSItem *item) {
        return [item inOrContainsItemIn:items];
    }];
}

- (ODSFolderItem *)parentFolderOfItem:(ODSItem *)item;
{
    if ([_childItems member:item])
        return self;
    for (ODSItem *child in _childItems) {
        ODSFolderItem *folder = [child parentFolderOfItem:item];
        if (folder)
            return folder;
    }
    return nil;
}

- (ODSItem *)itemWithRelativePath:(NSString *)relativePath;
{
    ODSItem *item = self;
    for (NSString *component in [relativePath pathComponents]) {
        if (item.type != ODSItemTypeFolder)
            return nil;
        
        ODSFolderItem *folder = (ODSFolderItem *)item;
        item = [folder childItemWithFilename:component];
    }
    
    return item;
}

- (ODSItem *)childItemWithFilename:(NSString *)filename;
{
    return [_childItems any:^BOOL(ODSItem *item) {
        return [item hasFilename:filename];
    }];
}

+ (NSSet *)keyPathsForValuesAffectingName;
{
    return [NSSet setWithObjects:ODSFileItemRelativePathBinding, nil];
}

#pragma mark - ODSItem protocol

- (NSString *)name;
{
    return _displayName;
}

- (ODSItemType)type;
{
    return ODSItemTypeFolder;
}

- (BOOL)hasDownloadQueued;
{
    return NO;
}

- (void)addFileItems:(NSMutableSet *)fileItems;
{
    for (ODSItem *child in _childItems)
        [child addFileItems:fileItems];
}

- (void)eachItem:(void (^)(ODSItem *item))applier;
{
    applier(self);
    for (ODSItem *child in _childItems)
        [child eachItem:applier];
}

- (void)eachFile:(void (^)(ODSFileItem *file))applier;
{
    for (ODSItem *child in _childItems)
        [child eachFile:applier];
}

- (void)eachFolder:(void (^)(ODSFolderItem *folder, BOOL *stop))applier;
{
    BOOL stop = NO;
    applier(self, &stop);
    if (stop)
        return;
    
    for (ODSItem *child in _childItems)
        [child eachFolder:applier];
}

- (BOOL)inOrContainsItemIn:(NSSet *)items;
{
    if ([items member:self])
        return YES;
    return [_childItems any:^BOOL(ODSItem *child){ return [child inOrContainsItemIn:items]; }] != nil;
}

- (BOOL)hasFilename:(NSString *)filename;
{
    return [_filename localizedStandardCompare:filename] == NSOrderedSame;
}

#pragma mark - NSObject (NSKeyValueObserving)

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context;
{
    if (context == &ODSFolderItemContext) {
        
        // Do incremental updates. Bulk updates on this path are way too slow in the case of a ton of documents downloading.
        
        if ([keyPath isEqualToString:ODSItemUserModificationDateBinding]) {
            NSDate *date = change[NSKeyValueChangeNewKey];
            if (!_userModificationDate || (date && [_userModificationDate isAfterDate:date]))
                self.userModificationDate = date;
        } else if ([keyPath isEqualToString:ODSItemIsDownloadingBinding]) {
            NSNumber *oldValue = change[NSKeyValueChangeOldKey];
            OBASSERT(oldValue);
            NSNumber *newValue = change[NSKeyValueChangeNewKey];
            OBASSERT(newValue);
            
            if ([oldValue boolValue] == NO && [newValue boolValue])
                self.isDownloading = YES;
            else
                self.isDownloading = [_childItems any:^BOOL(ODSItem *child) { return child.isDownloading; }] != nil;
        } else if ([keyPath isEqualToString:ODSItemIsDownloadedBinding]) {
            NSNumber *oldValue = change[NSKeyValueChangeOldKey];
            OBASSERT(oldValue);
            NSNumber *newValue = change[NSKeyValueChangeNewKey];
            OBASSERT(newValue);
            
            if ([oldValue boolValue] == NO && [newValue boolValue])
                self.isDownloaded = YES;
            else
                self.isDownloaded = [_childItems all:^BOOL(ODSItem *child) { return child.isDownloaded; }];
        } else if ([keyPath isEqualToString:ODSItemIsUploadingBinding]) {
            NSNumber *oldValue = change[NSKeyValueChangeOldKey];
            OBASSERT(oldValue);
            NSNumber *newValue = change[NSKeyValueChangeNewKey];
            OBASSERT(newValue);
            
            if ([oldValue boolValue] == NO && [newValue boolValue])
                self.isUploading = YES;
            else
                self.isUploading = [_childItems any:^BOOL(ODSItem *child) { return child.isUploading; }] != nil;
        } else if ([keyPath isEqualToString:ODSItemIsUploadedBinding]) {
            NSNumber *oldValue = change[NSKeyValueChangeOldKey];
            OBASSERT(oldValue);
            NSNumber *newValue = change[NSKeyValueChangeNewKey];
            OBASSERT(newValue);
            
            if ([oldValue boolValue] == NO && [newValue boolValue])
                self.isUploaded = YES;
            else
                self.isUploaded = [_childItems all:^BOOL(ODSItem *child) { return child.isUploaded; }];
        } else if ([keyPath isEqualToString:ODSItemUploadedSizeBinding]) {
            NSNumber *oldValue = change[NSKeyValueChangeOldKey];
            OBASSERT(oldValue);
            NSNumber *newValue = change[NSKeyValueChangeNewKey];
            OBASSERT(newValue);
            
            self.uploadedSize = self.uploadedSize + [newValue unsignedLongLongValue] - [oldValue unsignedLongLongValue];
        } else if ([keyPath isEqualToString:ODSItemDownloadedSizeBinding]) {
            NSNumber *oldValue = change[NSKeyValueChangeOldKey];
            OBASSERT(oldValue);
            NSNumber *newValue = change[NSKeyValueChangeNewKey];
            OBASSERT(newValue);
            
            self.downloadedSize = self.downloadedSize + [newValue unsignedLongLongValue] - [oldValue unsignedLongLongValue];
        } else {
            [self _updateDerivedValues];
        }
    } else
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

#pragma mark - ODSItem Internal

- (void)_addMotions:(NSMutableArray *)motions toParentFolderURL:(NSURL *)destinationFolderURL isTopLevel:(BOOL)isTopLevel usedFolderNames:(NSMutableSet *)usedFolderNames ignoringFileItems:(NSSet *)ignoredFileItems;
{
    OBPRECONDITION([ignoredFileItems member:self] == nil, "We are a folder and shouldn't be in the set of ignored file items");
    
    // If we are a top-level copy (relative to the parent folder that contains the copies), then we need to pick a new folder name, but none of our children do.
    if (isTopLevel) {
        OBASSERT(usedFolderNames, "Need to unique the destination folder name in this case");
        
        NSUInteger counter = 0;
        __autoreleasing NSString *baseName;
        [_displayName splitName:&baseName andCounter:&counter];
        
        NSString *pathExtension = [NSString isEmptyString:[_displayName pathExtension]] ? nil : OFDirectoryPathExtension;
        
        NSString *destinationFolderName = ODSScopeFindAvailableName(usedFolderNames, baseName, pathExtension, &counter);
        
        [usedFolderNames addObject:destinationFolderName];
        
        for (ODSItem *item in _childItems)
            [item _addMotions:motions toParentFolderURL:[destinationFolderURL URLByAppendingPathComponent:destinationFolderName isDirectory:YES] isTopLevel:NO usedFolderNames:usedFolderNames ignoringFileItems:ignoredFileItems];
    } else {
        // Some ancestor directory has already provided a new base path.
        for (ODSItem *item in _childItems)
            [item _addMotions:motions toParentFolderURL:[destinationFolderURL URLByAppendingPathComponent:_filename isDirectory:YES] isTopLevel:NO usedFolderNames:usedFolderNames ignoringFileItems:ignoredFileItems];
    }
}

static unsigned ODSFolderItemContext;

- (void)_startObservingChildItem:(ODSItem *)item;
{
    [item addObserver:self forKeyPath:ODSItemUserModificationDateBinding options:0 context:&ODSFolderItemContext];
    [item addObserver:self forKeyPath:ODSItemIsDownloadedBinding options:NSKeyValueObservingOptionNew|NSKeyValueObservingOptionOld context:&ODSFolderItemContext];
    [item addObserver:self forKeyPath:ODSItemIsDownloadingBinding options:NSKeyValueObservingOptionNew|NSKeyValueObservingOptionOld context:&ODSFolderItemContext];
    [item addObserver:self forKeyPath:ODSItemIsUploadedBinding options:NSKeyValueObservingOptionNew|NSKeyValueObservingOptionOld context:&ODSFolderItemContext];
    [item addObserver:self forKeyPath:ODSItemIsUploadingBinding options:NSKeyValueObservingOptionNew|NSKeyValueObservingOptionOld context:&ODSFolderItemContext];
    [item addObserver:self forKeyPath:ODSItemTotalSizeBinding options:NSKeyValueObservingOptionNew|NSKeyValueObservingOptionOld context:&ODSFolderItemContext];
    [item addObserver:self forKeyPath:ODSItemDownloadedSizeBinding options:NSKeyValueObservingOptionNew|NSKeyValueObservingOptionOld context:&ODSFolderItemContext];
    [item addObserver:self forKeyPath:ODSItemUploadedSizeBinding options:NSKeyValueObservingOptionNew|NSKeyValueObservingOptionOld context:&ODSFolderItemContext];
}

- (void)_stopObservingChildItem:(ODSItem *)item;
{
    [item removeObserver:self forKeyPath:ODSItemUserModificationDateBinding context:&ODSFolderItemContext];
    [item removeObserver:self forKeyPath:ODSItemIsDownloadedBinding context:&ODSFolderItemContext];
    [item removeObserver:self forKeyPath:ODSItemIsDownloadingBinding context:&ODSFolderItemContext];
    [item removeObserver:self forKeyPath:ODSItemIsUploadedBinding context:&ODSFolderItemContext];
    [item removeObserver:self forKeyPath:ODSItemIsUploadingBinding context:&ODSFolderItemContext];
    [item removeObserver:self forKeyPath:ODSItemTotalSizeBinding context:&ODSFolderItemContext];
    [item removeObserver:self forKeyPath:ODSItemDownloadedSizeBinding context:&ODSFolderItemContext];
    [item removeObserver:self forKeyPath:ODSItemUploadedSizeBinding context:&ODSFolderItemContext];
}

- (void)_updateDerivedValues;
{
    // Kind of wasteful to enumerate the child set so many times...
    self.userModificationDate = [_childItems maxValueForKey:ODSItemUserModificationDateBinding comparator:^(NSDate *dateA, NSDate *dateB){
        return [dateA compare:dateB];
    }];
    self.isDownloaded = [_childItems all:^BOOL(ODSItem *child) { return child.isDownloaded; }];
    self.isDownloading = [_childItems any:^BOOL(ODSItem *child) { return child.isDownloading; }] != nil;
    self.isUploaded = [_childItems all:^BOOL(ODSItem *child) { return child.isUploaded; }];
    self.isUploading = [_childItems any:^BOOL(ODSItem *child) { return child.isUploading; }] != nil;
    
    uint64_t totalUploaded = 0;
    uint64_t totalDownloaded = 0;
    uint64_t totalSize = 0;
    for (ODSItem *child in _childItems) {
        totalSize += child.totalSize;
        totalUploaded += child.uploadedSize;
        totalDownloaded += child.downloadedSize;
    }
    self.totalSize = totalSize;
    self.uploadedSize = totalUploaded;
    self.downloadedSize = totalDownloaded;
}

#pragma mark - Debugging

- (NSString *)shortDescription;
{
    return [NSString stringWithFormat:@"<%@:%p %@>", NSStringFromClass([self class]), self, _relativePath];
}

@end
