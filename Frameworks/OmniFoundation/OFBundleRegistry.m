// Copyright 1997-2005, 2007-2008, 2010-2011, 2013 Omni Development, Inc. All rights reserved.
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
    

static NSString * const PathBundleDescriptionKey = @"path";

@interface OFBundleRegistry (Private)
+ (void)readConfigDictionary;
+ (NSArray *)standardPath;
+ (NSArray *)_bundlesFromStandardPath;
+ (NSArray *)bundlesInDirectory:(NSString *)directoryPath ignoringPaths:(NSSet *)seen;
#ifdef OF_BUNDLE_REGISTRY_DYNAMIC_BUNDLE_LOADING
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
#ifdef OF_BUNDLE_REGISTRY_DYNAMIC_BUNDLE_LOADING
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
    
#ifdef OMNI_ASSERTIONS_ON
    do {
        if ([[NSBundle mainBundle] bundleIdentifier] == nil)
            // This *could* possibly be a horribly misconfigured app, but you aren't going to get very far if so. The most likely case is that this is a command line tool which doesn't have a real Info.plist.
            break;
        
        // Sanity check the main bundle's Info.plist. In particular, this helps make sure we detect if the InfoPlist.h scheme we use gets broken by using Xcode's plist editor.
        NSDictionary *infoDictionary = [[NSBundle mainBundle] infoDictionary];
    
        OBASSERT([[[OFVersionNumber alloc] initWithVersionString:[infoDictionary objectForKey:(id)kCFBundleVersionKey]] autorelease]);
        OBASSERT([[[OFVersionNumber alloc] initWithVersionString:[infoDictionary objectForKey:(id)CFSTR("CFBundleShortVersionString")]] autorelease]);
        
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

+ (void)didLoad;
{
    [self registerKnownBundles];
}

+ (void)registerKnownBundles;
{
    [self readConfigDictionary];
    [self registerBundles:[self linkedBundles]];
    [self registerBundles:[self _bundlesFromStandardPath]];
#ifdef OF_BUNDLE_REGISTRY_DYNAMIC_BUNDLE_LOADING
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(recordBundleLoading:) name:NSBundleDidLoadNotification object:nil]; // Keep track of future bundle loads
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_defaultsDidChange:) name:NSUserDefaultsDidChangeNotification object:nil]; // Keep track of changes to defaults
#endif
    [self registerAdditionalRegistrations];
#ifdef OF_BUNDLE_REGISTRY_DYNAMIC_BUNDLE_LOADING
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
    [self registerBundles:[self _bundlesFromStandardPath]];
    [OFBundledClass processImmediateLoadClasses];
}
#endif

+ (void)noteAdditionalBundles:(NSArray *)additionalBundles owner:bundleOwner
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

@end

@implementation OFBundleRegistry (Private)

static NSString * const OFBundleRegistryConfig = @"OFBundleRegistryConfig";
#ifdef OF_BUNDLE_REGISTRY_DYNAMIC_BUNDLE_LOADING
static NSString * const OFRequiredSoftwareVersions = @"OFRequiredSoftwareVersions";
#endif
static NSString * const OFRegistrations = @"OFRegistrations";

static NSString * const OFBundleRegistryConfigSearchPaths = @"SearchPaths";
static NSString * const OFBundleRegistryConfigAppWrapperPath = @"AppWrapper";
static NSString * const OFBundleRegistryConfigBundleExtensions = @"BundleExtensions";
static NSString * const OFBundleRegistryConfigAdditionalRegistrations = @"AdditionalRegistrations";
static NSString * const OFBundleRegistryConfigLogBundleRegistration = @"LogBundleRegistration";

#ifdef OF_BUNDLE_REGISTRY_DYNAMIC_BUNDLE_LOADING
NSString * const OFBundleRegistryDisabledBundlesDefaultsKey = @"DisabledBundles";
#endif

static NSDictionary *configDictionary = nil;
static BOOL OFBundleRegistryDebug = NO;

static NSString *_normalizedPath(NSString *path)
{
    return [[[path stringByExpandingTildeInPath] stringByResolvingSymlinksInPath] stringByStandardizingPath];
}

