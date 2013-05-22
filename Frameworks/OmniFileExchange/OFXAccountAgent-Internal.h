// Copyright 2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import "OFXAccountAgent.h"

@class OFXFileItem;

@interface OFXAccountAgent ()

- (void)_fileItemDidGenerateConflict:(OFXFileItem *)fileItem;
- (void)_fileItemDidDetectUnknownRemoteEdit:(OFXFileItem *)fileItem;

@property(nonatomic,readonly) NSOperationQueue *operationQueue;

@end

extern NSString * const OFXAccountAgentDidStopForReplacementNotification;

