// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>

@class OUIDocumentStore;

extern NSString * const OUIDocumentStoreItemNameBinding;
extern NSString * const OUIDocumentStoreItemDateBinding;

extern NSString * const OUIDocumentStoreItemReadyBinding;

// KVO properties that will mirror the NSMetadataItem properties for iCloud items (or have sensible defaults for local documents).
extern NSString * const OUIDocumentStoreItemHasUnresolvedConflictsBinding;
extern NSString * const OUIDocumentStoreItemIsDownloadedBinding;
extern NSString * const OUIDocumentStoreItemIsDownloadingBinding;
extern NSString * const OUIDocumentStoreItemIsUploadedBinding;
extern NSString * const OUIDocumentStoreItemIsUploadingBinding;
extern NSString * const OUIDocumentStoreItemPercentDownloadedBinding;
extern NSString * const OUIDocumentStoreItemPercentUploadedBinding;

@interface OUIDocumentStoreItem : OFObject

+ (NSString *)displayStringForDate:(NSDate *)date;

- initWithDocumentStore:(OUIDocumentStore *)documentStore;

@property(readonly,nonatomic) OUIDocumentStore *documentStore;
@property(assign,nonatomic) CGRect frame;

@property(assign,nonatomic) BOOL layoutShouldAdvance; // Stack the next item on top of this one during layout

@end

// Concrete stuff that subclasses must implement
@protocol OUIDocumentStoreItem <NSObject>
- (NSString *)name;
- (NSDate *)date;

@property(readonly,nonatomic,getter=isReady) BOOL ready; // It doesn't make sense to have an item without a date; this method returns NO while the item is loading its date (via a coordinated read). Subclasses can override this method to add additional properties that should prevent this item from being considered "ready". Previews are probably not a good candidate for that condition.

@property(nonatomic,readonly) BOOL hasUnresolvedConflicts;
@property(nonatomic,readonly) BOOL isDownloaded;
@property(nonatomic,readonly) BOOL isDownloading;
@property(nonatomic,readonly) BOOL isUploaded;
@property(nonatomic,readonly) BOOL isUploading;
@property(nonatomic,readonly) double percentDownloaded;
@property(nonatomic,readonly) double percentUploaded;

@end
@interface OUIDocumentStoreItem (OUIDocumentStoreItem) <OUIDocumentStoreItem>
@end
