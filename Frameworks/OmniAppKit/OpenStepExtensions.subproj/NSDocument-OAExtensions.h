// Copyright 2003-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <AppKit/NSDocument.h>

@interface NSDocument (OAExtensions)

- (NSArray <__kindof NSWindowController *> *)windowControllersOfClass:(Class)windowControllerClass;
- (NSArray <__kindof NSWindowController *> *)orderedWindowControllersOfClass:(Class)windowControllerClass;
- (__kindof NSWindowController *)frontWindowControllerOfClass:(Class)windowControllerClass;

- (NSArray <NSWindowController *> *)orderedWindowControllers;
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
