// Copyright 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSSetCommand-OFFixes.h>

#import <Foundation/NSAppleEventDescriptor.h>
#import <Foundation/NSScriptObjectSpecifiers.h>

#import <OmniFoundation/NSScriptCommand-OFExtensions.h>

RCS_ID("$Id$");


/*
 
 Radar 4875905 -- Cocoa scripting can't set relationships to 'missing value'
 The base code works fine for setting POD properties (strings, boolean, etc), but if you 
 are setting a <property> whose 'type' is a scriptable class (a to-one relationship)
 you can't clear it by setting 'missing value'.
 
 I tried munging the 'Value' key to +[NSNull null] when it is 'msng', but that doesn't
 work either.  So, for now, we'll just handle this case completely.
 
*/

@implementation NSSetCommand (OFFixes)

static id (*originalPerformDefaultImplementation)(id self, SEL cmd) = NULL;

+ (void)didLoad;
{
    originalPerformDefaultImplementation = (void *)OBReplaceMethodImplementationWithSelector(self,  @selector(performDefaultImplementation), @selector(replacement_performDefaultImplementation));
}

- (id)replacement_performDefaultImplementation;
{
    do {
        id value = [[self arguments] objectForKey:@"Value"];
        if (![value isKindOfClass:[NSAppleEventDescriptor class]])
            break;

        NSAppleEventDescriptor *event = value;
        if ([event descriptorType] != typeType || [event typeCodeValue] != 'msng')
            break;
        
        NSScriptObjectSpecifier *keySpec = [self keySpecifier];
        if (![keySpec isKindOfClass:[NSPropertySpecifier class]]) {
            OBASSERT_NOT_REACHED("Expected a property specifier; what did we get?");
            break;
        }
        
        NSArray *objects = [self collectFlattenedObjectsFromArguments:[self receiversSpecifier] requiringClass:Nil];
        [objects setValue:nil forKey:[keySpec key]];
        return nil;
    } while (NO);
    
    return originalPerformDefaultImplementation(self, _cmd);
}

@end
