// Copyright 1997-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFBundleRegistry.h>

#import <OmniFoundation/NSObject-OFExtensions.h>
#import <OmniFoundation/NSString-OFReplacement.h>
#import <OmniFoundation/NSMutableSet-OFExtensions.h>
#ifdef OF_BUNDLE_REGISTRY_DYNAMIC_BUNDLE_LOADING
#import <OmniFoundation/OFController.h>
#import <OmniFoundation/NSString-OFExtensions.h>
#import <OmniFoundation/OFBundledClass.h>
#endif
#import <OmniFoundation/OFBundleMigrationTarget.h>
#import <OmniFoundation/NSUserDefaults-OFExtensions.h>
#import <OmniFoundation/CFPropertyList-OFExtensions.h>
#import <OmniFoundation/OFPreference.h>
#import <OmniFoundation/OFVersionNumber.h>

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
#import <OmniFoundation/NSProcessInfo-OFExtensions.h>
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
    
NS_ASSUME_NONNULL_BEGIN

static NSString * const PathBundleDescriptionKey = @"path";
static NSString * const RegisterBundlesMigrationsKey = @"migrations";

static NSMutableSet *registeredBundleNames;
static NSMutableDictionary *softwareVersionDictionary;
static NSMutableSet *registeredBundleDescriptions;
static NSMutableDictionary * _Nullable additionalBundleDescriptions;
#ifdef OF_BUNDLE_REGISTRY_DYNAMIC_BUNDLE_LOADING
static NSArray *oldDisabledBundleNames;
#endif

static NSUserDefaults *StandardUserDefaults = nil;

@implementation OFBundleRegistry

+ (void)initialize;
{
    OBINITIALIZE;

    // We've seen KVO crashes where it *looks* like the +standardUserDefaults is changing out from underneath us while we had an active observation. Hold on to the one we are going to observe (though we might lose updates).
    StandardUserDefaults = [[NSUserDefaults standardUserDefaults] retain];

    registeredBundleNames = [[NSMutableSet alloc] init];
    softwareVersionDictionary = [[NSMutableDictionary alloc] init];
    registeredBundleDescriptions = [[NSMutableSet alloc] init];
    additionalBundleDescriptions = nil;  // Lazily create this one since not all apps use it
    
#ifdef OMNI_ASSERTIONS_ON
    do {
        if ([[NSBundle mainBundle] bundleIdentifier] == nil || OFIsRunningUnitTests())
            // This *could* possibly be a horribly misconfigured app, but you aren't going to get very far if so. The most likely case is that this is a command line tool which doesn't have a real Info.plist.
            break;
        
        // Sanity check the main bundle's Info.plist. In particular, this helps make sure we detect if the InfoPlist.h scheme we use gets broken by using Xcode's plist editor.
        NSDictionary *infoDictionary = [[NSBundle mainBundle] infoDictionary];
    
        OBASSERT(OB_AUTORELEASE([[OFVersionNumber alloc] initWithVersionString:[infoDictionary objectForKey:(id)kCFBundleVersionKey]]));
        OBASSERT(OB_AUTORELEASE([[OFVersionNumber alloc] initWithVersionString:[infoDictionary objectForKey:(id)CFSTR("CFBundleShortVersionString")]]));
        
        NSString *copyright = [infoDictionary objectForKey:@"NSHumanReadableCopyright"];
        NSCharacterSet *decimalDigits = [NSCharacterSet decimalDigitCharacterSet];
        NSUInteger yearStart = [copyright rangeOfCharacterFromSet:decimalDigits].location; // just returns the first character
        OBASSERT(yearStart != NSNotFound);
        if (yearStart != NSNotFound) {
            NSString *year = [copyright substringWithRange:NSMakeRange(yearStart, 4)];
            OBASSERT([year rangeOfCharacterFromSet:[decimalDigits invertedSet]].location == NSNotFound);
        }
    } while (0);
#endif
}

OBDidLoad(^{
    [OFBundleRegistry registerKnownBundles];
});

