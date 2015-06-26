// Copyright 2013-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import "OFXAccountAgent.h"

@class ODAVConnection;
@class OFXContainerAgent, OFXFileItem;

@interface OFXAccountAgent ()

- (ODAVConnection *)_makeConnection;

- (void)_fileItemDidDetectUnknownRemoteEdit:(OFXFileItem *)fileItem;
- (void)_containerAgentNeedsMetadataUpdate:(OFXContainerAgent *)container;

@property(nonatomic,readonly) NSOperationQueue *operationQueue;

@end

extern NSString * const OFXAccountAgentDidStopForReplacementNotification;

