// Copyright 2015-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>

@class OFFileEdit;

@interface OFFileMotionResult : NSObject

// The item at the given URL doesn't exist. Use this when the file motion is the result of metadata-based updates on the server for a file that hasn't been downloaded. The fileEdit of the result will be nil.
- (instancetype)initWithPromisedFileURL:(NSURL *)fileURL;

// For local files when you've already obtained the current OFFileEdit.
- (instancetype)initWithFileEdit:(OFFileEdit *)fileEdit;

@property(nonatomic,readonly) NSURL *fileURL;
@property(nonatomic,readonly) OFFileEdit *fileEdit;

@end
