// Copyright 1997-2005, 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFBundleRegistry.h>

// The iPhone can't dynamically load code (or even link frameworks), so a lot of this class does nothing on that platform.
#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
#define DYNAMIC_BUNDLE_LOADING
#endif

#import <OmniFoundation/NSObject-OFExtensions.h>
#import <OmniFoundation/NSMutableSet-OFExtensions.h>
#ifdef DYNAMIC_BUNDLE_LOADING
#import <OmniFoundation/NSString-OFExtensions.h>
#import <OmniFoundation/OFBundledClass.h>
#endif

RCS_ID("$Id$")

/* Bundle descriptions are currently NSMutableDictionaries with the following keys:

    path          --- the path to the bundle, if known
    bundle        --- the NSBundle, if any
    invalid       --- if the bundle isn't valid, indicates why (may be "disabled", a nonlocalized string)
    loaded        --- indicates whether the bundle is loaded (maybe)
    preloaded     --- indicates that bundle was loaded at startup time
    text          --- string containing human-readable information about the bundle
    needsRestart  --- indicates that this bundle has been en/disabled since launch (so you might need to restart the app in order to use it)

It may be better to make an OFBundleDescription class eventually.

NB also, if this dictionary changes, the OmniBundlePreferences bundle (in OmniComponents/Other) should be updated, as well as the NetscapePluginSupport bundle.
*/
    

@interface OFBundleRegistry (Private)
+ (void)readConfigDictionary;
#ifdef DYNAMIC_BUNDLE_LOADING
+ (NSArray *)standardPath;
+ (NSArray *)newBundlesFromStandardPath;
+ (NSArray *)bundlesInDirectory:(NSString *)directoryPath ignoringPaths:(NSSet *)seen;
+ (void)recordBundleLoading:(NSNotification *)note;
+ (void)_defaultsDidChange:(NSNotification *)note;
#endif
+ (NSArray *)linkedBundles;
+ (void)registerDictionary:(NSDictionary *)registrationDictionary forBundle:(NSDictionary *)bundleDescription;
+ (void)registerBundles:(NSArray *)bundleDescriptions;
+ (void)registerAdditionalRegistrations;
+ (BOOL)haveSoftwareVersionsInDictionary:(NSDictionary *)requiredVersionsDictionary;
@end

static NSMutableSet *registeredBundleNames;
static NSMutableDictionary *softwareVersionDictionary;
static NSMutableArray *knownBundles;
static NSMutableDictionary *additionalBundleDescriptions;
#ifdef DYNAMIC_BUNDLE_LOADING
static NSArray *oldDisabledBundleNames;
#endif

@implementation OFBundleRegistry

+ (void)initialize;
{
    OBINITIALIZE;

    registeredBundleNames = [[NSMutableSet alloc] init];
    softwareVersionDictionary = [[NSMutableDictionary alloc] init];
    knownBundles = [[NSMutableArray alloc] init];
    additionalBundleDescriptions = nil;  // Lazily create this one since not all apps use it
}

+ (void)didLoad;
{
    [self registerKnownBundles];
}

+ (void)registerKnownBundles;
{
    [self readConfigDictionary];
    [self registerBundles:[self linkedBundles]];
#ifdef DYNAMIC_BUNDLE_LOADING
    [self registerBundles:[self newBundlesFromStandardPath]];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(recordBundleLoading:) name:NSBundleDidLoadNotification object:nil]; // Keep track of future bundle loads
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_defaultsDidChange:) name:NSUserDefaultsDidChangeNotification object:nil]; // Keep track of changes to defaults
#endif
    [self registerAdditionalRegistrations];
#ifdef DYNAMIC_BUNDLE_LOADING
    [OFBundledClass processImmediateLoadClasses];
#endif
}

+ (NSDictionary *)softwareVersionDictionary;
{
    return softwareVersionDictionary;
}

