// Copyright 2005, 2012 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>

@class NSArray, NSURL;

@interface OAWorkflow : OFObject
{
    NSURL *_url;
}

+ (OAWorkflow *)workflowWithContentsOfFile:(NSString *)path error:(NSError **)outError;
+ (OAWorkflow *)workflowWithContentsOfURL:(NSURL *)url error:(NSError **)outError;

- (id)initWithContentsOfFile:(NSString *)path error:(NSError **)outError;
- (id)initWithContentsOfURL:(NSURL *)url error:(NSError **)outError;
- (void)executeWithFiles:(NSArray *)filePaths;

@end
