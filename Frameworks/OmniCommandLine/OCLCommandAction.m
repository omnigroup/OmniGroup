// Copyright 2012-2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OCLCommandAction.h"

#import "OCLCommandArgument.h"

#import <OmniFoundation/NSException-OFExtensions.h>

RCS_ID("$Id$")

@implementation OCLCommandAction
{
    NSArray *_requiredArguments;
    NSDictionary *_optionalArgumentsByName;
}

- initWithSpecification:(NSString *)specification action:(void (^)(void))action;
{
    if (!(self = [super init]))
        return nil;
    
    // Documentation is at the end, prefixed by a a '#'
    if ([specification containsString:@"#"]) {
        NSArray *specs = [specification componentsSeparatedByString:@"#"];
        if ([specs count] != 2)
            [NSException raise:NSInvalidArgumentException format:@"Specification \"%@\" contains more than one documentation string", specification];
        _documentation = [[specs objectAtIndex:1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        specification = [[specs objectAtIndex:0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    }
    
    NSMutableArray *specs = [[specification componentsSeparatedByString:@" "] mutableCopy];
    if ([specs count] == 0)
        [NSException raise:NSInvalidArgumentException format:@"Specification \"%@\" must at least contain a name", specification];

    _action = [action copy];
    
    _name = [[specs objectAtIndex:0] copy];
    [specs removeObjectAtIndex:0];
    
    NSMutableArray *requiredArguments = [[NSMutableArray alloc] init];
    NSMutableDictionary *optionalArgumentsByName = [[NSMutableDictionary alloc] init];
    NSMutableDictionary *argumentByName = [[NSMutableDictionary alloc] init];
    for (NSString *spec in specs) {
        OCLCommandArgument *argument = [[OCLCommandArgument alloc] initWithSpecification:spec];
        if ([argumentByName objectForKey:argument.name])
            [NSException raise:NSInvalidArgumentException format:@"Specification \"%@\" has duplicate argument names", specification];
        
        argumentByName[argument.name] = argument;
        
        if (argument.optional)
            optionalArgumentsByName[argument.name] = argument;
        else
            [requiredArguments addObject:argument];
    }
    
    _requiredArguments = [requiredArguments copy];
    _optionalArgumentsByName = [optionalArgumentsByName copy];
    
    return self;
}

@synthesize name = _name;
@synthesize action = _action;

- (NSDictionary *)parseArgumentStrings:(NSArray *)argumentStrings;
{
    NSMutableDictionary *argumentValues = [NSMutableDictionary dictionary];
    
    NSUInteger requiredArgumentIndex = 0, requiredArgumentCount = [_requiredArguments count];
    NSUInteger argumentStringCount = [argumentStrings count];
    for (NSUInteger argumentStringIndex = 0; argumentStringIndex < argumentStringCount; argumentStringIndex++) {
        NSString *argumentString = argumentStrings[argumentStringIndex];
        OCLCommandArgument *argument;
        id value;
        
        if ([argumentString hasPrefix:@"--"]) {
            argument = _optionalArgumentsByName[[argumentString stringByRemovingPrefix:@"--"]];
            if (!argument)
                [NSException raise:NSInvalidArgumentException format:@"\"%@\" is not a valid argument", argumentString]; // TODO: Do a 'usage' thing.

            argumentStringIndex++;
            if (argumentStringIndex >= argumentStringCount)
                [NSException raise:NSInvalidArgumentException format:@"\"%@\" requires an argument", argumentString]; // TODO: Do a 'usage' thing.
            
            argumentString = argumentStrings[argumentStringIndex];
        } else {
            if (requiredArgumentIndex >= requiredArgumentCount)
                [NSException raise:NSInvalidArgumentException reason:@"Too many arguments"];

            argument = _requiredArguments[requiredArgumentIndex];
            requiredArgumentIndex++;
        }
        
        value = [argument valueForString:argumentString];
        
        if (argumentValues[argument.name])
            [NSException raise:NSInvalidArgumentException format:@"Argument \"%@\" already specified", argument.name]; // TODO: Later add a spec that allows 'array of'
        
        argumentValues[argument.name] = value;
    }
    
    if (requiredArgumentIndex != requiredArgumentCount) {
        [NSException raise:NSInvalidArgumentException reason:@"Not enough arguments given."];
    }
    
    return argumentValues;
}

- (NSString *)argumentsUsageDescription;
{
    NSMutableArray *argumentDescriptions = [NSMutableArray array];
    
    [_requiredArguments enumerateObjectsUsingBlock:^(OCLCommandArgument *argument, NSUInteger idx, BOOL *stop){
        [argumentDescriptions addObject:argument.usageDescription];
    }];
    [_optionalArgumentsByName enumerateKeysAndObjectsUsingBlock:^(NSString *name, OCLCommandArgument *argument, BOOL *stop){
        [argumentDescriptions addObject:argument.usageDescription];
    }];
    
    return [argumentDescriptions componentsJoinedByString:@" "];
}

@end
