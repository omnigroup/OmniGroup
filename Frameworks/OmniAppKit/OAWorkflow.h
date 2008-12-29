// Copyright 2005 Omni Development, Inc.  All rights reserved.
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

+ (OAWorkflow *)workflowWithContentsOfFile:(NSString *)path;
+ (OAWorkflow *)workflowWithContentsOfURL:(NSURL *)url;

- (id)initWithContentsOfFile:(NSString *)path;
- (id)initWithContentsOfURL:(NSURL *)url;
- (void)executeWithFiles:(NSArray *)filePaths;

@end