+ (NSArray *)knownBundles;
{
    NSMutableArray *allBundleDescriptions;
    NSEnumerator *foreignBundleEnumerator;
    NSArray *foreignBundleDescriptions;
    
    // If there aren't any additional registrations, just return our known bundles
    if (!additionalBundleDescriptions || ![additionalBundleDescriptions count])
        return knownBundles;

    allBundleDescriptions = [[NSMutableArray alloc] initWithArray:knownBundles];
    [allBundleDescriptions autorelease];
    foreignBundleEnumerator = [additionalBundleDescriptions objectEnumerator];
    while( (foreignBundleDescriptions = [foreignBundleEnumerator nextObject]) != nil)
        [allBundleDescriptions addObjectsFromArray:foreignBundleDescriptions];

    return allBundleDescriptions;
}

#if 0
   // This should be changed to use a notification or some other method so that bundle-loaders other than us can catch it and re-scan for bundles when requested 
+ (void)lookForBundles
{
    [self registerBundles:[self newBundlesFromStandardPath]];
    [OFBundledClass processImmediateLoadClasses];
}
#endif

+ (void)noteAdditionalBundles:(NSArray *)additionalBundles owner:bundleOwner
{
    BOOL changedSomething;
    
    if (additionalBundles && ![additionalBundles count])
        additionalBundles = nil;

    changedSomething = NO;

    if (!additionalBundles) {
        if (additionalBundleDescriptions != nil &&
            [additionalBundleDescriptions objectForKey:bundleOwner] != nil) {
            changedSomething = YES;
            [additionalBundleDescriptions removeObjectForKey:bundleOwner];
        }
    } else {
        if (additionalBundleDescriptions == nil) {
            additionalBundleDescriptions = [[NSMutableDictionary alloc] init];
        }
    
        // Assume that the bundle registrar is only sending us this message if something actually changed in its registry.
        changedSomething = YES;
        [additionalBundleDescriptions setObject:additionalBundles forKey:bundleOwner];
    }

    if (changedSomething) {
        [[NSNotificationCenter defaultCenter] postNotificationName:OFBundleRegistryChangedNotificationName object:nil];
    }
}

@end

@implementation OFBundleRegistry (Private)

static NSString * const OFBundleRegistryConfig = @"OFBundleRegistryConfig";
static NSString * const OFRequiredSoftwareVersions = @"OFRequiredSoftwareVersions";
static NSString * const OFRegistrations = @"OFRegistrations";

#ifdef DYNAMIC_BUNDLE_LOADING
static NSString * const OFBundleRegistryConfigSearchPaths = @"SearchPaths";
static NSString * const OFBundleRegistryConfigAppWrapperPath = @"AppWrapper";
static NSString * const OFBundleRegistryConfigBundleExtensions = @"BundleExtensions";
#endif
static NSString * const OFBundleRegistryConfigAdditionalRegistrations = @"AdditionalRegistrations";
static NSString * const OFBundleRegistryConfigLogBundleRegistration = @"LogBundleRegistration";

#ifdef DYNAMIC_BUNDLE_LOADING
NSString * const OFBundleRegistryDisabledBundlesDefaultsKey = @"DisabledBundles";
#endif
NSString * const OFBundleRegistryChangedNotificationName = @"OFBundleRegistry changed";

static NSDictionary *configDictionary = nil;
static BOOL OFBundleRegistryDebug = NO;

+ (void)readConfigDictionary;
{
    NSString *logBundleRegistration;

    configDictionary = [[[[NSBundle mainBundle] infoDictionary] objectForKey:OFBundleRegistryConfig] retain];
    if (!configDictionary)
        configDictionary = [[NSDictionary alloc] init];

    logBundleRegistration = [configDictionary objectForKey:OFBundleRegistryConfigLogBundleRegistration];
    if (logBundleRegistration != nil && [logBundleRegistration boolValue] == YES)
        OFBundleRegistryDebug = YES;

#ifdef DYNAMIC_BUNDLE_LOADING
    oldDisabledBundleNames = [[[NSUserDefaults standardUserDefaults] arrayForKey:OFBundleRegistryDisabledBundlesDefaultsKey] copy];
#endif
}