#ifdef OMNI_ASSERTIONS_ON
+ (BOOL)_checkBundlesAreInsideApp;
{
#ifdef DEBUG_bungi
    // We used to support having bundles and frameworks in the build output next to the app so that we could build just a framework and then re-run the app w/o having to package it up. But, we build from Xcode workspaces now and code signing and XPC service validation don't work unless things are in the right spots.
    
    NSBundle *mainBundle = [NSBundle mainBundle];
    
    NSString *mainBundlePath = [mainBundle bundlePath];
    if ([mainBundlePath hasSuffix:@"/"] == NO)
        mainBundlePath = [mainBundlePath stringByAppendingString:@"/"];
    
    NSString *mainBundleContainerPath = [mainBundlePath stringByDeletingLastPathComponent];
    if ([mainBundleContainerPath hasSuffix:@"/"] == NO)
        mainBundleContainerPath = [mainBundleContainerPath stringByAppendingString:@"/"];
    
    void (^checkBundles)(NSArray *) = ^(NSArray *bundles){
        for (NSBundle *bundle in bundles) {
            if (bundle == mainBundle)
                continue;
            
            NSString *bundlePath = [bundle bundlePath];
            
            /*
             
             IF YOU HIT THIS ASSERTION, you needs to paste this line into the Environment Variables section of your scheme in Xcode and you need a Copy Files build phase that installs frameworks and plugins in your app bundle in the right spots:
             
             DYLD_FRAMEWORK_PATH=${BUILT_PRODUCTS_DIR}/${WRAPPER_NAME}/Contents/Frameworks
             
             The problem is that even though we build with DYLIB_INSTALL_NAME_BASE=@rpath and LD_RUNPATH_SEARCH_PATHS=@executable_path/../Frameworks, Xcode decides to insert a DYLD_FRAMEWORKS_PATH that points to the build output directory. This is consulted first by dyld instead of the compiled-in path, and so we load the copy of the framework that was just built in debug builds. This, in turn, means that our XPC services can't be tested since they verify that they are inside the app that is calling them.
             
             */
            
            // If the bundle is inside the build output directory, then it should be inside the app (we don't want to pick up the bundles next to the app any more).
            OBASSERT_IF([bundlePath hasPrefix:mainBundleContainerPath], [bundlePath hasPrefix:mainBundlePath], @"Bundle %@ is from an unexpected location", bundle);
        }
    };
    
    checkBundles([NSBundle allBundles]);
    checkBundles([NSBundle allFrameworks]);
#endif
		
    return YES;
}
#endif

#ifdef OF_BUNDLE_REGISTRY_DYNAMIC_BUNDLE_LOADING
static unsigned UserDefaultsContext;
#endif

+ (void)registerKnownBundles;
{
    OBPRECONDITION([self _checkBundlesAreInsideApp]);
    
    [self readConfigDictionary];
    [self registerBundles:[self _linkedBundlesNotIncludingMainBundle]];
    [self registerBundles:[self _bundlesFromStandardPath]];
    
    // Make sure the main bundle is registered *last* so that if it overrides settings (in particular NSUserDefaults registrations) the application's choices win.
    [self registerBundles:@[[self _mainBundleDescription]]];
    
#ifdef OF_BUNDLE_REGISTRY_DYNAMIC_BUNDLE_LOADING
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(recordBundleLoading:) name:NSBundleDidLoadNotification object:nil]; // Keep track of future bundle loads

    [StandardUserDefaults addObserver:(id)self forKeyPath:OFBundleRegistryDisabledBundlesDefaultsKey options:0 context:&UserDefaultsContext]; // Keep track of changes to defaults
#endif
    [self registerAdditionalRegistrations];
#ifdef OF_BUNDLE_REGISTRY_DYNAMIC_BUNDLE_LOADING
    [OFBundledClass processImmediateLoadClasses];
#endif
}

#ifdef OF_BUNDLE_REGISTRY_DYNAMIC_BUNDLE_LOADING
+ (void)observeValueForKeyPath:(nullable NSString *)keyPath ofObject:(nullable id)object change:(nullable NSDictionary<NSKeyValueChangeKey, id> *)change context:(nullable void *)context;
{
    if (object == StandardUserDefaults && context == &UserDefaultsContext) {
        OBASSERT([keyPath isEqual:OFBundleRegistryDisabledBundlesDefaultsKey]);
        OFMainThreadPerformBlock(^{
            [self _disabledBundlesDefaultChanged];
        });
        return;
    }

    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}
#endif

+ (NSDictionary *)softwareVersionDictionary;
{
    return softwareVersionDictionary;
}

+ (NSArray <NSMutableDictionary <NSString *, id> *> *)knownBundles;
{
    // If there aren't any additional registrations, just return our known bundles
    NSArray *knownBundles = [registeredBundleDescriptions allObjects];
    
    if ([additionalBundleDescriptions count] > 0) {
        NSMutableArray *allBundleDescriptions = [[[NSMutableArray alloc] initWithArray:knownBundles] autorelease];
        
        NSEnumerator *foreignBundleEnumerator = [additionalBundleDescriptions objectEnumerator];
        NSArray *foreignBundleDescriptions;
        while( (foreignBundleDescriptions = [foreignBundleEnumerator nextObject]) != nil)
            [allBundleDescriptions addObjectsFromArray:foreignBundleDescriptions];
        
        knownBundles = allBundleDescriptions;
    }
    
    return knownBundles;
}

