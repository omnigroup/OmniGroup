// Copyright 2003-2010, 2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <AppKit/NSDocument.h>

@interface NSDocument (OAExtensions)

- (NSArray *)orderedWindowControllers;
- (NSWindowController *)frontWindowController;

// Status for long operations
- (void)startingLongOperation:(NSString *)operationName automaticallyEnds:(BOOL)shouldAutomaticallyEnd;
- (void)continuingLongOperation:(NSString *)operationStatus;
- (void)finishedLongOperation;

@end

#import <OmniFoundation/OFSaveType.h>
#import <OmniBase/assertions.h>

static inline OFSaveType OFSaveTypeForSaveOperationType(NSSaveOperationType operation)
{
    OBPRECONDITION(operation <= (NSSaveOperationType)OFSaveTypeAutosaveInPlace);
    return (OFSaveType)operation;
}