+ (void)readConfigDictionary;
{
    NSString *logBundleRegistration;

#ifdef OF_BUNDLE_REGISTRY_DYNAMIC_BUNDLE_LOADING
    NSBundle *bundle = [OFController controllingBundle];
#else
    NSBundle *bundle = [NSBundle mainBundle];
#endif
    
    configDictionary = [[[bundle infoDictionary] objectForKey:OFBundleRegistryConfig] retain];
    if (!configDictionary)
        configDictionary = [[NSDictionary alloc] init];

    logBundleRegistration = [configDictionary objectForKey:OFBundleRegistryConfigLogBundleRegistration];
    if (logBundleRegistration != nil && [logBundleRegistration boolValue] == YES)
        OFBundleRegistryDebug = YES;

#ifdef OF_BUNDLE_REGISTRY_DYNAMIC_BUNDLE_LOADING
    oldDisabledBundleNames = [[[NSUserDefaults standardUserDefaults] arrayForKey:OFBundleRegistryDisabledBundlesDefaultsKey] copy];
#endif
}

+ (NSArray *)standardPath;
{
    static NSArray *standardPath = nil;
    NSArray *configPathArray;

    if (standardPath)
        return standardPath;

    // Bundles are stored in the Resources directory of the applications, but tools might have bundles in the same directory as their binary.  Use both paths.
    // Use the controllingBundle in case we are a unit test.
#ifdef OF_BUNDLE_REGISTRY_DYNAMIC_BUNDLE_LOADING
    NSBundle *mainBundle = [OFController controllingBundle];
    NSString *mainBundlePath = _normalizedPath([mainBundle bundlePath]);
    NSString *mainBundleResourcesPath = [[mainBundlePath stringByAppendingPathComponent:@"Contents"] stringByAppendingPathComponent:@"PlugIns"];
#endif

    // Search for the config path array in defaults, then in the app wrapper's configuration dictionary.  (In gdb, we set the search path on the command line where it will appear in the NSArgumentDomain, overriding the app wrapper's configuration.)
    if ((configPathArray = [[NSUserDefaults standardUserDefaults] arrayForKey:OFBundleRegistryConfigSearchPaths]) ||
        (configPathArray = [configDictionary objectForKey:OFBundleRegistryConfigSearchPaths])) {

        NSMutableArray *newPath = [[NSMutableArray alloc] init];
        for (NSString *path in configPathArray) {
            if ([path isEqualToString:OFBundleRegistryConfigAppWrapperPath]) {
#ifdef OF_BUNDLE_REGISTRY_DYNAMIC_BUNDLE_LOADING
                [newPath addObject:mainBundleResourcesPath];
                [newPath addObject:mainBundlePath];
#ifdef DEBUG

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
                // Also look next to the controlling bundle in DEBUG builds. This allows us to find locally built copies of plugins in development.
                // (But don't look here if we're sandboxed, because that won't work.)
                if (![[NSProcessInfo processInfo] isSandboxed])
                    [newPath addObject:[_normalizedPath([[OFController controllingBundle] bundlePath]) stringByDeletingLastPathComponent]];
#endif

#endif
#endif
            } else
                [newPath addObject:path];
        }

        standardPath = [newPath copy];
        [newPath release];
    } else {
        // standardPath = ("~/Library/Components", "/Library/Components", "AppWrapper");
        standardPath = [[NSArray alloc] initWithObjects:
#ifdef OF_BUNDLE_REGISTRY_DYNAMIC_BUNDLE_LOADING
            // User's library directory
            [NSString pathWithComponents:[NSArray arrayWithObjects:NSHomeDirectory(), @"Library", @"Components", nil]],

            // Standard Mac OS X library directories
            [NSString pathWithComponents:[NSArray arrayWithObjects:@"/", @"Library", @"Components", nil]],

            // App wrapper
            mainBundleResourcesPath,
            mainBundlePath,
#endif

            nil];
    }

    return standardPath;
}