+ (NSArray <NSBundle *> *)knownNSBundles;
{
    return [[self knownBundles] arrayByPerformingBlock:^(NSMutableDictionary <NSString *, id> *bundleInfo) {
        return bundleInfo[@"bundle"];
    }];
}

#if 0
   // This should be changed to use a notification or some other method so that bundle-loaders other than us can catch it and re-scan for bundles when requested 
+ (void)lookForBundles
{
    [self registerBundles:[self _bundlesFromStandardPath]];
    [OFBundledClass processImmediateLoadClasses];
}
#endif

+ (void)noteAdditionalBundles:(nullable NSArray *)additionalBundles owner:(id)bundleOwner;
{
    if (additionalBundles && ![additionalBundles count])
        additionalBundles = nil;

    if (!additionalBundles) {
        if (additionalBundleDescriptions != nil &&
            [additionalBundleDescriptions objectForKey:bundleOwner] != nil) {
            [additionalBundleDescriptions removeObjectForKey:bundleOwner];
        }
    } else {
        if (additionalBundleDescriptions == nil) {
            additionalBundleDescriptions = [[NSMutableDictionary alloc] init];
        }
    
        // Assume that the bundle registrar is only sending us this message if something actually changed in its registry.
        [additionalBundleDescriptions setObject:additionalBundles forKey:bundleOwner];
    }
}

#pragma mark - Private

static NSString * const OFBundleRegistryConfig = @"OFBundleRegistryConfig";
#ifdef OF_BUNDLE_REGISTRY_DYNAMIC_BUNDLE_LOADING
static NSString * const OFRequiredSoftwareVersions = @"OFRequiredSoftwareVersions";
#endif
static NSString * const OFRegistrations = @"OFRegistrations";

static NSString * const OFBundleRegistryConfigSearchPaths = @"SearchPaths";
static NSString * const OFBundleRegistryConfigAppWrapperPath = @"AppWrapper";
static NSString * const OFBundleRegistryConfigBundleExtensions = @"BundleExtensions";
static NSString * const OFBundleRegistryConfigAdditionalRegistrations = @"AdditionalRegistrations";

static OFDeclareDebugLogLevel(OFBundleRegistryDebug)
#define DEBUG_REGISTRY(level, format, ...) do { \
    if (OFBundleRegistryDebug >= (level)) \
        NSLog(@"BUNDLE REGISTRY: " format, ## __VA_ARGS__); \
    } while (0)

#ifdef OF_BUNDLE_REGISTRY_DYNAMIC_BUNDLE_LOADING
NSString * const OFBundleRegistryDisabledBundlesDefaultsKey = @"DisabledBundles";
#endif

static NSDictionary *configDictionary = nil;

static NSString *_normalizedPath(NSString *path)
{
    return [[[path stringByExpandingTildeInPath] stringByResolvingSymlinksInPath] stringByStandardizingPath];
}

+ (void)readConfigDictionary;
{
#ifdef OF_BUNDLE_REGISTRY_DYNAMIC_BUNDLE_LOADING
    NSBundle *bundle = [OFController controllingBundle];
#else
    NSBundle *bundle = [NSBundle mainBundle];
#endif
    
    configDictionary = [[[bundle infoDictionary] objectForKey:OFBundleRegistryConfig] retain];
    if (!configDictionary)
        configDictionary = [[NSDictionary alloc] init];

#ifdef OF_BUNDLE_REGISTRY_DYNAMIC_BUNDLE_LOADING
    oldDisabledBundleNames = [[StandardUserDefaults arrayForKey:OFBundleRegistryDisabledBundlesDefaultsKey] copy];
#endif
}

