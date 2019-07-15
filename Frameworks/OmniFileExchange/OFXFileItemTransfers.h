// Copyright 2013-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>

@class OFXFileItem;

@interface OFXFileItemTransfers : NSObject

- (void)addRequestedFileItem:(OFXFileItem *)fileItem;
- (void)removeRequestedFileItem:(OFXFileItem *)fileItem;
- (OFXFileItem *)anyRequest;
@property(nonatomic,readonly) NSUInteger numberRequested;

- (void)startedFileItem:(OFXFileItem *)fileItem;
- (void)finishedFileItem:(OFXFileItem *)fileItem;
@property(nonatomic,readonly) NSUInteger numberRunning;

- (BOOL)containsFileItem:(OFXFileItem *)fileItem;

@property(nonatomic,readonly,getter=isEmpty) BOOL empty;
- (void)reset;

@end

