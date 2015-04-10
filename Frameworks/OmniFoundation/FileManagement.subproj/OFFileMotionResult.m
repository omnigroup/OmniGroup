// Copyright 2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFFileMotionResult.h>

#import <OmniFoundation/OFFileEdit.h>

RCS_ID("$Id$");

@implementation OFFileMotionResult

// The item at the given URL doesn't exist. Use this when the file motion is the result of metadata-based updates on the server for a file that hasn't been downloaded. The fileEdit of the result will be nil.
- (instancetype)initWithPromisedFileURL:(NSURL *)fileURL;
{
    OBPRECONDITION(fileURL);
    
    if (!(self = [super init]))
        return nil;
    
    _fileURL = [fileURL copy];
    
    return self;
}

- (instancetype)initWithFileEdit:(OFFileEdit *)fileEdit;
{
    OBPRECONDITION(fileEdit);
    
    if (!(self = [super init]))
        return nil;
    
    _fileURL = [fileEdit.originalFileURL copy];
    _fileEdit = fileEdit;
    
    return self;
}

@end
