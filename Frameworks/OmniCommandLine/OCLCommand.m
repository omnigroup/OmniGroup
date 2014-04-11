// Copyright 2008-2012, 2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniCommandLine/OCLCommand.h>

#import "OCLCommandAction.h"
#import "OCLCommandArgument.h"

#import <OmniFoundation/NSException-OFExtensions.h>

RCS_ID("$Id$");

static void OCLCommandLogv(NSString *format, va_list args, BOOL addNewlineIfMissing)
{
    CFStringRef str = CFStringCreateWithFormatAndArguments(kCFAllocatorDefault, NULL/*formatOptions*/, (CFStringRef)format, args);
    BOOL addNewline = NO;
    if (addNewlineIfMissing) {
        CFIndex length = CFStringGetLength(str);
        if (length == 0 || CFStringGetCharacterAtIndex(str, length - 1) != '\n')
            addNewline = YES;
    }
    
    CFDataRef data = CFStringCreateExternalRepresentation(kCFAllocatorDefault, str, kCFStringEncodingUTF8, 0/*lossByte*/);
    CFRelease(str);
    
    fwrite(CFDataGetBytePtr(data), 1, CFDataGetLength(data), stderr);
    if (addNewline)
        fputc('\n', stderr);
    
    CFRelease(data);
    fflush(stderr);
}

void OCLCommandLog(NSString *format, ...)
{
    va_list args;
    va_start(args, format);
    OCLCommandLogv(format, args, NO/*add newline if missing*/);
    va_end(args);
}


@implementation OCLCommand
{
    NSMutableDictionary *_rootGroup;
    NSMutableDictionary *_currentGroup;
    
    NSDictionary *_argumentValues;
}

+ (instancetype)command;
{
    return [[self alloc] init];
}

- init;
{
    if (!(self = [super init]))
        return nil;
    
    _rootGroup = [[NSMutableDictionary alloc] init];
    _currentGroup = _rootGroup;
    
    __weak OCLCommand *cmd = self;
    [cmd add:@"help # Prints this documentation" with:^{
        [cmd usage];
    }];
    
    return self;
}

- (void)group:(NSString *)name with:(void (^)(void))addCommands;
{
    NSMutableDictionary *previousGroup = _currentGroup;

    _currentGroup = [[NSMutableDictionary alloc] init];
    OBASSERT(previousGroup[name] == nil);
    previousGroup[name] = _currentGroup;
    
    addCommands();
    
    _currentGroup = previousGroup;
}

- (void)add:(NSString *)specification with:(void (^)(void))handleCommand;
{
    OCLCommandAction *action = [[OCLCommandAction alloc] initWithSpecification:specification action:handleCommand];
    if (_currentGroup[action.name])
        [NSException raise:NSInvalidArgumentException format:@"Already registered a command with the name \"%@\"", action.name];
    _currentGroup[action.name] = action;
}

- (void)usage;
{
    NSMutableArray *actionDescriptions = [NSMutableArray array];
    
    OCLCommandLog(@"%@ supports the following commands:\n\n", [[NSProcessInfo processInfo] processName]);
    
    NSMutableArray *actionStack = [NSMutableArray array];
    [self _addActionDescriptions:actionDescriptions group:_rootGroup actionStack:actionStack];
    
    [actionDescriptions sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *actionDescription in actionDescriptions)
        OCLCommandLog(@"%@\n\n", actionDescription);
}

- (void)_addActionDescriptions:(NSMutableArray *)actionDescriptions group:(NSDictionary *)group actionStack:(NSMutableArray *)actionStack;
{
    [group enumerateKeysAndObjectsUsingBlock:^(NSString *key, id entry, BOOL *stop) {
        if ([entry isKindOfClass:[OCLCommandAction class]]) {
            OCLCommandAction *action = entry;
            
            NSMutableString *actionDescription = [NSMutableString stringWithFormat:@"\t%@", [[actionStack arrayByAddingObject:key] componentsJoinedByString:@" "]];
            
            NSString *argumentUsage = [action argumentsUsageDescription];
            if (![NSString isEmptyString:argumentUsage])
                [actionDescription appendFormat:@" %@", argumentUsage];
            
            NSString *documentation = action.documentation;
            if (![NSString isEmptyString:documentation])
                [actionDescription appendFormat:@"\n\t\t%@", documentation];
            
            [actionDescriptions addObject:actionDescription];
        } else {
            OBASSERT([entry isKindOfClass:[NSDictionary class]]);
            [actionStack addObject:key];
            [self _addActionDescriptions:actionDescriptions group:entry actionStack:actionStack];
            [actionStack removeLastObject];
        }
    }];
}

- (void)error:(NSString *)format, ...;
{
    va_list args;
    va_start(args, format);
    OCLCommandLogv(format, args, YES/*add newline if missing*/);
    va_end(args);
    exit(1);
}

- (void)runWithArguments:(NSArray *)argumentStrings;
{
    NSMutableArray *remainingArguments = [argumentStrings mutableCopy];
    NSDictionary *group = _rootGroup;
    
    while (YES) {
        if ([remainingArguments count] == 0)
            [NSException raise:NSInvalidArgumentException reason:@"No action specified"];

        NSString *argument = remainingArguments[0];
        [remainingArguments removeObjectAtIndex:0];
        
        id entry = group[argument];
        
        if (!entry)
            [NSException raise:NSInvalidArgumentException format:@"No such action \"%@\"", argument];
        
        if ([entry isKindOfClass:[OCLCommandAction class]]) {
            OCLCommandAction *action = entry;
            _argumentValues = [[action parseArgumentStrings:remainingArguments] copy];
            //NSLog(@"Invoking action with %@", _argumentValues);
            action.action();
            return;
        }
        
        OBASSERT([entry isKindOfClass:[NSDictionary class]]);
        group = entry;
    }
}

#pragma mark - Argument lookup

- (id)objectForKeyedSubscript:(id)key;
{
    return _argumentValues[key];
}

@end
