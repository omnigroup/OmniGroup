// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniDocumentStore/ODSStore.h>

@interface ODSStore ()
- (void)_fileWithURL:(NSURL *)oldURL andDate:(NSDate *)date willMoveToURL:(NSURL *)newURL;
- (void)_fileWithURL:(NSURL *)oldURL andDate:(NSDate *)date finishedMoveToURL:(NSURL *)newURL successfully:(BOOL)successfully;
- (void)_fileWithURL:(NSURL *)oldURL andDate:(NSDate *)date willCopyToURL:(NSURL *)newURL;
- (void)_fileWithURL:(NSURL *)oldURL andDate:(NSDate *)date finishedCopyToURL:(NSURL *)newURL andDate:(NSDate *)newDate successfully:(BOOL)successfully;
@end