+ (NSArray *)linkedBundles
{
    NSMutableArray *linkedBundles = [NSMutableArray array];

#ifdef OF_BUNDLE_REGISTRY_DYNAMIC_BUNDLE_LOADING
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

// Returns an NSArray of bundle descriptions
+ (NSArray *)_bundlesFromStandardPath;
{
    // Make a note of paths we've already examined so we can skip them this time
    NSMutableSet *seenPaths = [[NSMutableSet alloc] init];
    
    for (NSDictionary *bundleDict in knownBundles) {
        NSString *aPath;
        
        aPath = _normalizedPath([bundleDict objectForKey:PathBundleDescriptionKey]);
        if (aPath)
            [seenPaths addObject:aPath];
        aPath = _normalizedPath([[bundleDict objectForKey:PathBundleDescriptionKey] bundlePath]);
        if (aPath)
            [seenPaths addObject:aPath];
    }

    NSDictionary *environmentDictionary = [[NSProcessInfo processInfo] environment];
    NSMutableArray *bundlesFromStandardPath = [[NSMutableArray alloc] init];

    // Now find all the bundles from the standard paths
    for (NSString *pathElement in [self standardPath])  {
        pathElement = [pathElement stringByReplacingKeysInDictionary:environmentDictionary startingDelimiter:@"$(" endingDelimiter:@")"];
        @try {
            [bundlesFromStandardPath addObjectsFromArray:[self bundlesInDirectory:pathElement ignoringPaths:seenPaths]];
        } @catch (NSException *exc) {
            NSLog(@"+[OFBundleRegistry bundlesFromStandardPath]: %@", [exc reason]);
        }
    }

    [seenPaths release];

    return [bundlesFromStandardPath autorelease];
}

// Returns an array of bundle descriptions (currently NSMutableDictionaries)
+ (NSArray *)bundlesInDirectory:(NSString *)directoryPath ignoringPaths:(NSSet *)pathsToIgnore;
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
    NSArray *candidates = [[fileManager contentsOfDirectoryAtPath:expandedDirectoryPath error:NULL] sortedArrayUsingSelector:@selector(compare:)];
    if (!candidates)
        return nil;
    
    NSArray *bundleExtensions;
    if (!(bundleExtensions = [configDictionary objectForKey:OFBundleRegistryConfigBundleExtensions]))
        bundleExtensions = [NSArray arrayWithObjects:@"omni", nil];

#ifdef OF_BUNDLE_REGISTRY_DYNAMIC_BUNDLE_LOADING
    NSSet *disabledBundleNames;
    NSArray *disabledBundleNamesArray = [[NSUserDefaults standardUserDefaults] arrayForKey:OFBundleRegistryDisabledBundlesDefaultsKey]; 
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

    return [bundles count] > 0 ? bundles : nil;
}

#ifdef OF_BUNDLE_REGISTRY_DYNAMIC_BUNDLE_LOADING