#ifdef DYNAMIC_BUNDLE_LOADING

+ (NSArray *)standardPath;
{
    static NSArray *standardPath = nil;
    NSArray *configPathArray;
    NSString *mainBundlePath, *mainBundleResourcesPath;

    if (standardPath)
        return standardPath;

    // Bundles are stored in the Resources directory of the applications, but tools might have bundles in the same directory as their binary.  Use both paths.
    mainBundlePath = [[NSBundle mainBundle] bundlePath];
    mainBundleResourcesPath = [[mainBundlePath stringByAppendingPathComponent:@"Contents"] stringByAppendingPathComponent:@"PlugIns"];

    // Search for the config path array in defaults, then in the app wrapper's configuration dictionary.  (In gdb, we set the search path on the command line where it will appear in the NSArgumentDomain, overriding the app wrapper's configuration.)
    if ((configPathArray = [[NSUserDefaults standardUserDefaults] arrayForKey:OFBundleRegistryConfigSearchPaths]) ||
        (configPathArray = [configDictionary objectForKey:OFBundleRegistryConfigSearchPaths])) {
        unsigned int pathIndex, pathCount;
        NSMutableArray *newPath;

        pathCount = [configPathArray count];

        // The capacity of the newPath array is pathCount + 1 because AppWrapper expands to two entries.
        newPath = [[NSMutableArray alloc] initWithCapacity:pathCount + 1];
        for (pathIndex = 0; pathIndex < pathCount; pathIndex++) {
            NSString *path;

            path = [configPathArray objectAtIndex:pathIndex];
            if ([path isEqualToString:OFBundleRegistryConfigAppWrapperPath]) {
                [newPath addObject:mainBundleResourcesPath];
                [newPath addObject:mainBundlePath];
#ifdef DEBUG
                [newPath addObject:[mainBundlePath stringByDeletingLastPathComponent]];
#endif
            } else
                [newPath addObject:path];
        }

        standardPath = [newPath copy];
        [newPath release];
    } else {
        // standardPath = ("~/Library/Components", "/Library/Components", "/Network/Library/Components", "/System/Library/Components", "AppWrapper");
        standardPath = [[NSArray alloc] initWithObjects:[NSString pathWithComponents:
            // User's library directory
            [NSArray arrayWithObjects:NSHomeDirectory(), @"Library", @"Components", nil]],

            // Standard Mac OS X library directories
            [NSString pathWithComponents:[NSArray arrayWithObjects:@"/", @"Library", @"Components", nil]],
            [NSString pathWithComponents:[NSArray arrayWithObjects:@"/", @"Network", @"Library", @"Components", nil]],
            [NSString pathWithComponents:[NSArray arrayWithObjects:@"/", @"System", @"Library", @"Components", nil]],

            // App wrapper
            mainBundleResourcesPath,
            mainBundlePath,

            nil];
    }

    return standardPath;
}

#endif

