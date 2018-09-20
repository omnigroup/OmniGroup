// Copyright 2006-2018 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Carbon/Carbon.h>

#import <Foundation/NSScriptCommandDescription.h>
#import <Foundation/NSScriptObjectSpecifiers.h>
#import <OmniBase/NSError-OBExtensions.h>
#import <OmniFoundation/NSScriptCommand-OFExtensions.h>
#import <OmniFoundation/NSScriptObjectSpecifier-OFExtensions.h>

#import <OmniFoundation/OFSubjectTargettingScriptCommand.h>

RCS_ID("$Id$");

@implementation NSScriptCommand (OFExtensions)

+ (Class)requireObjectsInArray:(NSArray *)objects toAllHaveSameClassfromClasses:(Class)cls1, ... NS_REQUIRES_NIL_TERMINATION;
{
    va_list args;
    va_start(args, cls1);
    
    Class cls = cls1;
    while (cls) {
        BOOL allSame = YES;
        for (id object in objects) {
            if (![object isKindOfClass:cls]) {
                allSame = NO;
                break;
            }
        }
        if (allSame) {
            va_end(args);
            return cls;
        } else {
            cls = va_arg(args, Class);
        }
    }
    
    va_end(args);
    return Nil;
}

- (NSScriptObjectSpecifier *)directParameterSpecifier;
{
    NSAppleEventDescriptor *descriptor = [[self appleEvent] attributeDescriptorForKeyword:keyDirectObject];
    if (descriptor != nil && [descriptor descriptorType] != typeNull) {
        NSScriptObjectSpecifier *specifier = [NSScriptObjectSpecifier objectSpecifierWithDescriptor:descriptor];
        OBASSERT_NOTNULL(specifier);
        return specifier;
    }
    
    return nil;
}

- (NSScriptObjectSpecifier *)subjectSpecifier;
{
    NSAppleEventDescriptor *descriptor = [[self appleEvent] attributeDescriptorForKeyword:keySubjectAttr];
    if (descriptor != nil && [descriptor descriptorType] != typeNull) {
        NSScriptObjectSpecifier *specifier = [NSScriptObjectSpecifier objectSpecifierWithDescriptor:descriptor];
        OBASSERT_NOTNULL(specifier);
        return specifier;
    }
    
    return nil;
}

- (id)evaluatedSubjects;
{
    return [[self subjectSpecifier] objectsByEvaluatingSpecifier];
}

- (void)setScriptError:(NSError *)error;
{
    OBPRECONDITION(error != nil); // why are you calling this if there is no error?
    OBPRECONDITION([error code] != NSNoScriptError); // a zero error code means no error, so that'll result in no error in the caller
    OBPRECONDITION(![NSString isEmptyString:[error localizedDescription]]); // messages are good.
    
#if 1 && defined(DEBUG)
    NSLog(@"Script command %@ resulted in error %@", self, [error toPropertyList]);
#endif

    // NSError returns NSInteger, but AppleScript wants int.
    NSInteger code = [error code];
    OBASSERT(code <= INT_MAX);
    OBASSERT(code >= INT_MIN);
    
    [self setScriptErrorNumber:(int)code];
    [self setScriptErrorString:[error localizedDescription]];
}

static BOOL _checkObjectClass(NSScriptCommand *self, id object, Class cls)
{
    if (!cls || [object isKindOfClass:cls])
        return YES;
    
    [self setScriptErrorNumber:NSArgumentsWrongScriptError];
    [self setScriptErrorString:[NSString stringWithFormat:@"The '%@' command requires a list of %@, but was passed a %@", [[self commandDescription] commandName], NSStringFromClass(cls), NSStringFromClass([object class])]];
    return NO;
}

