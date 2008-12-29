// Copyright 1997-2005, 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFBundledClass.h>

#import <OmniFoundation/NSDictionary-OFExtensions.h>
#import <OmniFoundation/NSObject-OFExtensions.h>
#import <OmniFoundation/NSThread-OFExtensions.h>

RCS_ID("$Id$")

@interface OFBundledClass (Private)

+ (void)addImmediateLoadClass:(OFBundledClass *)aClass;

- initWithClassName:(NSString *)aClassName;

- (void)setBundle:(NSBundle *)aBundle;
- (void)addDependencyClassNamed:(NSString *)aClassName;
- (void)addModifyingBundledClass:(OFBundledClass *)aBundledClass;
- (void)addDependencyClassNames:(NSArray *)anArray;
- (void)modifiesClassesNamed:(NSArray *)anArray;

- (void)loadDependencyClasses;
- (void)loadModifierClasses;

- (void)processDescription:(NSDictionary *)description;

@end

@implementation OFBundledClass;

static NSLock *bundleLock;
static NSMutableDictionary *bundledClassRegistry;
static NSString *OFBundledClassDidLoadNotification;
static NSMutableArray *immediateLoadClasses;

#ifndef PRELOAD_ALL_CLASSES
#define PRELOAD_ALL_CLASSES 0
#endif

+ (void)initialize;
{
    OBINITIALIZE;

    bundleLock = [[NSRecursiveLock alloc] init];
    bundledClassRegistry = [[NSMutableDictionary alloc] initWithCapacity:64];
    immediateLoadClasses = [[NSMutableArray alloc] init];
    OFBundledClassDidLoadNotification = [@"OFBundledClassDidLoad" retain];

#if PRELOAD_ALL_CLASSES
    if ([NSThread isMultiThreaded]) {
#ifdef DEBUG
        NSLog(@"Warning: +[%@ %@] called after going multithreaded!", NSStringFromClass(self), NSStringFromSelector(_cmd));
#endif
        [self loadAllClasses];
    } else {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(loadAllClasses) name:NSWillBecomeMultiThreadedNotification object:nil];
    }
#endif
}

static BOOL OFBundledClassDebug = NO;

+ (void)loadAllClasses;
{
    // We've discovered that a lot of OmniWeb's crashes are caused by one thread loading a bundle while another thread is trying to look up a method implementation:  apparently the Objective C runtime is not thread-safe with respect to loading bundles.  As an experiment, we're now preloading all the bundles to see if that makes the application more stable.  Unfortunately, this slows down our launch time, which was already bad enough.
    // We've thought of three alternatives to preloading:
    // 1. Wait until all other threads are idle before loading a bundle.  (Huge disadvantage: if we're downloading a 100MB file, that might pause all the threads for a long time.)
    // 2. Suspend all other threads, and walk their stacks to see if any are in the Objective C runtime.  Once all threads are out of the runtime go ahead and load the bundle, then resume the threads.
    // 3. Try to patch the runtime so it is thread-safe.

    [bundleLock lock];
    @try {
        NSString *aClassName;
        NSEnumerator *classNameEnumerator = [bundledClassRegistry keyEnumerator];
        while ((aClassName = [classNameEnumerator nextObject])) {
            OFBundledClass *bundledClass = [bundledClassRegistry objectForKey:aClassName];
            
            @try {
                [bundledClass loadBundledClass];
            } @catch (NSException *exc) {
                NSLog(@"+[OFBundledClass loadAllClasses]: Exception while loading %@: %@", aClassName, [exc reason]);
            }
        }
    } @catch (NSException *exc) {
        NSLog(@"+[OFBundledClass loadAllClasses]: %@", [exc reason]);
    }
    [bundleLock unlock];
}

+ (Class)classNamed:(NSString *)aClassName;
{
    return [[self bundledClassNamed:aClassName] bundledClass];
}

+ (NSBundle *)bundleForClassNamed:(NSString *)aClassName;
{
    return [[self bundledClassNamed:aClassName] bundle];
}

+ (OFBundledClass *)bundledClassNamed:(NSString *)aClassName;
{
    NSException *raisedException = nil;
    OFBundledClass *bundledClass;

    if (!aClassName || ![aClassName length])
	return nil;

    [bundleLock lock];
    NS_DURING {
        bundledClass = [bundledClassRegistry objectForKey:aClassName];
        if (!bundledClass) {
            bundledClass = [[self alloc] initWithClassName:aClassName];
            if (bundledClass)
                [bundledClassRegistry setObject:bundledClass forKey:aClassName];
        }
    } NS_HANDLER {
        raisedException = localException;
        bundledClass = nil;
    } NS_ENDHANDLER;
    [bundleLock unlock];
    if (raisedException)
        [raisedException raise];
    return bundledClass;
}

