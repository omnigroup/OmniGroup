// Copyright 2003-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "NSDocument-OAExtensions.h"

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <OmniBase/rcsid.h>
#import <OmniBase/OBUtilities.h>
#import <OmniFoundation/OmniFoundation.h>

#import "NSWindowController-OAExtensions.h"
#import "NSWindow-OAExtensions.h"

RCS_ID("$Id$");

#define OmniAppKitBackupFourCharCode FOUR_CHAR_CODE('OABK')

@interface NSDocument (OAExtensions_Private)
- (OFResourceFork *)_newResourceForkCreateIfMissing:(BOOL)create;
@end

@implementation NSDocument (OAExtensions)

#ifdef OMNI_ASSERTIONS_ON

static void checkDeprecatedSelector(Class documentSubclass, Class documentClass, SEL sel)
{
    if (documentClass != OBClassImplementingMethod(documentSubclass, sel))
	NSLog(@"%@ is implementing %@, but this is deprecated!", NSStringFromClass(documentSubclass), NSStringFromSelector(sel));
}
#define CHECK_DOCUMENT_API(sel) checkDeprecatedSelector(aClass, self, sel)

+ (void)didLoad;
{
    // Check that no deprecated APIs are implemented in subclasses of NSDocument.  NSDocument changes its behavior if you *implement* the deprecated APIs and we want to stay on the mainstream path.
    // This assumes that all NSDocument subclasses are present at launch time.
    
    // Get the class list
    unsigned int classCount = 0, newClassCount = objc_getClassList(NULL, 0);
    Class *classes = NULL;
    while (classCount < newClassCount) {
	classCount = newClassCount;
	classes = realloc(classes, sizeof(Class) * classCount);
	newClassCount = objc_getClassList(classes, classCount);
    }
    
    if (classes != NULL) {
	unsigned int classIndex;
	
	// Loop over the gathered classes and process the requested implementations
	for (classIndex = 0; classIndex < classCount; classIndex++) {
	    Class aClass = classes[classIndex];
	    
	    if (aClass != self && OBClassIsSubclassOfClass(aClass, self)) {
		CHECK_DOCUMENT_API(@selector(dataRepresentationOfType:));
		CHECK_DOCUMENT_API(@selector(fileAttributesToWriteToFile:ofType:saveOperation:));
		CHECK_DOCUMENT_API(@selector(fileName));
		CHECK_DOCUMENT_API(@selector(fileWrapperRepresentationOfType:));
		CHECK_DOCUMENT_API(@selector(initWithContentsOfFile:ofType:));
		CHECK_DOCUMENT_API(@selector(initWithContentsOfURL:ofType:));
		CHECK_DOCUMENT_API(@selector(loadDataRepresentation:ofType:));
		CHECK_DOCUMENT_API(@selector(loadFileWrapperRepresentation:ofType:));
		CHECK_DOCUMENT_API(@selector(printShowingPrintPanel:));
		CHECK_DOCUMENT_API(@selector(readFromFile:ofType:));
		CHECK_DOCUMENT_API(@selector(readFromURL:ofType:));
		CHECK_DOCUMENT_API(@selector(revertToSavedFromFile:ofType:));
		CHECK_DOCUMENT_API(@selector(revertToSavedFromURL:ofType:));
		CHECK_DOCUMENT_API(@selector(runModalPageLayoutWithPrintInfo:));
		CHECK_DOCUMENT_API(@selector(saveToFile:saveOperation:delegate:didSaveSelector:contextInfo:));
		CHECK_DOCUMENT_API(@selector(setFileName:));
		CHECK_DOCUMENT_API(@selector(writeToFile:ofType:));
		CHECK_DOCUMENT_API(@selector(writeToFile:ofType:originalFile:saveOperation:));
		CHECK_DOCUMENT_API(@selector(writeToURL:ofType:));
		CHECK_DOCUMENT_API(@selector(writeWithBackupToFile:ofType:saveOperation:));
	    }
	}
    }
}
#endif

- (NSFileWrapper *)fileWrapperOfType:(NSString *)typeName saveOperation:(NSSaveOperationType)saveOperationType error:(NSError **)outError;
/*" Methods that care about the save operation when building their file wrapper can subclass this.  OmniAppKit's NSDocument support for autosave calls this method, but currently no other code path does, so you still need to override -fileWrapperOfType:error:.  This just gives the autosave support a way to inform the document that it is saving with a specific operation during autosave. "*/
{
    return [self fileWrapperOfType:typeName error:outError];
}

- (void)writeToBackupInResourceFork;
{
    NSString *fileName = [[self fileURL] path];
    if (!fileName)
        return;

    NSError *error = nil;
    NSFileWrapper *wrapper = [self fileWrapperOfType:[self fileType] saveOperation:NSSaveOperation error:&error];
    if (error)
	NSLog(@"Failed to create file wrapper in %s -- %@", __PRETTY_FUNCTION__, error);
    NSData *contentData = [wrapper serializedRepresentation];

    OFResourceFork *newFork = [self _newResourceForkCreateIfMissing:YES];
    OBASSERT(newFork != nil);
    [newFork setData:contentData forResourceType:OmniAppKitBackupFourCharCode];
    // release newFork so that deleteAllBackups... can open it.
    [newFork release];
    [self deleteAllBackupsButMostRecentInResourceFork];
}

