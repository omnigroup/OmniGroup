// Copyright 1999-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSBundle-OFFixes.h>

#ifdef __MACH__
#import <mach-o/dyld.h>
#endif

RCS_ID("$Id$")

@implementation NSBundle (OFFixes)

static IMP oldBundleForClass = NULL;
static NSMutableDictionary *cachedBundlesForClasses = nil;
static NSLock *cachedBundlesForClassesLock = nil;

static IMP original_bundleWithIdentifier = NULL;

+ (void) performPosing;
{
    cachedBundlesForClasses = [[NSMutableDictionary alloc] init];
    cachedBundlesForClassesLock = [[NSLock alloc] init];
    oldBundleForClass = OBReplaceMethodImplementationWithSelector(((Class)self)->isa /* we're replacing a class method */, @selector(bundleForClass:), @selector(replacement_bundleForClass:));
    OBPOSTCONDITION(oldBundleForClass != NULL);
    
    original_bundleWithIdentifier = OBReplaceMethodImplementationWithSelector(((Class)self)->isa /* we're replacing a class method */, @selector(bundleWithIdentifier:), @selector(replacement_bundleWithIdentifier:));
    OBPOSTCONDITION(original_bundleWithIdentifier != NULL);
}

// In 10.0.4, +bundleForClass: accesses the filesystem every time you call it, so we're now caching the results
// TJW: Retested on 10.2.6 and 10.3 7A179 (from WWDC2003).  This is still a problem: It seems they've added a single-entry cache, but if you repeatedly pass classes from different bundles, you'll get repeated stat/access calls for those bundles.
// Test case submitted at http://www.omnigroup.com/~bungi/NSBundleFileAccessTest-20030702.zip
// Submitted to Radar as #3313045
+ (NSBundle *)replacement_bundleForClass:(Class)aClass;
{
    NSBundle *bundle = nil;
    NSString *className;

    if (aClass == nil)
        return oldBundleForClass(self, _cmd, aClass);
    className = NSStringFromClass(aClass);
    if (className == nil)
        return oldBundleForClass(self, _cmd, aClass);
    [cachedBundlesForClassesLock lock];
    bundle = [cachedBundlesForClasses objectForKey:className];
    [cachedBundlesForClassesLock unlock];
    if (bundle != nil) {
        return bundle;
    }
    bundle = oldBundleForClass(self, _cmd, aClass);
    if (bundle != nil) {
        [cachedBundlesForClassesLock lock];
#ifdef OMNI_ASSERTIONS_ON
        NSBundle *cachedBundle = 
#endif
        [cachedBundlesForClasses objectForKey:className];
        OBASSERT(cachedBundle == nil || cachedBundle == bundle);
        [cachedBundlesForClasses setObject:bundle forKey:className];
        [cachedBundlesForClassesLock unlock];
    }
    return bundle;
}

/*
 Radar #4435970.
 If there is a duplicate copy of the app, LaunchServies can end up looking at that other bundle for strings and such.
 As part of this, it allocates and then deallocates a CFBundleRef for the other bundle.
 The deallocation of the duplicate bundle deregisters the running bundle!
 We've seen this happen for the main bundle, <bug://bugs/26790>.
 */
+ (NSBundle *)replacement_bundleWithIdentifier:(NSString *)identifier;
{
    NSBundle *bundle = original_bundleWithIdentifier(self, _cmd, identifier);
    if (bundle)
	return bundle;
    
    NSBundle *mainBundle = [NSBundle mainBundle];
    if ([identifier isEqualToString:[mainBundle bundleIdentifier]])
	return mainBundle;
    
    return nil;
}

@end
