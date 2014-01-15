// Copyright 2007-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Carbon/Carbon.h>
#import <Foundation/NSScriptSuiteRegistry.h>

#import <OmniFoundation/NSScriptCommand-OFExtensions.h>
#import <OmniFoundation/OFSubjectTargettingScriptCommand.h>

RCS_ID("$Id$");

@implementation NSScriptCommand (OFSubjectTargetting)

- (void)targetSubject;
{
    /*
     There are several forms of bulk commands that we'd like to handle with direct-parameter style syntax.
     
     select row 1
     -- receiver specifier set to row, goes to row
     
     select {row 1, row 2}
     -- no receiver specifier set, but subject specifier is
     
     select every row
     -- receiver specifier will resolve to array of rows, command invoked on *each* row
     
     select {}
     -- no receiver specifier set, but subject specifier is
     
     In the {...} cases, Cocoa scripting will not fill out the receivers specifier at all and will get confused, but it *will* have a subject specifier (the target of the parent tell block).
     
     In the 'every row' case, we don't really want the command sent to each object in the general case. For example, if we have a 'extending' option like the 'select' command in OmniOutliner, we want "select every row without extending" to clear the previous selection and then select "every row" w/in the parent document or row. Instead, it would call "select" on each row one at a time and clear the selection from the previous row (leaving you with just one row selected).
     
     With this, subclasses/handlers of this command should look at the directParameter to figure out what to operate on, likely via -collectFlattenedParametersRequiringClass: or one of its lower-level helpers.
     
     */
    
    NSScriptObjectSpecifier *receiversSpecifier = self.receiversSpecifier;
    if (receiversSpecifier == nil) {
        NSScriptObjectSpecifier *subjectSpecifier = self.subjectSpecifier;
        OBASSERT(subjectSpecifier);
        self.receiversSpecifier = subjectSpecifier;
    } else {
        // Peel back one layer on the receivers to get a good target. This means that in the case of OmniOutliner, for example, 'select row 1 of row 1' will target the parent row and ask it to select its first child. That seems OK. We could look at the receivers and only do this if it resolves to an array, but it seems easier to have one less path.
        NSScriptObjectSpecifier *containerSpecifier = receiversSpecifier.containerSpecifier;
        if (containerSpecifier)
            self.receiversSpecifier = containerSpecifier;
        else
            OBASSERT_NOT_REACHED("No container for OFSubjectTargettingScriptCommand %@", self);
    }
    
}

@end

@implementation OFSubjectTargettingScriptCommand

- (id)executeCommand;
{
    [self targetSubject];
    return [super executeCommand];
}

- (id)performDefaultImplementation;
{
    OBASSERT_NOT_REACHED("Expected command to be dispatched to subject.");
    [self setScriptErrorNumber:NSReceiversCantHandleCommandScriptError];
    [self setScriptErrorString:@"Receiver did not handle the command."];
    return nil;
}

@end

@implementation OFSubjectTargettingDeleteCommand : NSDeleteCommand

- (id)executeCommand;
{
    // Only need to do this when the direct parameter is a list
    if ([self.directParameter isKindOfClass:[NSArray class]]) {
        id subject = [self.subjectSpecifier objectsByEvaluatingSpecifier];
        if (subject) {
            NSScriptClassDescription *desc = [NSScriptClassDescription classDescriptionForClass:[subject class]];
            SEL sel = [desc selectorForCommand:[self commandDescription]];
            if (sel && [subject respondsToSelector:sel]) {
                [self targetSubject];
                
                // Calling super won't actually invoke the selection for some reason, even though we've changed the receivers specifier to the subject.
                return [subject performSelector:sel withObject:self];
            }
        }
    }
    
    return [super executeCommand];
}

@end
