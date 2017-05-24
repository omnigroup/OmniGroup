// Copyright 2013,2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>

@interface OFXContainerScan : NSObject

- initWithDocumentIndexState:(NSObject <NSCopying> *)indexState;

@property(nonatomic,readonly) NSObject <NSCopying> *documentIndexState;

@property(nonatomic,readonly) NSArray <NSURL *> *scannedFileURLs;
- (void)scannedFileAtURL:(NSURL *)fileURL;


@end
