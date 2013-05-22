// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>

@class OFSDocumentStoreScope;

extern NSString * const OFSDocumentStoreItemNameBinding;
extern NSString * const OFSDocumentStoreItemUserModificationDateBinding;

extern NSString * const OFSDocumentStoreItemReadyBinding;

// KVO properties that will mirror the OFXFileMetadata properties (or have sensible defaults for local documents).
extern NSString * const OFSDocumentStoreItemHasDownloadQueuedBinding;
extern NSString * const OFSDocumentStoreItemIsDownloadedBinding;
extern NSString * const OFSDocumentStoreItemIsDownloadingBinding;
extern NSString * const OFSDocumentStoreItemIsUploadedBinding;
extern NSString * const OFSDocumentStoreItemIsUploadingBinding;
extern NSString * const OFSDocumentStoreItemPercentDownloadedBinding;
extern NSString * const OFSDocumentStoreItemPercentUploadedBinding;

@interface OFSDocumentStoreItem : NSObject <NSCopying>

+ (NSString *)displayStringForDate:(NSDate *)date;

- initWithScope:(OFSDocumentStoreScope *)scope;

@property(weak,readonly,nonatomic) OFSDocumentStoreScope *scope;

@end

// Concrete stuff that subclasses must implement
@protocol OFSDocumentStoreItem <NSObject>
- (NSString *)name;
- (NSDate *)userModificationDate;

@property(nonatomic,readonly) BOOL hasDownloadQueued;
@property(nonatomic,readonly) BOOL isDownloaded;
@property(nonatomic,readonly) BOOL isDownloading;
@property(nonatomic,readonly) BOOL isUploaded;
@property(nonatomic,readonly) BOOL isUploading;
@property(nonatomic,readonly) double percentDownloaded;
@property(nonatomic,readonly) double percentUploaded;

@end
@interface OFSDocumentStoreItem (OFSDocumentStoreItem) <OFSDocumentStoreItem>
@end
