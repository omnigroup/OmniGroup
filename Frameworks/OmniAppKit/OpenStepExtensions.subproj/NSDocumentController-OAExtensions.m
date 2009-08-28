// Copyright 2001-2006 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "NSDocumentController-OAExtensions.h"
#import <OmniFoundation/OmniFoundation.h>
#import <OmniBase/OmniBase.h>
#import <Carbon/Carbon.h>
#import <AppKit/AppKit.h>
#import <CoreFoundation/CoreFoundation.h>

RCS_ID("$Id$")

@implementation NSDocumentController (OAExtensions)

static id (*originalOpenDocumentIMP)(id, SEL, NSURL *, BOOL, NSError **);

#ifdef OMNI_ASSERTIONS_ON
static void checkDeprecatedSelector(Class subclass, Class klass, SEL sel)
{
    Class implementingClass = OBClassImplementingMethod(subclass, sel);
    OBASSERT(implementingClass); // misspelled selector?
    
    if (implementingClass && klass != implementingClass)
	NSLog(@"%@ is implementing %@, but this is deprecated!", NSStringFromClass(subclass), NSStringFromSelector(sel));
}
#define CHECK_DOCUMENT_API(sel) checkDeprecatedSelector(aClass, self, sel)
#endif

+ (void)didLoad;
{
    originalOpenDocumentIMP = (typeof(originalOpenDocumentIMP))OBReplaceMethodImplementationWithSelector(self, @selector(openDocumentWithContentsOfURL:display:error:), @selector(_replacement_openDocumentWithContentsOfURL:display:error:));
    
#ifdef OMNI_ASSERTIONS_ON
    // Check that no deprecated APIs are implemented in subclasses of NSDocumentController.  NSDocumentController changes its behavior if you *implement* the deprecated APIs and we want to stay on the mainstream path.
    
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
		CHECK_DOCUMENT_API(@selector(documentForFileName:));
		CHECK_DOCUMENT_API(@selector(fileNamesFromRunningOpenPanel));
		CHECK_DOCUMENT_API(@selector(makeDocumentWithContentsOfFile:ofType:));
		CHECK_DOCUMENT_API(@selector(makeDocumentWithContentsOfURL:ofType:));
		CHECK_DOCUMENT_API(@selector(makeUntitledDocumentOfType:));
		CHECK_DOCUMENT_API(@selector(openDocumentWithContentsOfFile:display:));
		CHECK_DOCUMENT_API(@selector(openDocumentWithContentsOfURL:display:));
		CHECK_DOCUMENT_API(@selector(openUntitledDocumentOfType:display:));
		CHECK_DOCUMENT_API(@selector(setShouldCreateUI:));
		CHECK_DOCUMENT_API(@selector(shouldCreateUI));
		CHECK_DOCUMENT_API(@selector(validateMenuItem:)); // use -validateUserInterfaceItem: instead?  Not listed as deprecated in the header, but its in the 'NSDeprecated' category
	    }
	}
    }
#endif
}

- (id)_replacement_openDocumentWithContentsOfURL:(NSURL *)absoluteURL display:(BOOL)displayDocument error:(NSError **)outError;
{
    NSDocument *document = originalOpenDocumentIMP(self, _cmd, absoluteURL, displayDocument, outError);
    if ([[NSFileManager defaultManager] fileIsStationeryPad:[absoluteURL path]])
        [document setFileURL:nil];
    return document;
}

@end
