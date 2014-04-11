// Copyright 2000-2007, 2010, 2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFAddScriptCommand.h>

#import <OmniFoundation/NSObject-OFExtensions.h>
#import <OmniFoundation/NSScriptCommand-OFExtensions.h>
#import <Foundation/NSScriptObjectSpecifiers.h>

RCS_ID("$Id$");


/*
 This (and OFRemoveScriptCommand) are convenience classes for implementing the 'add' and 'remove' script commands for managing many-to-many relationships.  See TN2106.  These aren't implemented by Cocoa (as of 10.2.8, anyway), but are very useful.
 */

@implementation OFAddScriptCommand

/*
 This needs to be defined as -executeCommand instead of -performDefaultImplementation since often the receiver will be unset (if an array is the receiver) and -performDefaultImplementation will just bail in that caase.
 */
- (id)executeCommand;
{
    // If we do 'add every row of MyDoc to selected rows of MyDoc', then the receivers will be an array.  We'll pass this command to the container.
    NSScriptObjectSpecifier *containerSpec = [[self arguments] objectForKey:@"ToContainer"];
    if (!containerSpec) {
        [self setScriptErrorNumber:NSRequiredArgumentsMissingScriptError];
        [self setScriptErrorString:NSLocalizedStringFromTableInBundle(@"Add command missing the required 'to' specifier.", @"OmniFoundation", [OFAddScriptCommand bundle], @"script exception format")];
        return nil;
    }

    NSArray *evaluatedParameters = [self collectFlattenedParametersRequiringClass:Nil];
    if (!evaluatedParameters) {
        OBASSERT([self scriptErrorNumber] != NSNoScriptError, "Script error should already be set");
        return nil;
    }
    
    if ([containerSpec isKindOfClass:[NSPropertySpecifier class]]) {
        //
        // If we just got a property specifier, then we don't care about the index.
        //
        NSPropertySpecifier *propertySpec = (NSPropertySpecifier *)containerSpec;
        NSString *key = [propertySpec key];
        NSObject <OFAddScriptCommandContainer> *container = [[propertySpec containerSpecifier] objectsByEvaluatingSpecifier];
        if (![container conformsToProtocol:@protocol(OFAddScriptCommandContainer)] ||
            ![container respondsToSelector:@selector(addObjects:toPropertyWithKey:forCommand:)]) {
            NSLog(@"Container doesn't conform to OFAddScriptCommandContainer -- container = %@", OBShortObjectDescription(container));
            [self setScriptErrorNumber:NSReceiversCantHandleCommandScriptError];
            [self setScriptErrorString:NSLocalizedStringFromTableInBundle(@"Specified container doesn't handle the add command.", @"OmniFoundation", [OFAddScriptCommand bundle], @"script exception format")];
            return nil;
        }

        [container addObjects:evaluatedParameters toPropertyWithKey:key forCommand:self];
    } else if ([containerSpec isKindOfClass:[NSPositionalSpecifier class]]) {
        //
        // With a position specifier, the index is important, so we pass that along.
        //
        NSPositionalSpecifier *positionalSpec = (NSPositionalSpecifier *)containerSpec;

        NSObject <OFAddScriptCommandContainer> *insertionContainer = [positionalSpec insertionContainer];
        if (![insertionContainer conformsToProtocol:@protocol(OFAddScriptCommandContainer)] ||
            ![insertionContainer respondsToSelector:@selector(insertObjects:inPropertyWithKey:atIndex:forCommand:)]) {
            NSLog(@"Container doesn't conform to OFAddScriptCommandContainer -- container = %@", OBShortObjectDescription(insertionContainer));
            [self setScriptErrorNumber:NSReceiversCantHandleCommandScriptError];
            [self setScriptErrorString:NSLocalizedStringFromTableInBundle(@"Specified container doesn't handle the add command.", @"OmniFoundation", [OFAddScriptCommand bundle], @"script exception format")];
            return nil;
        }

        if (!insertionContainer) {
            NSLog(@"Unable to resolve insertion container in specifier %@", positionalSpec);
            [self setScriptErrorNumber:NSArgumentEvaluationScriptError];
            [self setScriptErrorString:[NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Unable to resolve insertion container in specifier %@", @"OmniFoundation", [OFAddScriptCommand bundle], @"script exception format"), positionalSpec]];
            return nil;
        }
        
        NSString *insertionKey = [positionalSpec insertionKey];
        if (!insertionKey) {
            NSLog(@"Unable to resolve insertion key in specifier %@", positionalSpec);
            [self setScriptErrorNumber:NSArgumentEvaluationScriptError];
            [self setScriptErrorString:[NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Unable to resolve insertion key in specifier %@", @"OmniFoundation", [OFAddScriptCommand bundle], @"script exception format"), positionalSpec]];
            return nil;
        }
        
        NSInteger insertionIndex = [positionalSpec insertionIndex];
        if (insertionIndex < 0) {
            NSLog(@"Unable to resolve insertion index in specifier %@", positionalSpec);
            [self setScriptErrorNumber:NSArgumentEvaluationScriptError];
            [self setScriptErrorString:[NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Unable to resolve insertion index in specifier %@", @"OmniFoundation", [OFAddScriptCommand bundle], @"script exception format"), positionalSpec]];
            return nil;
        }
        
        [insertionContainer insertObjects:evaluatedParameters inPropertyWithKey:insertionKey atIndex:insertionIndex forCommand:self];
    } else {
        NSLog(@"Command's 'ToContainer' is not a NSPropertySpecifier or NSPositionalSpecifier -- %@", containerSpec);
        [self setScriptErrorNumber:NSArgumentsWrongScriptError];
        [self setScriptErrorString:NSLocalizedStringFromTableInBundle(@"Add command has invalid 'to' specifier.", @"OmniFoundation", [OFAddScriptCommand bundle], @"script exception format")];
        return nil;
    }

    return nil;
}

@end