+ (OFBundledClass *)createBundledClassWithName:(NSString *)aClassName bundle:(NSBundle *)aBundle description:(NSDictionary *)aDescription;
{
    OFBundledClass *bundledClass;
    
    bundledClass = [self bundledClassNamed:aClassName];
    [bundledClass setBundle:aBundle];
    [bundledClass processDescription:aDescription];

    return bundledClass;
}

+ (NSString *)didLoadNotification;
{
    return OFBundledClassDidLoadNotification;
}

+ (void)processImmediateLoadClasses;
{
    while ([immediateLoadClasses count] > 0) {
        unsigned int classIndex, classCount;
        NSArray *immediateLoadClassesCopy;

        immediateLoadClassesCopy = [[NSArray alloc] initWithArray:immediateLoadClasses];
        [immediateLoadClasses removeAllObjects];
        classCount = [immediateLoadClassesCopy count];
        for (classIndex = 0; classIndex < classCount; classIndex++) {
            OFBundledClass *immediateLoadClass;

            immediateLoadClass = [immediateLoadClassesCopy objectAtIndex:classIndex];
            NS_DURING {
                [immediateLoadClass loadBundledClass];
            } NS_HANDLER {
                NSLog(@"+[OFBundledClass processImmediateLoadClasses]: %@", [localException reason]);
            } NS_ENDHANDLER;
        }
        [immediateLoadClassesCopy release];
    }
}

// OFBundleRegistryTarget informal protocol

+ (void)registerItemName:(NSString *)itemName bundle:(NSBundle *)aBundle description:(NSDictionary *)description;
{
    [self createBundledClassWithName:itemName bundle:aBundle description:description];
}

// Init and dealloc

- (void)dealloc;
{
    [className release];
    [bundle release];
    [dependencyClassNames release];
    [modifyingBundledClasses release];
    [descriptionDictionary release];
    [super dealloc];
}

// Access

- (NSString *)className;
{
    return className;
}

- (Class)bundledClass;
{
    if (!bundleClass)
	[self loadBundledClass];
    return bundleClass;
}

- (NSBundle *)bundle;
{
    Class aClass;

    if (bundle)
	return bundle;
    else if ((aClass = NSClassFromString(className)))
	return [NSBundle bundleForClass:aClass];
    else
	return nil;
}

- (BOOL)isLoaded;
{
    return (loaded || (bundleClass != nil));
}

- (NSDictionary *)descriptionDictionary;
{
    return descriptionDictionary;
}

- (NSArray *)dependencyClassNames;
{
    return dependencyClassNames;
}

- (NSArray *)modifyingBundledClasses;
{
    return modifyingBundledClasses;
}

// Actions

- (void)loadBundledClass;
{
    if (loaded)
	return;

    [NSThread lockMainThread];
    [bundleLock lock];

    if (loaded) {
	[bundleLock unlock];
        [NSThread unlockMainThread];
	return;
    }

    if (OFBundledClassDebug)
        NSLog(@"-[OFBundledClass loadBundledClass], className=%@, bundle=%@", className, bundle);

    NS_DURING {
        [self loadDependencyClasses];

        if (bundle) {
            if (OFBundledClassDebug)
                NSLog(@"Class %@: loading from %@", className, bundle);
#ifdef OW_DISALLOW_DYNAMIC_LOADING
            if (!(bundleClass = NSClassFromString(className))) {
                NSLog(@"Dynamic load disallowed and class not hardlinked!");
                abort();
            }
#else
            bundleClass = [bundle classNamed:className];
            if (!bundleClass) {
                // If the class is in a framework which is linked into the bundle, then -[NSBundle classNamed:] won't find the class, but NSClassFromString() will.
                bundleClass = NSClassFromString(className);
            }
            [[NSNotificationCenter defaultCenter] postNotificationName:OFBundledClassDidLoadNotification object:bundle];
#endif
        } else {
            bundleClass = NSClassFromString(className);
            if (bundleClass) {
                if (OFBundledClassDebug)
                    NSLog(@"Class %@: found", className);
            }
        }

        [self loadModifierClasses];

        if (!bundleClass)
            NSLog(@"OFBundledClass unable to find class named '%@'", className);
        loaded = YES;

    } NS_HANDLER {
        NSLog(@"Error loading %@: %@", bundle, [localException reason]);
    } NS_ENDHANDLER;

    [bundleLock unlock];
    [NSThread unlockMainThread];
}

