// Copyright 2013-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "NSScriptSuiteRegistry-OFExtensions.h"

RCS_ID("$Id$")

@implementation NSScriptSuiteRegistry (OFExtensions)

static NSScriptSuiteRegistry *(*original_sharedScriptSuiteRegistry)(Class cls, SEL _cmd);

+ (void)performPosing;
{
    original_sharedScriptSuiteRegistry = (typeof(original_sharedScriptSuiteRegistry))OBReplaceClassMethodImplementationWithSelector(self, @selector(sharedScriptSuiteRegistry), @selector(replacement_sharedScriptSuiteRegistry));
}

+ (NSScriptSuiteRegistry *)replacement_sharedScriptSuiteRegistry;
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *registryClassName = [[NSUserDefaults standardUserDefaults] stringForKey:@"OFScriptSuiteRegistryClassName"];
        if (![NSString isEmptyString:registryClassName]) {
            Class cls = NSClassFromString(registryClassName);
            OBASSERT(cls);
            if (cls) {
                static NSScriptSuiteRegistry *registry;
                
                registry = [[cls alloc] init]; // -setSharedScriptSuiteRegistry: doesn't retain the instance, so we keep a reference
                [NSScriptSuiteRegistry setSharedScriptSuiteRegistry:registry];
                OBASSERT(original_sharedScriptSuiteRegistry(self, _cmd) == registry);
            }
        }
    });
    
    return original_sharedScriptSuiteRegistry(self, _cmd);
}

@end
