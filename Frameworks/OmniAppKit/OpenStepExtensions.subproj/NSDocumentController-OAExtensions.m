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

#if defined(MAC_OS_X_VERSION_10_4) && MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_4
static id (*originalOpenDocumentIMP)(id, SEL, NSURL *, BOOL, NSError **);
#else
static id (*originalOpenDocumentIMP)(id, SEL, NSString *, BOOL);
#endif

#if defined(OMNI_ASSERTIONS_ON) && defined(MAC_OS_X_VERSION_10_4) && (MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_4)

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
#if defined(MAC_OS_X_VERSION_10_4) && MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_4
    originalOpenDocumentIMP = (typeof(originalOpenDocumentIMP))OBReplaceMethodImplementationWithSelector(self, @selector(openDocumentWithContentsOfURL:display:error:), @selector(_replacement_openDocumentWithContentsOfURL:display:error:));
#else
    originalOpenDocumentIMP = (typeof(originalOpenDocumentIMP))OBReplaceMethodImplementationWithSelector(self, @selector(openDocumentWithContentsOfFile:display:), @selector(OAOpenDocumentWithContentsOfFile:display:));
#endif
    
#if defined(OMNI_ASSERTIONS_ON) && defined(MAC_OS_X_VERSION_10_4) && (MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_4)
    // Check that no deprecated APIs are implemented in subclasses of NSDocument if we are build for 10.4 or later.  NSDocument changes its behavior if you *implement* the deprecated APIs and we want to stay on the mainstream path.
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

#if defined(MAC_OS_X_VERSION_10_4) && MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_4
- (id)_replacement_openDocumentWithContentsOfURL:(NSURL *)absoluteURL display:(BOOL)displayDocument error:(NSError **)outError;
{
    NSDocument *document = originalOpenDocumentIMP(self, _cmd, absoluteURL, displayDocument, outError);
    if ([[NSFileManager defaultManager] fileIsStationeryPad:[absoluteURL path]])
        [document setFileURL:nil];
    return document;
}
#else
- (id)OAOpenDocumentWithContentsOfFile:(NSString *)fileName display:(BOOL)flag
{
    NSDocument *document;
    
    document = originalOpenDocumentIMP(self, _cmd, fileName, flag);
    if ([[NSFileManager defaultManager] fileIsStationeryPad:fileName])
        [document setFileName:nil];
    return document;
}
#endif

@end
