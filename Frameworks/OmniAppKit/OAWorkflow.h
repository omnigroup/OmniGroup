// Copyright 2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniAppKit/OAWorkflow.h 68908 2005-10-03 19:30:38Z kc $

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
