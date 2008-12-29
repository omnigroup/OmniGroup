// Copyright 2006-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSScriptCommand-OFExtensions.h>

#import <OmniBase/NSError-OBExtensions.h>
#import <OmniFoundation/NSScriptObjectSpecifier-OFExtensions.h>

#import <Foundation/NSScriptCommandDescription.h>
#import <Foundation/NSScriptObjectSpecifiers.h>

RCS_ID("$Id$");

@implementation NSScriptCommand (OFExtensions)

- (void)setError:(NSError *)error;
{
    OBPRECONDITION(error); // why are you calling this if there is no error?
    OBPRECONDITION([error code] != NSNoScriptError); // a zero error code means no error, so that'll result in no error in the caller
    OBPRECONDITION([error localizedDescription] != nil); // messages are good.
    
#if 1 && defined(DEBUG)
    NSLog(@"Script command %@ resulted in error %@", self, [error toPropertyList]);
#endif
    
    [self setScriptErrorNumber:[error code]];
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
    unsigned int argumentIndex, argumentCount = [arguments count];
    for (argumentIndex = 0; argumentIndex < argumentCount; argumentIndex++) {
        id argument = [arguments objectAtIndex:argumentIndex];

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
                NSLog(@"Unable to resolve object specifier '%@' for command %@", argument, self);
                [self setScriptErrorNumber:NSArgumentEvaluationScriptError];
                [self setScriptErrorString:[NSString stringWithFormat:@"The '%@' command was unable to locate the indicated object.", [[self commandDescription] commandName]]];
                return nil;
            }
	    argument = result;
        }
	
        if ([argument isKindOfClass:[NSArray class]]) {
            arraySpecified = YES;
	    unsigned int elementIndex = [argument count];
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
