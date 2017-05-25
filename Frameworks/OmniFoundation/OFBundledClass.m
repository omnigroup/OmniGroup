// Copyright 1997-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFBundledClass.h>

#import <OmniFoundation/NSDictionary-OFExtensions.h>
#import <OmniFoundation/NSObject-OFExtensions.h>

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

static NSRecursiveLock *bundleLock;
static NSMutableDictionary *bundledClassRegistry;
static NSString *OFBundledClassDidLoadNotification;
static NSMutableArray *immediateLoadClasses;

+ (void)initialize;
{
    OBINITIALIZE;

    bundleLock = [[NSRecursiveLock alloc] init];
    bundledClassRegistry = [[NSMutableDictionary alloc] initWithCapacity:64];
    immediateLoadClasses = [[NSMutableArray alloc] init];
    OFBundledClassDidLoadNotification = [@"OFBundledClassDidLoad" retain];
}

static BOOL OFBundledClassDebug = NO;

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
    if ([NSString isEmptyString:aClassName])
        return nil;

    [bundleLock lock];
    @try {
        OFBundledClass *bundledClass = [bundledClassRegistry objectForKey:aClassName];
        if (!bundledClass) {
            bundledClass = [[self alloc] initWithClassName:aClassName];
            if (bundledClass)
                [bundledClassRegistry setObject:bundledClass forKey:aClassName];
        }
        return bundledClass;
    } @finally {
        [bundleLock unlock];
    }
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
        NSArray *immediateLoadClassesCopy = [[NSArray alloc] initWithArray:immediateLoadClasses];
        [immediateLoadClasses removeAllObjects];
        
        for (OFBundledClass *immediateLoadClass in immediateLoadClassesCopy) {
            @try {
                [immediateLoadClass loadBundledClass];
            } @catch (NSException *exc) {
                NSLog(@"+[OFBundledClass processImmediateLoadClasses]: %@", [exc reason]);
            }
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

    OFMainThreadPerformBlockSynchronously(^{
        [bundleLock lock];

        if (loaded) {
            [bundleLock unlock];
            return;
        }

        if (OFBundledClassDebug)
            NSLog(@"-[OFBundledClass loadBundledClass], className=%@, bundle=%@", className, bundle);

        @try {
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
        } @catch (NSException *exc) {
            NSLog(@"Error loading %@: %@", bundle, [exc reason]);
        }
        
        [bundleLock unlock];
    });
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
    if (!(self = [super init]))
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
        [[self class] addImmediateLoadClass:self];
}

@end