// Invoked whenever NSBundle loads something
+ (void)recordBundleLoading:(NSNotification *)note
{
    NSBundle *theBundle = [note object];
#warning thread-safety ?
//    NSLog(@"Loded %@, info: %@", theBundle, [[note userInfo] description]);

    NSMutableDictionary *newlyLoadedBundleDescription = nil;

    for (NSMutableDictionary *aBundleDict in knownBundles) {
        NSBundle *aBundle = [aBundleDict objectForKey:@"bundle"];
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
}

// Invoked when the defaults change
// The only reason we watch this is to update our disabled bundles list, so we don't need to do it if we don't have dynamically loaded bundles.
+ (void)_defaultsDidChange:(NSNotification *)note
{
    NSArray *newDisabledBundleNames = [[NSUserDefaults standardUserDefaults] arrayForKey:OFBundleRegistryDisabledBundlesDefaultsKey];

    /* quick equality test */
    if ([oldDisabledBundleNames isEqualToArray:newDisabledBundleNames])
        return;

    /* compute differences */
    NSMutableSet *changedNames = [NSMutableSet setWithArray:oldDisabledBundleNames];
    [changedNames exclusiveDisjoinSet:[NSSet setWithArray:newDisabledBundleNames]];

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

+ (void)registerDictionary:(NSDictionary *)registrationClassToOptionsDictionary forBundle:(NSDictionary *)bundleDescription;
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
    for (NSString *path in [bundle pathsForResourcesOfType:@"defaults" inDirectory:nil]) {
        NSError *error = nil;
        
        if ([path hasPrefix:@"/System/"]) {
            // Don't grab stuff from "/System/Library/Frameworks/PreferencePanes.framework/Resources/global.defaults"
            continue;
        }
        
        CFPropertyListRef plist = OFCreatePropertyListFromFile((CFStringRef)path, kCFPropertyListImmutable, (CFErrorRef *)&error);
        if (!plist) {
            NSLog(@"Unable to parse %@ as a property list: %@", path, [error toPropertyList]);
            [error release];
            continue;
        }
        
        if (![(id)plist isKindOfClass:[NSDictionary class]]) {
            NSLog(@"Contents of %@ is not a dictionary.", path);
            CFRelease(plist);
            continue;
        }
        
        [NSUserDefaults registerItemName:OFUserDefaultsRegistrationItemName bundle:bundle description:(NSDictionary *)plist];
        CFRelease(plist);
    }

    for (NSString *registrationClassName in registrationClassToOptionsDictionary) {
        NSDictionary *registrationDictionary = [registrationClassToOptionsDictionary objectForKey:registrationClassName];
        Class registrationClass = NSClassFromString(registrationClassName);
        if (!registrationClass) {
            NSLog(@"OFBundleRegistry warning: registration class '%@' from bundle '%@' not found.", registrationClassName, bundlePath);
            continue;
        }
        if (![registrationClass respondsToSelector:@selector(registerItemName:bundle:description:)]) {
            NSLog(@"OFBundleRegistry warning: registration class '%@' from bundle '%@' doesn't accept registrations", registrationClassName, bundlePath);
            continue;
        }

        for (NSString *itemName in registrationDictionary) {
            NSDictionary *descriptionDictionary = [registrationDictionary objectForKey:itemName];

            @try {
                [registrationClass registerItemName:itemName bundle:bundle description:descriptionDictionary];
            } @catch (NSException *exc) {
                NSLog(@"+[%@ registerItemName:%@ bundle:%@ description:%@]: %@", [registrationClass description], [itemName description], [bundle description], [descriptionDictionary description], [exc reason]);
            };
        }
    }    
}

+ (void)registerBundles:(NSArray *)bundleDescriptions
{
    if (!configDictionary)
        return;

    [knownBundles addObjectsFromArray:bundleDescriptions];
    
    for (NSMutableDictionary *description in bundleDescriptions) {
        // skip invalidated bundles
        if ([description objectForKey:@"invalid"] != nil)
            continue;
        
        NSBundle *bundle = [description objectForKey:@"bundle"];

        NSString *bundlePath = _normalizedPath([bundle bundlePath]);
        NSString *bundleName = [bundlePath lastPathComponent];
        NSString *bundleIdentifier = [bundle bundleIdentifier];
        if ([NSString isEmptyString:bundleIdentifier])
            bundleIdentifier = [bundleName stringByDeletingPathExtension];
#ifdef OF_BUNDLE_REGISTRY_DYNAMIC_BUNDLE_LOADING
        NSDictionary *infoDictionary = [bundle infoDictionary];

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
#else
        NSString *infoDictionaryPath = [bundle pathForResource:@"Info" ofType:@"plist"];
        NSDictionary *infoDictionary = [NSDictionary dictionaryWithContentsOfFile:infoDictionaryPath];
#endif

        OBASSERT(infoDictionary != nil);

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

        // Register the bundle (which will look not only at the passed in dictionary, but also at the bundle's resources).
        NSDictionary *registrationDictionary = [infoDictionary objectForKey:OFRegistrations];
        if (OFBundleRegistryDebug)
            NSLog(@"OFBundleRegistry: Registering %@ (version %@) (%ld registrations)", bundlePath, softwareVersion, [registrationDictionary count]);
        [self registerDictionary:registrationDictionary forBundle:description];
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
            [self registerDictionary:registrationDictionary forBundle:nil];
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
