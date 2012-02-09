// Copyright 2010-2012 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFileStore/OFSFeatures.h>

#if OFS_DOCUMENT_STORE_SUPPORTED

@interface OFSDocumentStoreScope : NSObject <NSCopying> {
@private
    NSString *_containerID;
    NSURL *_url;
}

+ (OFSDocumentStoreScope *)defaultUbiquitousScope;
+ (BOOL)isFile:(NSURL *)fileURL inContainer:(NSURL *)containerURL;

- (id)initUbiquitousScopeWithContainerID:(NSString *)aContainerID;
- (id)initLocalScopeWithURL:(NSURL *)aURL;

- (BOOL)isFileInContainer:(NSURL *)fileURL;

@property(nonatomic,readonly,getter=isUbiquitous) BOOL ubiquitous;

- (NSURL *)containerURL;
- (NSURL *)documentsURL:(NSError **)outError;

@property (readonly, nonatomic) NSString *containerID;
@property (readonly, nonatomic) NSURL *url;

@end

#endif // OFS_DOCUMENT_STORE_SUPPORTED
