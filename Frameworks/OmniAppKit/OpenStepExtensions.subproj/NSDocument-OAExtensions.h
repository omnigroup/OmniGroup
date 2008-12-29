// Copyright 2003-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <AppKit/NSDocument.h>

@interface NSDocument (OAExtensions)

- (NSFileWrapper *)fileWrapperOfType:(NSString *)typeName saveOperation:(NSSaveOperationType)saveOperationType error:(NSError **)outError;

// TODO: Eliminate remaining use of resource-fork backups, then delete these methods.
- (void)writeToBackupInResourceFork;
- (NSFileWrapper *)fileWrapperFromBackupInResourceFork;
- (BOOL)readFromBackupInResourceFork;
- (BOOL)hasBackupInResourceFork;
- (void)deleteAllBackupsInResourceFork;
- (void)deleteAllBackupsButMostRecentInResourceFork;

- (NSArray *)orderedWindowControllers;
- (NSWindowController *)frontWindowController;

// Status for long operations
- (void)startingLongOperation:(NSString *)operationName automaticallyEnds:(BOOL)shouldAutomaticallyEnd;
- (void)continuingLongOperation:(NSString *)operationStatus;
- (void)finishedLongOperation;

@end
