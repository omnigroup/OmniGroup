// Copyright 2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFXTestSaveFilePresenter.h"

#import "OFXTestCase.h"

RCS_ID("$Id$")

@interface OFXTestSaveFilePresenter () <NSFilePresenter>
@end

@implementation OFXTestSaveFilePresenter
{
    NSURL *_fromURL;
    BOOL _didWrite; // Only write once.
}

- initWithSaveToURL:(NSURL *)saveToURL fromURL:(NSURL *)fromURL;
{
    OBPRECONDITION(saveToURL);
    OBPRECONDITION(fromURL);
    
    if (!(self = [super init]))
        return nil;
    
    _saveToURL = [saveToURL copy];
    _fromURL = [fromURL copy];
    
    // Ensure that the directory-ness is right.
    NSNumber *isDirectory;
    NSError *error;
    NSCAssert([_fromURL getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:&error], @"_fromURL must exist");

    NSCAssert([isDirectory boolValue] == [[_fromURL absoluteString] hasSuffix:@"/"], @"Pass in a URL with the right trailing slash");
    NSCAssert([isDirectory boolValue] == [[_saveToURL absoluteString] hasSuffix:@"/"], @"Pass in a URL with the right trailing slash");
    
    _operationQueue = [[NSOperationQueue alloc] init];
    _operationQueue.maxConcurrentOperationCount = 1;
    
    [NSFileCoordinator addFilePresenter:self];
    
    return self;
}

#pragma mark - OFXTestHelper

- (void)tearDown;
{
    [NSFileCoordinator removeFilePresenter:self];
}

#pragma mark - NSFilePresenter

// These properties are declared implicit atomic by the system header
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wimplicit-atomic-properties"
@synthesize presentedItemURL = _saveToURL;
@synthesize presentedItemOperationQueue = _operationQueue;
#pragma clang diagnostic pop

- (void)savePresentedItemChangesWithCompletionHandler:(void (^)(NSError *errorOrNil))completionHandler;
{    
    // TODO: It is unclear if we are supposed to do a coordinated write here or not. We pass ourselves as the file presenter to avoid deadlock, at least (or we could dispatch this to another queue).
    if (!_didWrite) {
        [OFXTestCase copyFileURL:_fromURL toURL:_saveToURL filePresenter:self];
        _didWrite = YES;
    }
    
    if (completionHandler)
        completionHandler(nil);
}

@end
