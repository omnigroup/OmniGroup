// Copyright 2012-2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFSCommandArgument.h"

#import <OmniFoundation/NSString-OFReplacement.h>

RCS_ID("$Id$")

@implementation OFSCommandArgument

+ (instancetype)argumentWithName:(NSString *)name type:(OFSCommandArgumentType)type optional:(BOOL)optional;
{
    return [[self alloc] initWithName:name type:type optional:optional];
}

- (id)initWithName:(NSString *)name type:(OFSCommandArgumentType)type optional:(BOOL)optional;
{
    if (!(self = [super init]))
        return nil;
    
    _name = [name copy];
    _type = type;
    _optional = optional;
    
    return self;
}

- (id)initWithSpecification:(NSString *)specification;
{
    if (!(self = [super init]))
        return nil;
    
    NSArray *components = [specification componentsSeparatedByString:@":"];
    if ([components count] > 2)
        [NSException raise:NSInvalidArgumentException format:@"Specification \"%@\" has more than two components", specification];
    
    NSString *name = [components objectAtIndex:0];
    if ([name hasPrefix:@"--"]) {
        name = [name stringByRemovingPrefix:@"--"];
        _optional = YES;
    }
    _name = [name copy];
    
    NSString *type;
    BOOL explicitType = NO;
    if ([components count] == 2) {
        type = [components objectAtIndex:1];
        explicitType = YES;
    } else
        type = _name;
    
    if ([type isEqual:@"string"])
        _type = OFSCommandArgumentTypeString;
    else if ([type isEqual:@"file"])
        _type = OFSCommandArgumentTypeFile;
    else if ([type isEqual:@"url"])
        _type = OFSCommandArgumentTypeURL;
    else {
        if (explicitType)
            [NSException raise:NSInvalidArgumentException format:@"Specification \"%@\" has unknown type", specification];
        _type = OFSCommandArgumentTypeString; // Allow just specifying "name" to mean string.
    }
        
    return self;
}

@synthesize name = _name;
@synthesize type = _type;
@synthesize optional = _optional;

- (NSString *)usageDescription;
{
    NSString *type;
    switch (_type) {
        case OFSCommandArgumentTypeString:
            type = @"string";
            break;
        case OFSCommandArgumentTypeFile:
            type = @"file";
            break;
        case OFSCommandArgumentTypeURL:
            type = @"url";
            break;
        default:
            [NSException raise:NSInvalidArgumentException format:@"Unknown argument type %d", _type];
    }
    
    if (_optional)
        return [NSString stringWithFormat:@"[--%@ %@]", _name, type];
    if ([_name isEqual:type])
        return _name;
    return [_name stringByAppendingFormat:@":%@", type];
}

- (id)valueForString:(NSString *)string;
{
    id value;
    
    switch (_type) {
        case OFSCommandArgumentTypeString:
            value = string;
            break;
        case OFSCommandArgumentTypeFile:
            value = [NSURL fileURLWithPath:string];
            break;
        case OFSCommandArgumentTypeURL:
            value = [NSURL URLWithString:string];
            break;
        default:
            value = nil;
    }
    
    if (!value)
        [NSException raise:NSInvalidArgumentException format:@"Unable to parse value \"%@\" for the \"%@\" argument", string, _name];
    return value;
}

@end
