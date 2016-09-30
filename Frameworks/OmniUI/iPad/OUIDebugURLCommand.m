// Copyright 2014-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIDebugURLCommand.h>

RCS_ID("$Id$");

@implementation OUIDebugURLCommand {
@private
    SEL _sel;
    BOOL _hasCompletionHandler;
    NSString *_commandString;
    NSString *_parameterString;
}

- (id)initWithURL:(NSURL *)url;
{
    if (!(self = [super initWithURL:url])) {
        return nil;
    }
    
    NSString *commandAndArguments = nil;
    
    NSString *path = [url path];
    if (path != nil) {
        commandAndArguments = [url query]; // omnifocus:///debug?set-default:EnableSyncDetailsLogging:1
    } else {
        commandAndArguments = [url resourceSpecifier]; // x-omnifocus-debug:set-default:EnableSyncDetailsLogging:1
    }
    
    NSRange parameterRange = [commandAndArguments rangeOfString:@":"];
    if (parameterRange.length > 0) {
        _parameterString = [commandAndArguments substringFromIndex:NSMaxRange(parameterRange)];
        _commandString = [commandAndArguments substringToIndex:parameterRange.location];
    } else {
        _commandString = commandAndArguments;
    }
    
    NSString *camelCommand = [[[_commandString componentsSeparatedByString:@"-"] arrayByPerformingSelector:@selector(capitalizedString)] componentsJoinedByString:@""];
    SEL selectorWithCompletionHandler = NSSelectorFromString([NSString stringWithFormat:@"command_%@_completionHandler:", camelCommand]);
    SEL selectorWithoutCompletionHandler = NSSelectorFromString([NSString stringWithFormat:@"command_%@", camelCommand]);
    if ([self respondsToSelector:selectorWithCompletionHandler]) {
        _hasCompletionHandler = YES;
        _sel = selectorWithCompletionHandler;
    } else if ([self respondsToSelector:selectorWithoutCompletionHandler]) {
        _sel = selectorWithoutCompletionHandler;
    } else {
#ifdef DEBUG
        NSLog(@"%@ does not respond to %@", NSStringFromClass([self class]), NSStringFromSelector(_sel));
#endif
        return nil;
    }

    return self;
}

- (NSArray *)parameters;
{
    NSArray *encodedParameters = [_parameterString componentsSeparatedByString:@":"];
    NSMutableArray *decodedParameters = [NSMutableArray array];
    for (NSString *encodedParameter in encodedParameters) {
        NSString *decodedParameter = [encodedParameter stringByRemovingPercentEncoding];
        [decodedParameters addObject:decodedParameter];
    }
    return decodedParameters;
}

- (NSString *)commandDescription;
{
    if (_parameterString != nil)
        return [NSString stringWithFormat:@"%@:%@", _commandString, _parameterString];
    else
        return _commandString;
}

- (NSString *)confirmationMessage;
{
    NSString *messageFormat = NSLocalizedStringFromTableInBundle(@"You have tapped on a link which will run the following debugging command:\n\n\"%@\"\n\nIf you weren’t instructed to do this by Omni Support Humans, please don’t.\nDo you wish to run this command?", @"OmniUI", OMNI_BUNDLE, @"debug setting alert message");
    NSString *message = [NSString stringWithFormat:messageFormat, [self commandDescription]];
    return message;
}

- (NSString *)confirmButtonTitle;
{
    return NSLocalizedStringFromTableInBundle(@"Invoke and Quit", @"OmniUI", OMNI_BUNDLE, @"button title");
}

- (void)invoke;
{
    typedef void (^InvokeCompletionBlock)(BOOL success);
    InvokeCompletionBlock completionBlock = ^void(BOOL success) {
        if (success) {
            // Successful debug commands quit and require relaunch.  Otherwise, they'd be much harder to implement and test.
            if ([self respondsToSelector:@selector(prepareForTermination)]) {
                [self prepareForTermination];
            }
            
            exit(0);
        } else {
            // Finish starting up if we postponed to handle the DEBUG url
            OUIAppController *controller = [OUIAppController controller];
            controller.shouldPostponeLaunchActions = NO;
        }
    };

    if (_hasCompletionHandler) {
        void (*command)(id self, SEL _cmd, InvokeCompletionBlock completionBlock) = (typeof(command))[self methodForSelector:_sel];
        command(self, _cmd, completionBlock);
    } else {
        BOOL (*command)(id self, SEL _cmd) = (typeof(command))[self methodForSelector:_sel];
        BOOL success = command(self, _cmd);
        completionBlock(success);
    }
}

@end