+ (NSArray *)linkedBundles
{
    NSMutableArray *linkedBundles = [NSMutableArray array];

#ifdef DYNAMIC_BUNDLE_LOADING
    // The frameworks and main bundle are already loaded, so we should register them first.
    NSEnumerator *frameworkEnumerator = [[NSBundle allFrameworks] objectEnumerator];
    NSBundle *framework;
    while ((framework = [frameworkEnumerator nextObject])) {
        [linkedBundles addObject:[NSMutableDictionary dictionaryWithObjectsAndKeys:framework, @"bundle", @"YES", @"loaded", @"YES", @"preloaded", nil]];
    }
    
    // Add in any dynamically loaded bundles that are already present.  In particular, unit test bundles might have registration dicitionaries for their test cases.
    NSEnumerator *bundleEnumerator = [[NSBundle allBundles] objectEnumerator];
    NSBundle *bundle;
    while ((bundle = [bundleEnumerator nextObject])) {
        OBASSERT(![[NSBundle allFrameworks] containsObject:bundle]); // should only contain the main bundle and dynamically loaded bundles.
        if (bundle != [NSBundle mainBundle]) // main bundle done below
            [linkedBundles addObject:[NSMutableDictionary dictionaryWithObjectsAndKeys:bundle, @"bundle", @"YES", @"loaded", @"YES", @"preloaded", nil]];
    }
#endif

    // And, of course, there's the application bundle itself.
    [linkedBundles addObject:[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSBundle mainBundle], @"bundle", @"YES", @"loaded", @"YES", @"preloaded", nil]];

    return linkedBundles;
}

#ifdef DYNAMIC_BUNDLE_LOADING

// Returns an NSArray of bundle descriptions
+ (NSArray *)newBundlesFromStandardPath;
{
    NSMutableArray *bundlesFromStandardPath;
    NSArray *standardPath;
    NSMutableSet *seenPaths;
    unsigned int pathIndex, pathCount;

    // Make a note of paths we've already examined so we can skip them this time
    pathCount = [knownBundles count];
    seenPaths = [[NSMutableSet alloc] initWithCapacity:pathCount];
    for(pathIndex = 0; pathIndex < pathCount; pathIndex ++) {
        NSString *aPath;
        
        aPath = [[knownBundles objectAtIndex:pathIndex] objectForKey:@"path"];
        if (aPath)
            [seenPaths addObject:aPath];
        aPath = [[[knownBundles objectAtIndex:pathIndex] objectForKey:@"path"] bundlePath];
        if (aPath)
            [seenPaths addObject:aPath];
    }

    NSDictionary *environmentDictionary = [[NSProcessInfo processInfo] environment];
    bundlesFromStandardPath = [[NSMutableArray alloc] init];

    // Now find all the bundles from the standard paths
    standardPath = [self standardPath];
    pathCount = [standardPath count];
    for (pathIndex = 0; pathIndex < pathCount; pathIndex++) {
        NSString *pathElement;

        pathElement = [[standardPath objectAtIndex:pathIndex] stringByReplacingKeysInDictionary:environmentDictionary startingDelimiter:@"$(" endingDelimiter:@")"];
        NS_DURING {
            [bundlesFromStandardPath addObjectsFromArray:[self bundlesInDirectory:pathElement ignoringPaths:seenPaths]];
        } NS_HANDLER {
            NSLog(@"+[OFBundleRegistry bundlesFromStandardPath]: %@", [localException reason]);
        } NS_ENDHANDLER;
    }

    [seenPaths release];

    return [bundlesFromStandardPath autorelease];
}

// Invoked whenever NSBundle loads something
+ (void)recordBundleLoading:(NSNotification *)note
{
    int knownBundlesCount, knownBundlesIndex;
    NSBundle *theBundle = [note object];
    NSMutableDictionary *newlyLoadedBundleDescription;
#warning thread-safety ?
//    NSLog(@"Loded %@, info: %@", theBundle, [[note userInfo] description]);

    newlyLoadedBundleDescription = nil;

    knownBundlesCount = [knownBundles count];
    for(knownBundlesIndex = 0; knownBundlesIndex < knownBundlesCount; knownBundlesIndex ++) {
        NSMutableDictionary *aBundleDict;
        NSBundle *aBundle;
        aBundleDict = [knownBundles objectAtIndex:knownBundlesIndex];
        aBundle = [aBundleDict objectForKey:@"bundle"];
        if (aBundle == theBundle) {
            newlyLoadedBundleDescription = aBundleDict;
            break;
        }
    }

    if (newlyLoadedBundleDescription == nil) {
        // somebody loaded a bundle we didn't already know about
        newlyLoadedBundleDescription = [NSMutableDictionary dictionaryWithObjectsAndKeys:theBundle, @"bundle", nil];
        [knownBundles addObject:newlyLoadedBundleDescription];
    }

    [newlyLoadedBundleDescription setObject:@"YES" forKey:@"loaded"];

    [[NSNotificationCenter defaultCenter] postNotificationName:OFBundleRegistryChangedNotificationName object:nil];
}

