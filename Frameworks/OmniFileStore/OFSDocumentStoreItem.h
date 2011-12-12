// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFileStore/OFSFeatures.h>

#if OFS_DOCUMENT_STORE_SUPPORTED

#import <OmniFoundation/OFObject.h>

@class OFSDocumentStore;

extern NSString * const OFSDocumentStoreItemNameBinding;
extern NSString * const OFSDocumentStoreItemDateBinding;

extern NSString * const OFSDocumentStoreItemReadyBinding;

// KVO properties that will mirror the NSMetadataItem properties for iCloud items (or have sensible defaults for local documents).
extern NSString * const OFSDocumentStoreItemHasUnresolvedConflictsBinding;
extern NSString * const OFSDocumentStoreItemIsDownloadedBinding;
extern NSString * const OFSDocumentStoreItemIsDownloadingBinding;
extern NSString * const OFSDocumentStoreItemIsUploadedBinding;
extern NSString * const OFSDocumentStoreItemIsUploadingBinding;
extern NSString * const OFSDocumentStoreItemPercentDownloadedBinding;
extern NSString * const OFSDocumentStoreItemPercentUploadedBinding;

@interface OFSDocumentStoreItem : OFObject

+ (NSString *)displayStringForDate:(NSDate *)date;

- initWithDocumentStore:(OFSDocumentStore *)documentStore;

@property(readonly,nonatomic) OFSDocumentStore *documentStore;

@end

// Concrete stuff that subclasses must implement
@protocol OFSDocumentStoreItem <NSObject>
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
@interface OFSDocumentStoreItem (OFSDocumentStoreItem) <OFSDocumentStoreItem>
@end

#endif // OFS_DOCUMENT_STORE_SUPPORTED