// Debugging

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *debugDictionary;

    debugDictionary = [super debugDictionary];

    [debugDictionary setObject:className forKey:@"className"];
    if (bundle)
        [debugDictionary setObject:bundle forKey:@"bundle"];
    if (dependencyClassNames)
        [debugDictionary setObject:dependencyClassNames forKey:@"dependencyClassNames"];
    if (modifyingBundledClasses)
        [debugDictionary setObject:modifyingBundledClasses forKey:@"modifyingBundledClasses"];

    return debugDictionary;
}

- (NSString *)shortDescription;
{
    return [@"OFBundledClass " stringByAppendingString:className];
}

@end

@implementation OFBundledClass (Private)

+ (void)addImmediateLoadClass:(OFBundledClass *)aClass;
{
    [immediateLoadClasses addObject:aClass];
}

- initWithClassName:(NSString *)aClassName;
{
    if (![super init])
	return nil;

    className = [aClassName copy];
    bundle = nil;
    dependencyClassNames = [[NSMutableArray alloc] init];
    modifyingBundledClasses = [[NSMutableArray alloc] init];

    bundleClass = NSClassFromString(aClassName);
    loaded = bundleClass != nil;
    
    return self;
}

//

- (void)setBundle:(NSBundle *)aBundle;
{
    if (bundle == aBundle)
	return;
    [bundle release];
    bundle = [aBundle retain];
}

- (void)addDependencyClassNamed:(NSString *)aClassName;
{
    [dependencyClassNames addObject:aClassName];
}

- (void)addModifyingBundledClass:(OFBundledClass *)aBundledClass;
{
    [modifyingBundledClasses addObject:aBundledClass];
    if (loaded)
        [aBundledClass loadBundledClass];
}

- (void)addDependencyClassNames:(NSArray *)anArray;
{
    NSEnumerator *enumerator;
    NSString *dependency;
    
    enumerator = [anArray objectEnumerator];
    while ((dependency = [enumerator nextObject]))
	[self addDependencyClassNamed:dependency];
}

- (void)modifiesClassesNamed:(NSArray *)anArray;
{
    NSEnumerator *enumerator;
    NSString *modifiedClass;
    
    enumerator = [anArray objectEnumerator];
    while ((modifiedClass = [enumerator nextObject])) {
	OFBundledClass *bundledClass;

	bundledClass = [[self class] bundledClassNamed:modifiedClass];
	[bundledClass addModifyingBundledClass:self];
    }
}

//

- (void)loadDependencyClasses;
{
    NSEnumerator *enumerator;
    NSString *aClassName;

    if ([dependencyClassNames count] == 0)
	return;

    if (OFBundledClassDebug)
	NSLog(@"Class %@: loading dependencies", className);

    enumerator = [dependencyClassNames objectEnumerator];
    while ((aClassName = [enumerator nextObject]))
	[[[self class] bundledClassNamed:aClassName] loadBundledClass];
}

- (void)loadModifierClasses;
{
    NSEnumerator *enumerator;
    OFBundledClass *aClass;

    if ([modifyingBundledClasses count] == 0)
	return;

    if (OFBundledClassDebug)
	NSLog(@"Class %@: loading modifiers", className);
    
    enumerator = [modifyingBundledClasses objectEnumerator];
    while ((aClass = [enumerator nextObject]))
        [aClass loadBundledClass];
}

//

- (void)processDescription:(NSDictionary *)description;
{
    BOOL immediateLoad;

    OBPRECONDITION(descriptionDictionary == nil); // -processDescription: shouldn't be called more than once for a given class
    // If the above assumption is false, then we'll need to figure out how to merge descriptionDictionaries. Right now nobody actually calls the -descriptionDictionary method so we might be able to sidestep the issue entirely by eliminating that ivar.
    [descriptionDictionary release];
    descriptionDictionary = [description copy];

    [self addDependencyClassNames:[descriptionDictionary objectForKey:@"dependsOnClasses"]];
    [self modifiesClassesNamed:[descriptionDictionary objectForKey:@"modifiesClasses"]];
    immediateLoad = [descriptionDictionary boolForKey:@"immediateLoad"];
    if (immediateLoad)
        [isa addImmediateLoadClass:self];
}

@end