// Invoked when the defaults change
// The only reason we watch this is to update our disabled bundles list, so we don't need to do it if we don't have dynamically loaded bundles.
+ (void)_defaultsDidChange:(NSNotification *)note
{
    BOOL changedAnything;
    NSMutableSet *changedNames;
    NSArray *allBundles, *newDisabledBundleNames;
    unsigned bundleIndex, bundleCount;

    newDisabledBundleNames = [[NSUserDefaults standardUserDefaults] arrayForKey:OFBundleRegistryDisabledBundlesDefaultsKey];

    /* quick equality test */
    if ([oldDisabledBundleNames isEqualToArray:newDisabledBundleNames])
        return;

    /* compute differences */
    changedNames = [NSMutableSet setWithArray:oldDisabledBundleNames];
    [changedNames exclusiveDisjoinSet:[NSSet setWithArray:newDisabledBundleNames]];

    [oldDisabledBundleNames release];
    oldDisabledBundleNames = [newDisabledBundleNames copy];

    /* full equality test */
    if (![changedNames count])
        return;

    /* Mark all bundles affected by this change as needing a restart before changes will take effect. */
    changedAnything = NO;
    allBundles = [self knownBundles];
    bundleCount = [allBundles count];
    for(bundleIndex = 0; bundleIndex < bundleCount; bundleIndex ++) {
        NSMutableDictionary *bundleDescription = [allBundles objectAtIndex:bundleIndex];
        NSString *thisBundlePath;
        NSString *thisBundleName;

        thisBundlePath = [bundleDescription objectForKey:@"path"];
        if (!thisBundlePath)
            thisBundlePath = [[bundleDescription objectForKey:@"bundle"] bundlePath];
        if (!thisBundlePath)
            continue; // ??!!

        thisBundleName = [thisBundlePath lastPathComponent];
        if ([changedNames containsObject:thisBundlePath]  ||
            [changedNames containsObject:thisBundleName]  ||
            [changedNames containsObject:[thisBundleName stringByDeletingPathExtension]]) {
            if (![bundleDescription objectForKey:@"needsRestart"]) {
                [bundleDescription setObject:@"YES" forKey:@"needsRestart"];
                changedAnything = YES;
            }
        }
    }

    if (changedAnything) {
        [[NSNotificationCenter defaultCenter] postNotificationName:OFBundleRegistryChangedNotificationName object:nil];
    }
}

