// Copyright 2010-2012 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFileStore/OFSDocumentStore.h>

@interface OFSDocumentStore ()
- (void)_fileWithURL:(NSURL *)oldURL andDate:(NSDate *)date didMoveToURL:(NSURL *)newURL;
- (void)_fileWithURL:(NSURL *)oldURL andDate:(NSDate *)date didCopyToURL:(NSURL *)newURL andDate:(NSDate *)newDate;
@end