+ (NSArray *)standardPath;
{
    static NSArray *standardPath = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSArray *configPathArray;

        // Bundles are stored in the Resources directory of the applications, but tools might have bundles in the same directory as their binary.  Use both paths.
#if OMNI_BUILDING_FOR_MAC
        NSBundle *mainBundle = [OFController controllingBundle]; // Use the controllingBundle in case we are a unit test.
        NSString *mainBundlePath = _normalizedPath([mainBundle bundlePath]);
        NSString *mainBundleResourcesPath = [[mainBundlePath stringByAppendingPathComponent:@"Contents"] stringByAppendingPathComponent:@"PlugIns"];
#elif OMNI_BUILDING_FOR_IOS
        NSBundle *mainBundle = [NSBundle mainBundle];
        NSString *mainBundlePath = _normalizedPath([mainBundle bundlePath]);  // iOS bundles are flat, so look for plug-ins at the top level.
#endif

        // Search for the config path array in defaults, then in the app wrapper's configuration dictionary.  (In gdb, we set the search path on the command line where it will appear in the NSArgumentDomain, overriding the app wrapper's configuration.)
        if ((configPathArray = [StandardUserDefaults arrayForKey:OFBundleRegistryConfigSearchPaths]) ||
            (configPathArray = [configDictionary objectForKey:OFBundleRegistryConfigSearchPaths])) {

            NSMutableArray *newPath = [[NSMutableArray alloc] init];
            for (NSString *path in configPathArray) {
                if ([path isEqualToString:OFBundleRegistryConfigAppWrapperPath]) {
#if OMNI_BUILDING_FOR_MAC
                    [newPath addObject:mainBundleResourcesPath];
#endif
#if OMNI_BUILDING_FOR_MAC || OMNI_BUILDING_FOR_IOS
                    [newPath addObject:mainBundlePath];
#endif

#ifdef DEBUG
// This breaks assertions in OmniFoundation about only loading things from inside the bundle; add the plugins to a copy files build phase.
//#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
//                    // Also look next to the controlling bundle in DEBUG builds. This allows us to find locally built copies of plugins in development.
//                    // (But don't look here if we're sandboxed, because that won't work.)
//                    if (![[NSProcessInfo processInfo] isSandboxed])
//                        [newPath addObject:[_normalizedPath([[OFController controllingBundle] bundlePath]) stringByDeletingLastPathComponent]];
//#endif
#endif
                } else
                    [newPath addObject:path];
            }

            standardPath = [newPath copy];
            [newPath release];
        } else {
            NSMutableArray *paths = [NSMutableArray array];
            
            // We probably could not include this for any platform, but this avoids the need for a sandbox rule.
#if OMNI_BUILDING_FOR_MAC
            // User's library directory
            [paths addObject:[NSString pathWithComponents:[NSArray arrayWithObjects:NSHomeDirectory(), @"Library", @"Components", nil]]];

            // Standard Mac OS X library directories
            [paths addObject:[NSString pathWithComponents:[NSArray arrayWithObjects:@"/", @"Library", @"Components", nil]]];
#endif

            // App wrapper
#if OMNI_BUILDING_FOR_MAC
            [paths addObject:mainBundleResourcesPath];
#endif
#if OMNI_BUILDING_FOR_MAC || OMNI_BUILDING_FOR_IOS
            [paths addObject:mainBundlePath];
#endif
            
            standardPath = [paths copy];
        }
    });
    
    return standardPath;
}

+ (NSArray *)_linkedBundlesNotIncludingMainBundle;
{
    NSMutableArray *linkedBundles = [NSMutableArray array];

    NSSet <NSBundle *>*allFrameworks = [NSSet setWithArray:[NSBundle allFrameworks]];
    for (NSBundle *framework in allFrameworks) {
        if (framework.bundleIdentifier != nil)
            [linkedBundles addObject:[NSMutableDictionary dictionaryWithObjectsAndKeys:framework, @"bundle", @"YES", @"loaded", @"YES", @"preloaded", nil]];
    }
    
    
    // Add in any dynamically loaded bundles that are already present.  In particular, unit test bundles might have registration dictionaries for their test cases.
    NSArray <NSBundle *>*allBundles = [NSBundle allBundles];
    for (NSBundle *bundle in allBundles) {
        // On iOS the app is in both allFrameworks and allBundles. Don't include it twice. Also, main bundle is handled separately
        if ([allFrameworks containsObject:bundle] || bundle == [NSBundle mainBundle]) {
            continue;
        }
        [linkedBundles addObject:[NSMutableDictionary dictionaryWithObjectsAndKeys:bundle, @"bundle", @"YES", @"loaded", @"YES", @"preloaded", nil]];
    }

    return linkedBundles;
}

+ (NSDictionary *)_mainBundleDescription;
{
    return [NSMutableDictionary dictionaryWithObjectsAndKeys:[NSBundle mainBundle], @"bundle", @"YES", @"loaded", @"YES", @"preloaded", nil];
}