// Returns an array of bundle descriptions (currently NSMutableDictionaries)
+ (NSArray *)bundlesInDirectory:(NSString *)directoryPath ignoringPaths:(NSSet *)pathsToIgnore;
{
    NSString *expandedDirectoryPath;
    NSArray *bundleExtensions, *disabledBundleNamesArray;
    NSSet *disabledBundleNames;
    NSMutableArray *bundles;
    NSArray *candidates;
    unsigned int candidateIndex, candidateCount;
    NSFileManager *fileManager;
    
    expandedDirectoryPath = [directoryPath stringByExpandingTildeInPath];
    fileManager = [NSFileManager defaultManager];
    candidates = [[fileManager contentsOfDirectoryAtPath:expandedDirectoryPath error:NULL] sortedArrayUsingSelector:@selector(compare:)];
    if (!candidates)
        return nil;
    
    if (!(bundleExtensions = [configDictionary objectForKey:OFBundleRegistryConfigBundleExtensions]))
        bundleExtensions = [NSArray arrayWithObjects:@"omni", nil];

    disabledBundleNamesArray = [[NSUserDefaults standardUserDefaults] arrayForKey:OFBundleRegistryDisabledBundlesDefaultsKey]; 
    if (disabledBundleNamesArray)
        disabledBundleNames = [NSSet setWithArray:disabledBundleNamesArray];
    else
        disabledBundleNames = [NSSet set];
    
    bundles = [NSMutableArray array];
    candidateCount = [candidates count];
    for (candidateIndex = 0; candidateIndex < candidateCount; candidateIndex++) {
        NSString *candidateName;
        NSString *bundlePath;
        NSBundle *bundle;
        NSMutableDictionary *description;

        candidateName = [candidates objectAtIndex:candidateIndex];
        if (![bundleExtensions containsObject:[candidateName pathExtension]])
            continue;

        bundlePath = [expandedDirectoryPath stringByAppendingPathComponent:candidateName];
        
        if ([pathsToIgnore containsObject:bundlePath])
            continue;

        description = [NSMutableDictionary dictionary];
        [description setObject:bundlePath forKey:@"path"];
        [bundles addObject:description];

        if ([disabledBundleNames containsObject:candidateName] ||
            [disabledBundleNames containsObject:[candidateName stringByDeletingPathExtension]] ||
            [disabledBundleNames containsObject:bundlePath]) {
            [description setObject:@"disabled" forKey:@"invalid"];
            continue;
        }
        
        bundle = [NSBundle bundleWithPath:bundlePath];
        if (!bundle) {
            // bundle might be nil if the candidate is not a directory or is a symbolic link to a path that doesn't exist or doesn't contain a valid bundle.
            [description setObject:NSLocalizedStringFromTableInBundle(@"Not a valid bundle", @"OmniFoundation", [OFBundleRegistry bundle], @"invalid bundle reason") forKey:@"invalid"];
            continue;
        }

        [description setObject:bundle forKey:@"bundle"];
        
        if ([[bundle infoDictionary] objectForKey:@"CFBundleGetInfoString"])
            [description setObject:[[bundle infoDictionary] objectForKey:@"CFBundleGetInfoString"] forKey:@"text"];
    }

    return [bundles count] > 0 ? bundles : nil;
}

#endif

+ (void)registerDictionary:(NSDictionary *)registrationClassToOptionsDictionary forBundle:(NSDictionary *)bundleDescription;
{
    NSString *bundlePath, *registrationClassName;
    NSEnumerator *registrationClassEnumerator, *registrationClassToOptionsDictionaryEnumerator;
    NSBundle *bundle;

    bundle = [bundleDescription objectForKey:@"bundle"];

    // this is just temporary ...wim
    if (bundle) {
        bundlePath = [bundleDescription objectForKey:@"path"];
        if (bundlePath && ![bundlePath isEqual:[bundle bundlePath]])
            NSLog(@"OFBundleRegistry: warning: %@ != %@", bundlePath, [bundle bundlePath]);
    }
    
    bundlePath = bundle ? [bundle bundlePath] : NSLocalizedStringFromTableInBundle(@"local configuration file", @"OmniFoundation", [OFBundleRegistry bundle], @"local bundle path readable string");

    registrationClassEnumerator = [registrationClassToOptionsDictionary keyEnumerator];
    registrationClassToOptionsDictionaryEnumerator = [registrationClassToOptionsDictionary objectEnumerator];

    while ((registrationClassName = [registrationClassEnumerator nextObject])) {
        NSDictionary *registrationDictionary;
        NSEnumerator *itemEnumerator;
        NSString *itemName;
        NSEnumerator *descriptionEnumerator;
        Class registrationClass;

        if (!registrationClassName || [registrationClassName length] == 0)
            break;

        registrationDictionary = [registrationClassToOptionsDictionaryEnumerator nextObject];
        registrationClass = NSClassFromString(registrationClassName);
        if (!registrationClass) {
            NSLog(@"OFBundleRegistry warning: registration class '%@' from bundle '%@' not found.", registrationClassName, bundlePath);
            continue;
        }
        if (![registrationClass respondsToSelector:@selector(registerItemName:bundle:description:)]) {
            NSLog(@"OFBundleRegistry warning: registration class '%@' from bundle '%@' doesn't accept registrations", registrationClassName, bundlePath);
            continue;
        }

        itemEnumerator = [registrationDictionary keyEnumerator];
        descriptionEnumerator = [registrationDictionary objectEnumerator];

        while ((itemName = [itemEnumerator nextObject])) {
            NSDictionary *descriptionDictionary;

            descriptionDictionary = [descriptionEnumerator nextObject];
            NS_DURING {
                [registrationClass registerItemName:itemName bundle:bundle description:descriptionDictionary];
            } NS_HANDLER {
                NSLog(@"+[%@ registerItemName:%@ bundle:%@ description:%@]: %@", [registrationClass description], [itemName description], [bundle description], [descriptionDictionary description], [localException reason]);
            } NS_ENDHANDLER;
        }
    }
}

