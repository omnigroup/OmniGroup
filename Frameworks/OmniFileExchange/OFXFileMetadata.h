// Copyright 2013-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>

@interface OFXFileMetadata : NSObject

// The persistent identifier for the file used on the server.
@property(nonatomic,readonly,copy) NSString *fileIdentifier;

// The server version of the file; nil if the file isn't fully uploaded. Guaranteed to change between versions, even if the creationDate/modificationDate don't
@property(nonatomic,readonly,copy) NSString *editIdentifier;

@property(nonatomic,readonly,copy) NSURL *fileURL; // The location that the file is at or will appear at if downloaded under the current conditions
@property(nonatomic,readonly,copy) NSURL *intendedFileURL; // The location that the user wanted the file at. This might differ from the current fileURL if there are two files assigned to the same path (on different devices, presumably).
@property(nonatomic,readonly) unsigned long long fileSize;

@property(nonatomic,readonly,getter=isDirectory) BOOL directory;

@property(nonatomic,readonly,copy) NSDate *creationDate;
@property(nonatomic,readonly,copy) NSDate *modificationDate;

@property(nonatomic,readonly) BOOL hasDownloadQueued;

@property(nonatomic,readonly) uint64_t totalSize;

@property(nonatomic,readonly,getter=isDownloaded) BOOL downloaded;
@property(nonatomic,readonly,getter=isDownloading) BOOL downloading;
@property(nonatomic,readonly) float percentDownloaded; // 0..1

@property(nonatomic,readonly,getter=isUploaded) BOOL uploaded;
@property(nonatomic,readonly,getter=isUploading) BOOL uploading;
@property(nonatomic,readonly) float percentUploaded; // 0..1

@property(nonatomic,readonly,getter=isDeleting) BOOL deleting;

@property(nonatomic,readonly,copy) NSDate *fileModificationDate; // nil if the file isn't downloaded
@property(nonatomic,readonly,copy) NSNumber *inode; // nil if the file isn't downloaded.

@end

#import <OmniFoundation/OFBindingPoint.h>

#define OFXFileMetadataHasDownloadQueuedKey @"hasDownloadQueued"
#define OFXFileMetadataIsUploadedKey @"isUploaded"
#define OFXFileMetadataIsUploadingKey @"isUploading"
#define OFXFileMetadataPercentUploadedKey @"percentUploaded"
#define OFXFileMetadataIsDownloadedKey @"isDownloaded"
#define OFXFileMetadataIsDownloadQueuedKey @"isDownloadQueued"
#define OFXFileMetadataIsDownloadingKey @"isDownloading"
#define OFXFileMetadataPercentDownloadedKey @"percentDownloaded"
#define OFXFileMetadataIsDeletingKey @"isDeleting"