- (NSFileWrapper *)fileWrapperFromBackupInResourceFork;
{
    OFResourceFork *newFork = [self _newResourceForkCreateIfMissing:NO];
    if (!newFork)
        return nil;
    
    // if we're maintaining our resource data correctly there are two possibilities:
    // - we have 2 backups because we crashed doing a backup.  So use the penultimate backup
    // - we have one backup because life is good.  Use the last backup
    // in either case, this means we want to load the backup at index 0.
    NSData *backupData = [newFork dataForResourceType:OmniAppKitBackupFourCharCode atIndex:0];
    NSFileWrapper *wrapper = [[[NSFileWrapper alloc] initWithSerializedRepresentation:backupData] autorelease];
    [newFork release];

    return wrapper;
}

- (BOOL)readFromBackupInResourceFork;
{
    NSFileWrapper *wrapper = [self fileWrapperFromBackupInResourceFork];
    NSError *err = nil;
    if (![self readFromFileWrapper:wrapper ofType:[self fileType] error:&err]) {
        [self presentError:err];
        return NO;
    } else
        return YES;
}

- (BOOL)hasBackupInResourceFork;
{
    OFResourceFork *newFork = [self _newResourceForkCreateIfMissing:NO];
    
    if (!newFork)
        return NO;

    short count = [newFork countForResourceType:OmniAppKitBackupFourCharCode];
    
    BOOL result = (count > 0);

    [newFork release];

    return result;
}

- (void)deleteAllBackupsInResourceFork;
{
    OFResourceFork *newFork = [self _newResourceForkCreateIfMissing:NO];
    if (!newFork)
        return;

    int count = [newFork countForResourceType:OmniAppKitBackupFourCharCode];
    while (count-- > 0) {
        [newFork deleteResourceOfType:OmniAppKitBackupFourCharCode atIndex:count];
        OBASSERT([newFork countForResourceType:OmniAppKitBackupFourCharCode] == count);
    }

    [newFork release];
}

- (void)deleteAllBackupsButMostRecentInResourceFork;
{
    OFResourceFork *newFork = [self _newResourceForkCreateIfMissing:NO];
    if (!newFork)
        return;
    
    int count = [newFork countForResourceType:OmniAppKitBackupFourCharCode];

    while (count-- > 1) {
        [newFork deleteResourceOfType:OmniAppKitBackupFourCharCode atIndex:count - 1];
        OBASSERT([newFork countForResourceType:OmniAppKitBackupFourCharCode] == count);
    }

    [newFork release];
}

- (NSArray *)orderedWindowControllers;
{
    NSArray *orderedWindows = [NSWindow windowsInZOrder]; // Doesn't include miniaturized or ordered out windows
    NSArray *loadedWindowControllers = [[self windowControllers] objectsSatisfyingCondition:@selector(isWindowLoaded)]; // don't provoke loading of windows we don't need
    
    NSMutableArray *loadedWindows = [[[loadedWindowControllers valueForKey:@"window"] mutableCopy] autorelease];
    [loadedWindows sortBasedOnOrderInArray:orderedWindows identical:YES unknownAtFront:NO];
    
    // Actually want the window controllers
    return [loadedWindows valueForKey:@"delegate"];
}

- (NSWindowController *)frontWindowController;
{
    NSArray *windowControllers = [self orderedWindowControllers];
    if ([windowControllers count] == 0)
        return nil;
    return [windowControllers objectAtIndex:0];
}

- (void)startingLongOperation:(NSString *)operationName automaticallyEnds:(BOOL)shouldAutomaticallyEnd;
{
    NSWindowController *windowController = [self frontWindowController];
    if (windowController)
        [NSWindowController startingLongOperation:operationName controlSize:NSSmallControlSize inWindow:[windowController window] automaticallyEnds:shouldAutomaticallyEnd];
    else
        [NSWindowController startingLongOperation:operationName controlSize:NSSmallControlSize];
}

- (void)continuingLongOperation:(NSString *)operationStatus;
{
    [NSWindowController continuingLongOperation:operationStatus];
}

- (void)finishedLongOperation;
{
    [NSWindowController finishedLongOperation];
}

@end


@implementation NSDocument (OAExtensions_Private)

- (OFResourceFork *)_newResourceForkCreateIfMissing:(BOOL)create;
{
    BOOL isDirectory = NO;
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSURL *fileLocation = [self fileURL];
    
    if (!fileLocation || ![fileLocation isFileURL])
        return nil;
    
    NSString *fileName = [fileLocation path];

    if (!fileName || ![fileManager fileExistsAtPath:fileName isDirectory:&isDirectory])
        return nil;

    if (isDirectory) {
        NSString *insideWrapperFilename = [fileName stringByAppendingPathComponent:@".OABK"];

        if (![fileManager fileExistsAtPath:insideWrapperFilename]) {
            if (!create)
                return nil;
            
            if (![fileManager createFileAtPath:insideWrapperFilename contents:[NSData data] attributes:nil])
                [NSException raise:NSInvalidArgumentException format:@"Unable to create backup file at %@", fileName];
        }
        
        return [[OFResourceFork alloc] initWithContentsOfFile:insideWrapperFilename forkType:OFResourceForkType createFork:create];
    } else {
        return [[OFResourceFork alloc] initWithContentsOfFile:fileName forkType:OFResourceForkType createFork:create];
    }    
}

@end
