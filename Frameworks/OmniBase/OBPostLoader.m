// Copyright 1997-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniBase/OBPostLoader.h>

#import <OmniBase/OBUtilities.h>
#import <OmniBase/assertions.h>

#import <Foundation/Foundation.h>
#import <OmniBase/rcsid.h>
#import <OmniBase/objc.h>

RCS_ID("$Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniBase/OBPostLoader.m 98770 2008-03-17 22:25:33Z kc $")

static NSRecursiveLock *lock = nil;
static NSHashTable *calledImplementations = NULL;
static BOOL isMultiThreaded = NO;
static BOOL isSendingBecomingMultiThreaded = NO;

#if !defined(MAC_OS_X_VERSION_10_5) || MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_5
extern void _objc_resolve_categories_for_class(struct objc_class *cls);
#endif

@interface OBPostLoader (PrivateAPI)
+ (BOOL)_processSelector:(SEL)selectorToCall inClass:(Class)aClass initialize:(BOOL)shouldInitialize;
+ (void)_becomingMultiThreaded:(NSNotification *)note;
@end

//#define POSTLOADER_DEBUG

@implementation OBPostLoader
/*"
OBPostLoader provides the functionality that you might expect to get from implementing a +load method.  Unfortunately, some implementations of OpenStep have bugs with their implementation of +load.  Rather than attempt to use +load, OBPostLoader provides similar functionality that actually works.  Early in your program startup, you should call +processClasses.  This will go through the ObjC runtime and invoke all of the +performPosing and +didLoad methods.  Each class may have multiple implementations of each of theses selectors -- all will be called.

OBPostLoader listens for bundle loaded notifications and will automatically reinvoke +processClasses to perform any newly loaded methods.

OBPostLoader also listens for NSBecomingMultiThreaded and will invoke every implementation of +becomingMultiThreaded.
"*/

+ (void)initialize;
{
    OBINITIALIZE;

    // We used to allocate this only when going multi-threaded, but this can happen while we are in the middle of processing a selector (that is, a +didLoad can fork a thread).  In this case we'd end up 'locking' nil when starting the +didLoad processing and then unlocking a non-nil lock that we didn't own.  We could create the lock in +_becomingMultiThreaded: _and_ lock it if we are in the middle of +processSelector:initialize:, but that's just getting too complicated.
    lock = [[NSRecursiveLock alloc] init];
    
    // Set this up before we call any method implementations
    calledImplementations = NSCreateHashTable(NSNonOwnedPointerHashCallBacks, 0);

    // If any other bundles get loaded, make sure that we process them too.
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(bundleDidLoad:) name:NSBundleDidLoadNotification object:nil];

    // Register for the multi-threadedness here so that most classes won't have to
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_becomingMultiThreaded:) name:NSWillBecomeMultiThreadedNotification object:nil];
}

/*"
Searches the ObjC runtime for particular methods and invokes them.  Each implementation will be invoked exactly once.  Currently, there is no guarantee on the order that these messages will occur.  This should be called as the first line of main().  Once this has been called at the beginning of main, it will automatically be called each time a bundle is loaded (view the NSBundle loading notification).

This method makes several passes, each time invoking a different selector.  On the first pass, +performPosing implementations are invoked, allowing modifictions to the ObjC runtime to happen early (before +initialize).  Then, +didLoad implementations are processed.
"*/
+ (void)processClasses;
{
    [self processSelector:@selector(performPosing) initialize:NO];
    [self processSelector:@selector(didLoad) initialize:YES];

    // Handle the case that this doesn't get called until after we've gone multi-threaded
    if ([NSThread isMultiThreaded])
        [self _becomingMultiThreaded:nil];
}

/*"
This method does the work of looping over the runtime searching for implementations of selectorToCall and invoking them when they haven't already been invoked.
"*/
+ (void)processSelector:(SEL)selectorToCall initialize:(BOOL)shouldInitialize;
{
    BOOL didInvokeSomething = YES;

    [lock lock];

    // We will collect the necessary information from the runtime before calling any method implementations.  This is necessary since any once of the implementations that we call could actually modify the ObjC runtime.  It could add classes or methods.

    while (didInvokeSomething) {
        int classCount = 0, newClassCount;
        Class *classes = NULL;

        // Start out claiming to have invoked nothing.  If this doesn't get reset to YES below, we're done.
        didInvokeSomething = NO;

        // Get the class list
        newClassCount = objc_getClassList(NULL, 0);
        while (classCount < newClassCount) {
            classCount = newClassCount;
            classes = realloc(classes, sizeof(Class) * classCount);
            newClassCount = objc_getClassList(classes, classCount);
        }

        // Now, use the class list; if NULL, there are no classes
        if (classes != NULL) {
            int classIndex;
            
            // Loop over the gathered classes and process the requested implementations
            for (classIndex = 0; classIndex < classCount; classIndex++) {
                Class aClass = classes[classIndex];

#if !defined(MAC_OS_X_VERSION_10_5) || MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_5
                // TJW: After some investiation, I tracked down the ObjC runtime bug that Steve was running up against in OmniOutliner when he needed to add this (I also hit it in OmniGraffle when trying to get rid of this line).  The bug is essentially that categories don't get registered when you pose before +initialize.  Logged as Radar #3319132.
                _objc_resolve_categories_for_class(aClass);
#endif
                
                if ([self _processSelector:selectorToCall inClass:aClass initialize:shouldInitialize])
                    didInvokeSomething = YES;
            }
        }

        // Free the class list
        free(classes);
    }

    [lock unlock];
}

