// Copyright 2013-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFileExchange/OFXFileMetadata.h>

// Our public interface marks these as read-only, but internally they are read-write so we can set up them up reasonably

@interface OFXFileMetadata ()

// The persistent identifier for the file used on the server.
@property(nonatomic,readwrite,copy) NSString *fileIdentifier;

// The server version of the file; nil if the file isn't fully uploaded. Guaranteed to change between versions, even if the creationDate/modificationDate don't
@property(nonatomic,readwrite,copy) NSString *editIdentifier;

@property(nonatomic,readwrite,copy) NSURL *fileURL;
@property(nonatomic,readwrite,copy) NSURL *intendedFileURL;
@property(nonatomic,readwrite) unsigned long long fileSize;

@property(nonatomic,readwrite,getter=isDirectory) BOOL directory;

@property(nonatomic,readwrite,copy) NSDate *creationDate;
@property(nonatomic,readwrite,copy) NSDate *modificationDate;

@property(nonatomic,readwrite) uint64_t totalSize;

@property(nonatomic,readwrite,getter=isDownloaded,setter=setIsDownloaded:) BOOL downloaded;
@property(nonatomic,readwrite,getter=isDownloading,setter=setIsDownloading:) BOOL downloading;
@property(nonatomic,readwrite) float percentDownloaded; // 0..1

@property(nonatomic,readwrite,getter=isUploaded,setter=setIsUploaded:) BOOL uploaded;
@property(nonatomic,readwrite,getter=isUploading,setter=setIsUploading:) BOOL uploading;
@property(nonatomic,readwrite) float percentUploaded; // 0..1

@property(nonatomic,readwrite) BOOL deleting;

@property(nonatomic,readwrite,copy) NSDate *fileModificationDate; // nil if the file isn't downloaded
@property(nonatomic,readwrite,copy) NSNumber *inode; // nil if the file isn't downloaded.

@end