// Returns an NSArray of bundle descriptions
+ (NSArray *)_bundlesFromStandardPath;
{
    // Make a note of paths we've already examined so we can skip them this time
    NSMutableSet *seenPaths = [[NSMutableSet alloc] init];
    
    for (NSDictionary *bundleDict in registeredBundleDescriptions) {
        NSString *aPath;
        
        aPath = _normalizedPath([bundleDict objectForKey:PathBundleDescriptionKey]);
        if (aPath)
            [seenPaths addObject:aPath];
        id pathValue = [bundleDict objectForKey:PathBundleDescriptionKey];
        if ([pathValue respondsToSelector:@selector(bundlePath)]) {
            aPath = _normalizedPath([pathValue bundlePath]);
            if (aPath)
                [seenPaths addObject:aPath];
        }
    }

    NSDictionary *environmentDictionary = [[NSProcessInfo processInfo] environment];
    NSMutableArray *bundlesFromStandardPath = [[NSMutableArray alloc] init];

    // Now find all the bundles from the standard paths
    for (NSString *pathElement in [self standardPath])  {
        pathElement = [pathElement stringByReplacingKeysInDictionary:environmentDictionary startingDelimiter:@"$(" endingDelimiter:@")"];

        __autoreleasing NSError *error = nil;
        NSArray *bundles = [self _bundlesInDirectory:pathElement ignoringPaths:seenPaths error:&error];
        if (!bundles) {
            if (![error causedByMissingFile]) {
                [error log:@"Error finding bundles in %@", pathElement];
            }
        } else {
            [bundlesFromStandardPath addObjectsFromArray:bundles];
        }
    }

    [seenPaths release];

    return [bundlesFromStandardPath autorelease];
}

// Returns an array of bundle descriptions (currently NSMutableDictionaries)
+ (nullable NSArray *)_bundlesInDirectory:(NSString *)directoryPath ignoringPaths:(NSSet *)pathsToIgnore error:(NSError **)outError;
{
    NSString *expandedDirectoryPath = [directoryPath stringByExpandingTildeInPath];
    if (![expandedDirectoryPath hasPrefix:@"/"]) {
#ifdef OF_BUNDLE_REGISTRY_DYNAMIC_BUNDLE_LOADING
        NSBundle *mainBundle = [OFController controllingBundle];
#else
        NSBundle *mainBundle = [NSBundle mainBundle];
#endif
        NSString *mainBundlePath = _normalizedPath([mainBundle bundlePath]);
        expandedDirectoryPath = [mainBundlePath stringByAppendingPathComponent:expandedDirectoryPath];
    }

    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSArray *candidates = [[fileManager contentsOfDirectoryAtPath:expandedDirectoryPath error:outError] sortedArrayUsingSelector:@selector(compare:)];
    if (!candidates)
        return nil;
    
    NSArray *bundleExtensions;
    if (!(bundleExtensions = [configDictionary objectForKey:OFBundleRegistryConfigBundleExtensions]))
        bundleExtensions = [NSArray arrayWithObjects:@"omni", nil];

#ifdef OF_BUNDLE_REGISTRY_DYNAMIC_BUNDLE_LOADING
    NSSet *disabledBundleNames;
    NSArray *disabledBundleNamesArray = [StandardUserDefaults arrayForKey:OFBundleRegistryDisabledBundlesDefaultsKey];
    if (disabledBundleNamesArray)
        disabledBundleNames = [NSSet setWithArray:disabledBundleNamesArray];
    else
        disabledBundleNames = [NSSet set];
#endif
    
    NSMutableArray *bundles = [NSMutableArray array];
    for (NSString *candidateName in candidates) {
        if (![bundleExtensions containsObject:[candidateName pathExtension]])
            continue;

        NSString *bundlePath = [expandedDirectoryPath stringByAppendingPathComponent:candidateName];
        
        if ([pathsToIgnore containsObject:bundlePath])
            continue;

        NSMutableDictionary *description = [NSMutableDictionary dictionary];
        [description setObject:bundlePath forKey:PathBundleDescriptionKey];
        [bundles addObject:description];

#ifdef OF_BUNDLE_REGISTRY_DYNAMIC_BUNDLE_LOADING
        if ([disabledBundleNames containsObject:candidateName] ||
            [disabledBundleNames containsObject:[candidateName stringByDeletingPathExtension]] ||
            [disabledBundleNames containsObject:bundlePath]) {
            [description setObject:@"disabled" forKey:@"invalid"];
            continue;
        }
#endif
        
        NSBundle *bundle = [NSBundle bundleWithPath:bundlePath];
        if (!bundle) {
            // bundle might be nil if the candidate is not a directory or is a symbolic link to a path that doesn't exist or doesn't contain a valid bundle.
            [description setObject:NSLocalizedStringFromTableInBundle(@"Not a valid bundle", @"OmniFoundation", [OFBundleRegistry bundle], @"invalid bundle reason") forKey:@"invalid"];
            continue;
        }

        [description setObject:bundle forKey:@"bundle"];
        
        if ([[bundle infoDictionary] objectForKey:@"CFBundleGetInfoString"])
            [description setObject:[[bundle infoDictionary] objectForKey:@"CFBundleGetInfoString"] forKey:@"text"];
    }

    return bundles;
}