+ (void) bundleDidLoad: (NSNotification *) notification;
{
    [self processClasses];
}

/*"
This can be used instead of +[NSThread isMultiThreaded].  The difference is that this method doesn't return YES until after going multi-threaded, whereas the NSThread version starts returning YES before the NSWillBecomeMultiThreadedNotification is sent.
"*/
+ (BOOL)isMultiThreaded;
{
    return isMultiThreaded;
}

@end



@implementation OBPostLoader (PrivateAPI)

+ (BOOL)_processSelector:(SEL) selectorToCall inClass:(Class)aClass initialize:(BOOL)shouldInitialize;
{
    Class metaClass = object_getClass(aClass); // we are looking at class methods

    unsigned int impSize = 256;
    unsigned int impIndex, impCount = 0;
    IMP *imps = NSZoneMalloc(NULL, sizeof(IMP) * impSize);
    

#if defined(POSTLOADER_DEBUG)
    //fprintf(stderr, "Checking for implementations of +[%s %s]\n", class_getName(aClass), sel_getName(selectorToCall));
#endif
    // Gather all the method implementations of interest on this class before invoking any of them.  This is necessary since they might modify the ObjC runtime.
    unsigned int methodIndex, methodCount;
    Method *methodList = class_copyMethodList(metaClass, &methodCount);
    for (methodIndex = 0; methodIndex < methodCount; methodIndex++) {
        Method m = methodList[methodIndex];
        
        if (method_getName(m) == selectorToCall) {
            IMP imp = method_getImplementation(m);
            
            // Store this implementation if it hasn't already been called
            if (!NSHashGet(calledImplementations, imp)) {
                if (impCount >= impSize) {
                    impSize *= 2;
                    imps = NSZoneRealloc(NULL, imps, sizeof(IMP) * impSize);
                }
                
                imps[impCount] = imp;
                impCount++;
                NSHashInsertKnownAbsent(calledImplementations, imp);
                
#if defined(POSTLOADER_DEBUG)
                fprintf(stderr, "Recording +[%s %s] (%p)\n", class_getName(aClass), sel_getName(selectorToCall), (void *)imp);
#endif
            }
        }
    }
    if (methodList)
        free(methodList);
    
    if (impCount) {
        if (shouldInitialize) {
            NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
#if defined(POSTLOADER_DEBUG)
            fprintf(stderr, "Initializing %s\n", class_getName(aClass));
#endif
            // try to make sure +initialize gets called
            if (class_getClassMethod(aClass, @selector(class)))
                [aClass class];
            else if (class_getClassMethod(aClass, @selector(initialize)))
                // Avoid a compiler warning
                objc_msgSend(aClass, @selector(initialize));
            [pool release];
        }

        for (impIndex = 0; impIndex < impCount; impIndex++) {
            NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
#if defined(POSTLOADER_DEBUG)
            fprintf(stderr, "Calling (%p) ... ", (void *)imps[impIndex]);
#endif
            // We now call this within an exception handler because twice now we've released versions of OmniWeb where something would raise within +didLoad on certain configurations (not configurations we had available for testing) and weren't getting caught, resulting in an application that won't launch on those configurations.  We could insist that everyone do their own exception handling in +didLoad, but if we're going to potentially crash because a +didLoad failed I'd rather crash later than now.  (Especially since the exceptions in question were perfectly harmless.)
            @try {
                // We discovered that we'll crash if we use aClass after it has posed as another class.  So, we go look up the imposter class that resulted from the +poseAs: and use it instead.
                Class imposterClass = objc_getClass(class_getName(metaClass));
                if (imposterClass != Nil)
                    aClass = imposterClass;
                
                imps[impIndex](aClass, selectorToCall);
            } @catch (NSException *exc) {
                fprintf(stderr, "Exception raised by +[%s %s]: %s\n", class_getName(aClass), sel_getName(selectorToCall), [[exc reason] UTF8String]);
            }
#if defined(POSTLOADER_DEBUG)
            fprintf(stderr, "done\n");
#endif
            [pool release];
        }
    }

    NSZoneFree(NULL, imps);

    return impCount != 0;
}


+ (void)_becomingMultiThreaded:(NSNotification *)note;
{
    if (isSendingBecomingMultiThreaded)
        return;

    isSendingBecomingMultiThreaded = YES;

    @try {
        [self processSelector:@selector(becomingMultiThreaded) initialize:NO];
    } @catch (NSException *exc) {
        NSLog(@"Ignoring exception raised while sending -becomingMultiThreaded.  %@", exc);
    }

    isMultiThreaded = YES;
    isSendingBecomingMultiThreaded = NO;
}

@end
