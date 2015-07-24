// Copyright 2003-2015 Omni Development, Inc. All rights reserved.
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
	classes = reallocf(classes, sizeof(Class) * classCount);
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
        
        free(classes);
    }
}
#endif

- (NSArray *)orderedWindowControllers;
{
    NSArray *orderedWindows = [NSWindow windowsInZOrder]; // Doesn't include miniaturized or ordered out windows
    NSArray *loadedWindowControllers = [[self windowControllers] objectsSatisfyingCondition:@selector(isWindowLoaded)]; // don't provoke loading of windows we don't need
    
    NSMutableArray *loadedWindows = [[[loadedWindowControllers valueForKey:@"window"] mutableCopy] autorelease];
    [loadedWindows sortBasedOnOrderInArray:orderedWindows identical:YES unknownAtFront:NO];
    
    // Actually want the window controllers
    return [loadedWindows valueForKey:@"windowController"];
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