// On return, if outArraySpecified is non NULL, is informs the caller whether the arguments tried to specify one object or more than one.  An index specifier would result in a single object always, but if you do a whose, or even a range specifier *outArraySpecified will be YES (even if only zero or one object is matched).
- (NSArray *)collectFlattenedObjectsFromArguments:(id)arguments requiringClass:(Class)cls arraySpecified:(BOOL *)outArraySpecified;
{
    // This can happen, at least on 10.9, if we do something like "remove every row from selected rows". The -directParameter will be a specifier while the -directParameterSpecifier will be nil. That seems like a bug, but lets handle it...
    if ([arguments isKindOfClass:[NSScriptObjectSpecifier class]]) {
        NSScriptObjectSpecifier *argumentSpecifier = arguments;
        
#if 1
        // Maybe the OO issue was due to the subject targetting command? With the version below, OmniFocus fails to evaluate (every inbox task whose name is "a") correctly, returning an empty array instead of failure (so we'd never try the other version).
        if ([self isKindOfClass:[OFSubjectTargettingScriptCommand class]] || [self isKindOfClass:[OFSubjectTargettingDeleteCommand class]]) {
            id receiver = [[self receiversSpecifier] objectsByEvaluatingSpecifier];
            arguments = [argumentSpecifier objectsByEvaluatingWithContainers:receiver];
            
            if (!arguments) {
                // We sometimes get a fully qualified argument specifier that doesn't like being evaluated with a receiver.
                [argumentSpecifier resetEvaluationError];
                arguments = [argumentSpecifier objectsByEvaluatingSpecifier];
            }
        } else {
            // Trying to get rid of the subject targetting nonsense. It can spuriously "work" when doing something like "every tree of tree "foo" of content of ..." and end up skipping the inner tree "foo" component.
            id receiver = [[self receiversSpecifier] objectsByEvaluatingSpecifier];
            arguments = [argumentSpecifier objectsByEvaluatingSpecifier];

            // In 10.13.6, and probably earlier, we can get an empty array with the argument specifier having an evaluation error, so we can't just check for arguments == nil
            if (!arguments || ([arguments isKindOfClass:[NSArray class]] && [arguments count] == 0 && [argumentSpecifier evaluationErrorNumber] == NSUnknownKeySpecifierError)) {
                [argumentSpecifier resetEvaluationError]; // Otherwise it won't try again.
                arguments = [argumentSpecifier objectsByEvaluatingWithContainers:receiver];
            }
        }
#else
        // Try resolving this directly -- it might have a full path back to the application. If we naively pass the receiver to -objectsByEvaluatingWithContainers:, then 'row 1' can end up evaluating against itself (so you get row 1.1 in the document).
        // BUT, if we wait to resolve the receiver until after we've failed to resolve the arguments, resolving the receiver will return nil when it wouldn't have otherwise. Terrible.
        id receiver = [[self receiversSpecifier] objectsByEvaluatingSpecifier];
        arguments = [argumentSpecifier objectsByEvaluatingSpecifier];
        if (!arguments) {
            [argumentSpecifier resetEvaluationError]; // Otherwise it won't try again.
            arguments = [argumentSpecifier objectsByEvaluatingWithContainers:receiver];
        }
#endif
    }

    if (!arguments) {
        [self setScriptErrorNumber:NSRequiredArgumentsMissingScriptError];
        [self setScriptErrorString:[NSString stringWithFormat:@"The '%@' command requires a list of %@, but was passed nothing", [[self commandDescription] commandName], NSStringFromClass(cls)]];
        return nil;
    }
    
    BOOL arraySpecified = NO;
    
    if (![arguments isKindOfClass:[NSArray class]])
        arguments = [NSArray arrayWithObject:arguments];
    else
        arraySpecified = YES; // Multiple inputs results in an array output even if the lone entry in the input is a single index specifier.
    
    NSScriptObjectSpecifier *receiversSpecifier = [self receiversSpecifier];
    id receiver = [self evaluatedReceivers];
    
    // Collect the flattened list of objects to operate on.  The input specifiers can be things like 'every row' which will return an array when evaluated.
    NSMutableArray *collectedObjects = [NSMutableArray array];
    for (id argument in arguments) {
        // Handle this before we convert argument to an array unconditionally.
        if ([argument isKindOfClass:[NSArray class]])
            arraySpecified = YES;

        if ([argument isKindOfClass:[NSScriptObjectSpecifier class]]) {
            arraySpecified |= ![argument specifiesSingleObject];
            
	    /*
	     The container specifier can be nil if we are doing something like:
	     
	     tell application "OmniOutliner Professional"
                 tell front document
                     move ( columns 3 through 4 ) to beginning of columns
                 end tell
	     end tell
             
	     In this case, we need to supply the container.  But, if we get an argument
	     that has a container, we cannot pass the receiver to -objectsByEvaluatingWithContainers:
	     since if it isn't the actual container, we'll get nil!   For example:
	     
	     tell application "OmniOutliner Professional"
                 tell front document
                     move {column 3, column 4} to beginning of columns
                 end tell
	     end tell
	     
	     Also, we can't evaluate an object with itself as the container.  For example, documents are top
	     level objects and so they have no container.  So, doing:
	     
             expandAll MyDoc
	     
	     should just be evaluated with -objectsByEvaluatingSpecifier.
	     */
	    id result;
	    if ([argument containerSpecifier] || [argument isEqual:receiversSpecifier])
		result = [argument objectsByEvaluatingSpecifier];
	    else
		result = [argument objectsByEvaluatingWithContainers:receiver];
	    
            if (!result) {
                //NSLog(@"Unable to resolve object specifier '%@' for command %@", argument, self);
                [self setScriptErrorNumber:NSArgumentEvaluationScriptError];
                [self setScriptErrorString:[NSString stringWithFormat:@"The '%@' command was unable to locate the indicated object.", [[self commandDescription] commandName]]];
                return nil;
            }
	    argument = result;
        }
	
        if ([argument isKindOfClass:[NSArray class]]) {
            arraySpecified = YES;
	    NSUInteger elementIndex = [argument count];
	    while (elementIndex--) {
		if (!_checkObjectClass(self, [argument objectAtIndex:elementIndex], cls))
                    return nil;
            }
	    [collectedObjects addObjectsFromArray:argument];
	} else {
	    if (!_checkObjectClass(self, argument, cls))
                return nil;
            [collectedObjects addObject:argument];
	}
    }
    
    if (outArraySpecified)
        *outArraySpecified = arraySpecified;
    
    return collectedObjects;
}

- (NSArray *)collectFlattenedObjectsFromArguments:(id)arguments requiringClass:(Class)cls;
{
    return [self collectFlattenedObjectsFromArguments:arguments requiringClass:cls arraySpecified:NULL];
}

- (NSArray *)collectFlattenedParametersRequiringClass:(Class)cls;
{
    return [self collectFlattenedObjectsFromArguments:[self directParameter] requiringClass:cls];
}

@end
