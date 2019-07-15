// Copyright 2008-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>

#import <OmniDAV/ODAVConnection.h>

@class NSURL, NSFileWrapper;

@interface ODAVUpload : NSObject

+ (void)uploadFileWrapper:(NSFileWrapper *)fileWrapper toURL:(NSURL *)toURL createParentCollections:(BOOL)createParentCollections connection:(ODAVConnection *)connection completionHandler:(ODAVConnectionURLCompletionHandler)completionHandler;

@end