#ifdef OF_BUNDLE_REGISTRY_DYNAMIC_BUNDLE_LOADING

// Invoked whenever NSBundle loads something
+ (void)recordBundleLoading:(NSNotification *)note
{
    OBPRECONDITION([self _checkBundlesAreInsideApp]);
    

    NSBundle *theBundle = [note object];
#warning thread-safety ?
//    NSLog(@"Loded %@, info: %@", theBundle, [[note userInfo] description]);

    NSMutableDictionary *newlyLoadedBundleDescription = nil;

    for (NSMutableDictionary *aBundleDict in registeredBundleDescriptions) {
        NSBundle *aBundle = [aBundleDict objectForKey:@"bundle"];
        if (aBundle == theBundle) {
            newlyLoadedBundleDescription = aBundleDict;
            break;
        }
    }

    if (newlyLoadedBundleDescription == nil) {
        // somebody loaded a bundle we didn't already know about
        newlyLoadedBundleDescription = [NSMutableDictionary dictionaryWithObjectsAndKeys:theBundle, @"bundle", nil];
        [registeredBundleDescriptions addObject:newlyLoadedBundleDescription];
    }

    [newlyLoadedBundleDescription setObject:@"YES" forKey:@"loaded"];
}

// Invoked when the defaults change
// The only reason we watch this is to update our disabled bundles list, so we don't need to do it if we don't have dynamically loaded bundles.
+ (void)_disabledBundlesDefaultChanged;
{
    NSArray *newDisabledBundleNames = [StandardUserDefaults arrayForKey:OFBundleRegistryDisabledBundlesDefaultsKey];

    /* quick equality test */
    if ([oldDisabledBundleNames isEqualToArray:newDisabledBundleNames])
        return;

    /* compute differences */
    NSMutableSet *changedNames = [NSMutableSet setWithArray:oldDisabledBundleNames];
    [changedNames exclusiveDisjointSet:[NSSet setWithArray:newDisabledBundleNames]];

    [oldDisabledBundleNames release];
    oldDisabledBundleNames = [newDisabledBundleNames copy];

    /* full equality test */
    if (![changedNames count])
        return;

    /* Mark all bundles affected by this change as needing a restart before changes will take effect. */
    
    for (NSMutableDictionary *bundleDescription in [self knownBundles]) {
        NSString *thisBundlePath;
        NSString *thisBundleName;

        thisBundlePath = [bundleDescription objectForKey:PathBundleDescriptionKey];
        if (!thisBundlePath)
            thisBundlePath = _normalizedPath([[bundleDescription objectForKey:@"bundle"] bundlePath]);
        if (!thisBundlePath)
            continue; // ??!!

        thisBundleName = [thisBundlePath lastPathComponent];
        if ([changedNames containsObject:thisBundlePath]  ||
            [changedNames containsObject:thisBundleName]  ||
            [changedNames containsObject:[thisBundleName stringByDeletingPathExtension]]) {
            if (![bundleDescription objectForKey:@"needsRestart"]) {
                [bundleDescription setObject:@"YES" forKey:@"needsRestart"];
            }
        }
    }
}

#endif