+ (void)registerBundles:(NSArray *)bundleDescriptions
{
    NSEnumerator *bundleEnumerator;
    NSMutableDictionary *description;

    if (!configDictionary)
        return;

    if (!bundleDescriptions || ![bundleDescriptions count]) {
        // nothing to do, so short-circuit to avoid unnecessary notifications
        return;
    }

    [knownBundles addObjectsFromArray:bundleDescriptions];
        
    bundleEnumerator = [bundleDescriptions objectEnumerator];
    while ((description = [bundleEnumerator nextObject])) {
        NSBundle *bundle;
        NSDictionary *infoDictionary;
        NSString *bundlePath;
        NSString *bundleName;
        NSString *bundleIdentifier;
        NSString *softwareVersion;
        NSDictionary *registrationDictionary;

        // skip invalidated bundles
        if ([description objectForKey:@"invalid"] != nil)
            continue;
        
        bundle = [description objectForKey:@"bundle"];

        bundlePath = [bundle bundlePath];
        bundleName = [bundlePath lastPathComponent];
        bundleIdentifier = [bundle bundleIdentifier];
        if ([NSString isEmptyString:bundleIdentifier])
            bundleIdentifier = [bundleName stringByDeletingPathExtension];
        infoDictionary = [bundle infoDictionary];

        // If the bundle isn't already loaded, decide whether to register it
        if (![[description objectForKey:@"loaded"] isEqualToString:@"YES"]) {
            NSDictionary *requiredVersionsDictionary;

            // Look up the bundle's required software
            requiredVersionsDictionary = [infoDictionary objectForKey:OFRequiredSoftwareVersions];
            if (!requiredVersionsDictionary) {
                if (OFBundleRegistryDebug)
                    NSLog(@"OFBundleRegistry: Skipping %@ (obsolete)", bundlePath);
                [description setObject:NSLocalizedStringFromTableInBundle(@"Bundle is obsolete", @"OmniFoundation", [OFBundleRegistry bundle], @"invalid bundle reason") forKey:@"invalid"];
                continue;
            }
            // Check whether we have the bundle's required software
            if (![self haveSoftwareVersionsInDictionary:requiredVersionsDictionary]) {
                if (OFBundleRegistryDebug)
                    NSLog(@"OFBundleRegistry: Skipping %@ (requires software)", bundlePath);
                [description setObject:NSLocalizedStringFromTableInBundle(@"Bundle requires additional software", @"OmniFoundation", [OFBundleRegistry bundle], @"invalid bundle reason") forKey:@"invalid"];
                continue;
            }
            // Check whether we've already registered another copy of this bundle
            if ([registeredBundleNames containsObject:bundleName]) {
                // A possible enhancement would be to keep track of the duplicates rather than just throwing them out, and fall back on loading them if the first copy fails to load.
                if (OFBundleRegistryDebug)
                    NSLog(@"OFBundleRegistry: Skipping %@ (duplicate bundle name)", bundlePath);
                [description setObject:NSLocalizedStringFromTableInBundle(@"Duplicate bundle name", @"OmniFoundation", [OFBundleRegistry bundle], @"invalid bundle reason") forKey:@"invalid"];
                continue;
            }
        }
        // OK, we're going to register this bundle
        [registeredBundleNames addObject:bundleName];

        // Look up the bundle's software version
        softwareVersion = [infoDictionary objectForKey:@"OFSoftwareVersion"];
        if (softwareVersion != nil) {
            NSLog(@"OFBundleRegistry: Deprecated OFSoftwareVersion key found in %@", bundlePath);
        } else {
            softwareVersion = [infoDictionary objectForKey:@"CFBundleVersion"];
        }
        if (softwareVersion == nil || [softwareVersion isEqualToString:@""]) {
            // For logging purposes, let's say "unknown" rather than being blank
            softwareVersion = @"unknown";
        } else {
            // Register this bundle if it has a specified version number
            [softwareVersionDictionary setObject:softwareVersion forKey:bundleIdentifier];
        }

        // Register the bundle
        registrationDictionary = [infoDictionary objectForKey:OFRegistrations];
        if (registrationDictionary) {
            if (OFBundleRegistryDebug)
                NSLog(@"OFBundleRegistry: Registering %@ (version %@)", bundlePath, softwareVersion);
            [self registerDictionary:registrationDictionary forBundle:description];
        } else {
            if (OFBundleRegistryDebug)
                NSLog(@"OFBundleRegistry: Found %@ (version %@) (no registrations)", bundlePath, softwareVersion);
        }
    }

    [[NSNotificationCenter defaultCenter] postNotificationName:OFBundleRegistryChangedNotificationName object:nil];
}

