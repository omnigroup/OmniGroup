// Copyright 2013-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFXFileItem.h"

@class OFXFileMetadata;

@interface OFXFileItem ()

@property(nonatomic,readonly) BOOL isValidToUpload;
@property(nonatomic,readonly) BOOL isDownloaded; // YES if the current snapshot refers to a full published document instead of a stub.
@property(nonatomic,readonly) BOOL presentOnServer; // YES if there is some version on the server

@property(nonatomic,readonly) BOOL hasCurrentTransferBeenCancelled;

@property(nonatomic,readonly) NSString *publishedFileVersion;

@property(nonatomic,readonly) NSString *debugName;

- (OFXFileMetadata *)_makeMetadata;

- (NSURL *)_intendedLocalDocumentURL;

@end
