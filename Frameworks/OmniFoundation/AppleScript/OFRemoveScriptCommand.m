// Copyright 2000-2006 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFRemoveScriptCommand.h>

#import <OmniFoundation/NSObject-OFExtensions.h>
#import <OmniFoundation/NSScriptCommand-OFExtensions.h>

#import <Foundation/NSArray.h>
#import <Foundation/NSBundle.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSException.h>
#import <Foundation/NSScriptObjectSpecifiers.h>
#import <Foundation/NSString.h>

#import <OmniBase/rcsid.h>

RCS_ID("$Id$");

@implementation OFRemoveScriptCommand

/*
 This needs to be defined as -executeCommand instead of -performDefaultImplementation since often the receiver will be unset (if an array is the receiver) and -performDefaultImplementation will just bail in that caase.
 */
- (id)executeCommand;
{
    // If we do 'add every row of MyDoc to selected rows of MyDoc', then the receivers will be an array.  We'll pass this command to the container.
    NSPropertySpecifier *containerSpec = [[self arguments] objectForKey:@"FromContainer"];
    if (!containerSpec) {
        NSLog(@"Command has no 'FromContainer' -- %@", self);
        [self setScriptErrorNumber:NSRequiredArgumentsMissingScriptError];
        [self setScriptErrorString:NSLocalizedStringFromTableInBundle(@"Remove command missing the required 'from' specifier.", @"OmniFoundation", [OFRemoveScriptCommand bundle], @"script exception format")];
        return nil;
    }
    if (![containerSpec isKindOfClass:[NSPropertySpecifier class]]) {
        NSLog(@"Command's 'FromContainer' is not a NSPropertySpecifier -- %@", containerSpec);
        [self setScriptErrorNumber:NSArgumentsWrongScriptError];
        [self setScriptErrorString:NSLocalizedStringFromTableInBundle(@"Remove command has invalid 'from' specifier.", @"OmniFoundation", [OFRemoveScriptCommand bundle], @"script exception format")];
        return nil;
    }

    NSArray *evaluatedParameters = [self collectFlattenedParametersRequiringClass:Nil];
    if (!evaluatedParameters) {
        // Error information is already set
        OBASSERT([self scriptErrorNumber] != NSNoScriptError);
        return nil;
    }

    NSString *key = [containerSpec key];
    id container = [[containerSpec containerSpecifier] objectsByEvaluatingSpecifier];
    if (![container respondsToSelector:@selector(removeObjects:fromPropertyWithKey:)]) {
        NSLog(@"Container doesn't respond to -removeObjects:toPropertyWithKey: -- container = %@", OBShortObjectDescription(container));
        [self setScriptErrorNumber:NSReceiversCantHandleCommandScriptError];
        [self setScriptErrorString:NSLocalizedStringFromTableInBundle(@"Specified container doesn't handle the remove command.", @"OmniFoundation", [OFRemoveScriptCommand bundle], @"script exception format")];
        return nil;
    }

    [container removeObjects:evaluatedParameters fromPropertyWithKey:key];
    return nil;
}

@end