+ (void)_registerDictionary:(NSDictionary *)registrationClassToOptionsDictionary forBundle:(nullable NSDictionary *)bundleDescription;
{
    NSBundle *bundle = [bundleDescription objectForKey:@"bundle"];
    NSString *bundlePath;

    // this is just temporary ...wim
    if (bundle) {
        bundlePath = [bundleDescription objectForKey:PathBundleDescriptionKey];
        if (bundlePath && ![bundlePath isEqual:[bundle bundlePath]])
            NSLog(@"OFBundleRegistry: warning: %@ != %@", bundlePath, [bundle bundlePath]);
    }
    
    bundlePath = bundle ? [bundle bundlePath] : NSLocalizedStringFromTableInBundle(@"local configuration file", @"OmniFoundation", [OFBundleRegistry bundle], @"local bundle path readable string");

    // To facilitate sharing default registrations between Mac frameworks and iOS apps that link them as static libraries (but don't get the Info.plist), we allow putting the shared defaults in *.defaults resources.
    // We do this before the entries from the bundle infoDictionary so that the main app can override defaults from static libraries.
    // Don't spend the time looking in system bundles (or erroneously try to interpret their contents).
    if (bundle != nil && ![bundlePath hasPrefix:@"/System/"]) {
        for (NSString *path in [bundle pathsForResourcesOfType:@"defaults" inDirectory:nil]) {

            CFErrorRef error = NULL;
            CFPropertyListRef plist = OFCreatePropertyListFromFile((OB_BRIDGE CFStringRef)path, kCFPropertyListImmutable, &error);
            if (!plist) {
                [(OB_BRIDGE NSError *)error log:@"Unable to parse \"%@\" as a property list", path];
                if (error)
                    CFRelease(error);
                continue;
            }
            
            if (![(OB_BRIDGE id)plist isKindOfClass:[NSDictionary class]]) {
                NSLog(@"Contents of %@ is not a dictionary.", path);
                CFRelease(plist);
                continue;
            }
            
            [NSUserDefaults registerItemName:OFUserDefaultsRegistrationItemName bundle:bundle description:(OB_BRIDGE NSDictionary *)plist];
            CFRelease(plist);
        }
    }

    for (NSString *registrationClassName in registrationClassToOptionsDictionary) {
        NSDictionary *registrationDictionary = [registrationClassToOptionsDictionary objectForKey:registrationClassName];
        Class registrationClass = NSClassFromString(registrationClassName);
        if (!registrationClass) {
            NSLog(@"OFBundleRegistry warning: registration class '%@' from bundle '%@' not found.", registrationClassName, bundlePath);
            continue;
        }

        OBASSERT([registrationClass conformsToProtocol:@protocol(OFBundleRegistryTarget)], "The class %@ should conform to the OFBundleRegistryTarget protocol.", registrationClass);
        if (![registrationClass conformsToProtocol:@protocol(OFBundleRegistryTarget)]) {
            NSLog(@"OFBundleRegistry warning: registration class '%@' from bundle '%@' doesn't conform OFBundleRegistryTarget to accept registrations", registrationClassName, bundlePath);
            continue;
        }

        // .registrations can include an array of migrations to perform from a source suite name to destination suite name for a list of keys.
        // Its inclusion here reads a little awkwardly, but has a key benefit: it doesn't force an additional scan for a separate file extension (e.g. .migrations) in every bundle for little benefit; rather piggyback on the scan for .registrations that will already occur.
        // Capture migrations for separate processing. If found, OFBundleRegistry should perform the migrations last.
        __block NSArray <NSDictionary <NSString *, NSString *> *> *postRegistrationMigrations = nil;
        [registrationDictionary enumerateKeysAndObjectsUsingBlock:^(id _Nonnull key, id _Nonnull obj, BOOL * _Nonnull stop) {
            if ([key isEqual:RegisterBundlesMigrationsKey]) {
                postRegistrationMigrations = obj;
                return;
            }
            
            @try {
                [registrationClass registerItemName:key bundle:bundle description:obj];
            } @catch (NSException *exc) {
                NSLog(@"+[%@ registerItemName:%@ bundle:%@ description:%@]: %@", registrationClass, key, bundle, obj, [exc reason]);
            };
        }];
        
        // App Extensions can not access standard user defaults and should not attempt to perform migrations in case that's the migration's source/destination.
        // REVIEW: If needed, an additional check to ensure that migrations only happen once per bundle version can be added. This currently doesn't seem worth the extra complexity.
        if (postRegistrationMigrations == nil || OFIsRunningInAppExtension()) {
            continue;
        }

        OBASSERT([registrationClass conformsToProtocol:@protocol(OFBundleMigrationTarget)], "The class %@ should conform to the OFBundleMigrationTarget protocol if its registering for migrations.", registrationClass);
        if (![registrationClass conformsToProtocol:@protocol(OFBundleMigrationTarget)]) {
            NSLog(@"OFBundleRegistry warning: registration class '%@' from bundle '%@' doesn't conform to OFBundleMigrationTarget to accept migrations", registrationClassName, bundlePath);
            continue;
        }

        @try {
            [registrationClass migrateItems:postRegistrationMigrations bundle:bundle];
        } @catch (NSException *exc) {
            NSLog(@"+[%@ migrateItems:%@ bundle:%@]: %@", registrationClass, postRegistrationMigrations, bundle, [exc reason]);
        };
    }
}

