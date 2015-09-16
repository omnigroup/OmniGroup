// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>

@class ODSScope, ODSFileItem, ODSFolderItem;

extern NSString * const ODSItemNameBinding;
extern NSString * const ODSItemUserModificationDateBinding;
extern NSString * const ODSItemSelectedBinding;
extern NSString * const ODSItemScopeBinding;

// KVO properties that will mirror the OFXFileMetadata properties (or have sensible defaults for local documents).
extern NSString * const ODSItemHasDownloadQueuedBinding;
extern NSString * const ODSItemIsDownloadedBinding;
extern NSString * const ODSItemIsDownloadingBinding;
extern NSString * const ODSItemIsUploadedBinding;
extern NSString * const ODSItemIsUploadingBinding;
extern NSString * const ODSItemTotalSizeBinding;
extern NSString * const ODSItemDownloadedSizeBinding;
extern NSString * const ODSItemUploadedSizeBinding;
extern NSString * const ODSItemPercentDownloadedBinding;
extern NSString * const ODSItemPercentUploadedBinding;

// Avoids some -isKindOfClass: checks.
typedef NS_ENUM(NSUInteger, ODSItemType) {
    ODSItemTypeFile,
    ODSItemTypeFolder,
};

@interface ODSItem : NSObject <NSCopying>

+ (NSString *)displayStringForDate:(NSDate *)date;

- initWithScope:(ODSScope *)scope;

@property(nonatomic,readonly) BOOL isValid; // Will return NO once this item has been forgotten by its scope, or its scope has been removed.

@property(weak,nonatomic) ODSScope *scope;
@property(weak,readonly,nonatomic) ODSFolderItem *parentFolder;
@property(nonatomic,readonly) NSUInteger depth;

@property(assign,nonatomic) BOOL selected;

@property(nonatomic,readonly) double percentDownloaded;
@property(nonatomic,readonly) double percentUploaded;

@end

// Concrete stuff that subclasses must implement
@protocol ODSItem <NSObject>

@property(nonatomic,readonly) ODSItemType type;

- (NSString *)name;
- (NSDate *)userModificationDate;

@property(nonatomic,readonly) BOOL hasDownloadQueued;
@property(nonatomic,readonly) BOOL isDownloaded;
@property(nonatomic,readonly) BOOL isDownloading;
@property(nonatomic,readonly) BOOL isUploaded;
@property(nonatomic,readonly) BOOL isUploading;
@property(nonatomic,readonly) uint64_t totalSize;
@property(nonatomic,readonly) uint64_t downloadedSize;
@property(nonatomic,readonly) uint64_t uploadedSize;

- (void)addFileItems:(NSMutableSet *)fileItems;
- (void)eachItem:(void (^)(ODSItem *item))applier;
- (void)eachFile:(void (^)(ODSFileItem *file))applier;
- (void)eachFolder:(void (^)(ODSFolderItem *folder, BOOL *stop))applier; // Return NO to prune this folder's tree
- (BOOL)inOrContainsItemIn:(NSSet *)items;
- (ODSFolderItem *)parentFolderOfItem:(ODSItem *)item;
- (BOOL)hasFilename:(NSString *)filename;

@end
@interface ODSItem (ODSItem) <ODSItem>
@end
