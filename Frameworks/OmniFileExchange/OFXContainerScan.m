// Copyright 2013,2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFXContainerScan.h"

RCS_ID("$Id$")

@implementation OFXContainerScan
{
    NSMutableArray <NSURL *> *_scannedFileURLs;
}

- initWithDocumentIndexState:(NSObject <NSCopying> *)indexState;
{
    if (!(self = [super init]))
        return nil;
    
    _documentIndexState = [indexState copy];
    _scannedFileURLs = [NSMutableArray new];
    
    return self;
}

@synthesize scannedFileURLs = _scannedFileURLs;
- (void)scannedFileAtURL:(NSURL *)fileURL;
{
    [_scannedFileURLs addObject:fileURL];
}

@end