+ (void)registerBundles:(NSArray *)bundleDescriptions
{
    if (!configDictionary)
        return;
    
    for (NSMutableDictionary *description in bundleDescriptions) {
        // skip invalidated bundles
        if ([description objectForKey:@"invalid"] != nil)
            continue;
        
        // Skip items we've seen before
        if ([registeredBundleDescriptions member:description])
            continue;
        [registeredBundleDescriptions addObject:description];
        
        NSBundle *bundle = [description objectForKey:@"bundle"];

        NSString *bundlePath = _normalizedPath([bundle bundlePath]);
        NSString *bundleName = [bundlePath lastPathComponent];
        NSString *bundleIdentifier = [bundle bundleIdentifier];
        if (OFIsEmptyString(bundleIdentifier)) {
            continue;
        }
        NSDictionary *infoDictionary = [bundle infoDictionary];
        
#ifdef OF_BUNDLE_REGISTRY_DYNAMIC_BUNDLE_LOADING
        // If the bundle isn't already loaded, decide whether to register it
        if (![[description objectForKey:@"loaded"] isEqualToString:@"YES"]) {
            NSDictionary *requiredVersionsDictionary;

            // Look up the bundle's required software
            requiredVersionsDictionary = [infoDictionary objectForKey:OFRequiredSoftwareVersions];
            if (!requiredVersionsDictionary) {
                DEBUG_REGISTRY(1, @"Skipping %@ (obsolete)", bundlePath);
                [description setObject:NSLocalizedStringFromTableInBundle(@"Bundle is obsolete", @"OmniFoundation", [OFBundleRegistry bundle], @"invalid bundle reason") forKey:@"invalid"];
                continue;
            }
            // Check whether we have the bundle's required software
            if (![self haveSoftwareVersionsInDictionary:requiredVersionsDictionary]) {
                DEBUG_REGISTRY(1, @"Skipping %@ (requires software)", bundlePath);
                [description setObject:NSLocalizedStringFromTableInBundle(@"Bundle requires additional software", @"OmniFoundation", [OFBundleRegistry bundle], @"invalid bundle reason") forKey:@"invalid"];
                continue;
            }
            // Check whether we've already registered another copy of this bundle
            if ([registeredBundleNames containsObject:bundleName]) {
                // A possible enhancement would be to keep track of the duplicates rather than just throwing them out, and fall back on loading them if the first copy fails to load.
                DEBUG_REGISTRY(1, @"Skipping %@ (duplicate bundle name)", bundlePath);
                [description setObject:NSLocalizedStringFromTableInBundle(@"Duplicate bundle name", @"OmniFoundation", [OFBundleRegistry bundle], @"invalid bundle reason") forKey:@"invalid"];
                continue;
            }
        }
#endif

        OBASSERT(infoDictionary.count != 0, "Empty infoDictionary reported for bundle %@", bundle);

        // OK, we're going to register this bundle
        [registeredBundleNames addObject:bundleName];

        // Look up the bundle's software version
        NSString *softwareVersion = [infoDictionary objectForKey:@"OFSoftwareVersion"];
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

        // Allow registration dictionaries to also be placed in the bundle as 'registration' resources (but don't look at system bundles).
        // This should be preferred to the ".defaults" file support in -registerDictionary:description: in the future. Both may become less useful if we convert all our iOS static library targets to frameworks.
        if (![bundlePath hasPrefix:@"/System/"]) {
            for (NSString *path in [bundle pathsForResourcesOfType:@"registrations" inDirectory:nil]) {
                CFErrorRef error = NULL;
                CFPropertyListRef registrations = OFCreatePropertyListFromFile((OB_BRIDGE CFStringRef)path, kCFPropertyListImmutable, &error);
                if (!registrations) {
                    [(OB_BRIDGE NSError *)error log:@"Unable to parse \"%@\" as a property list", path];
                    if (error)
                        CFRelease(error);
                    continue;
                }
                
                if (![(OB_BRIDGE id)registrations isKindOfClass:[NSDictionary class]]) {
                    NSLog(@"Contents of %@ is not a dictionary.", path);
                    CFRelease(registrations);
                    continue;
                }
                
                [self _registerDictionary:registrations forBundle:description];
                CFRelease(registrations);
            }
        }
        
        // Lastly, register the bundle (which will look not only at the passed in dictionary, but also at the bundle's resources).
        // If this is the main bundle, it is important that this is after the "registraitons" files so that it can override them.
        NSDictionary *registrationDictionary = [infoDictionary objectForKey:OFRegistrations];
        DEBUG_REGISTRY(1, @"Registering %@ (version %@) (%ld registrations)", bundlePath, softwareVersion, [registrationDictionary count]);
        [self _registerDictionary:registrationDictionary forBundle:description];
    }
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
        if (registrationDictionary) {
            [self _registerDictionary:registrationDictionary forBundle:nil];
            [registrationDictionary release];
        }
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
        DEBUG_REGISTRY(1, @"Looking for version %@ of %@, found %@", requiredVersion, software, softwareVersion);
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

NS_ASSUME_NONNULL_END