+ (void)registerAdditionalRegistrations;
{
    NSEnumerator *registrationPathEnumerator;
    NSString *registrationPath;

    if (!configDictionary)
        return;

    NSDictionary *environmentDictionary = [[NSProcessInfo processInfo] environment];
    registrationPathEnumerator = [[configDictionary objectForKey:OFBundleRegistryConfigAdditionalRegistrations] objectEnumerator];
    while ((registrationPath = [registrationPathEnumerator nextObject])) {
        NSDictionary *registrationDictionary;

        registrationPath = [registrationPath stringByReplacingKeysInDictionary:environmentDictionary startingDelimiter:@"$(" endingDelimiter:@")"];
        registrationPath = [registrationPath stringByExpandingTildeInPath];
        registrationDictionary = [[NSDictionary alloc] initWithContentsOfFile:registrationPath];
        if (registrationDictionary)
            [self registerDictionary:registrationDictionary forBundle:nil];
    }
}

+ (BOOL)haveSoftwareVersionsInDictionary:(NSDictionary *)requiredVersionsDictionary;
{
    NSEnumerator *softwareEnumerator, *requiredVersionEnumerator;
    NSString *software;

    softwareEnumerator = [requiredVersionsDictionary keyEnumerator];
    requiredVersionEnumerator = [requiredVersionsDictionary objectEnumerator];
    while ((software = [softwareEnumerator nextObject])) {
        NSString *requiredVersion, *softwareVersion;

        requiredVersion = [requiredVersionEnumerator nextObject];
        softwareVersion = [softwareVersionDictionary objectForKey:software];
        if (OFBundleRegistryDebug)
            NSLog(@"OFBundleRegistry: Looking for version %@ of %@, found %@", requiredVersion, software, softwareVersion);
        if ([NSString isEmptyString:requiredVersion]) {
            // Match any version of the software
            if (softwareVersion == nil)
                return NO; // Software not found
        } else {
            // Look for an exact match of the software
            if (![requiredVersion isEqualToString:softwareVersion])
                return NO; // Software version wasn't an exact match
        }
    }
    return YES;
}

@end
