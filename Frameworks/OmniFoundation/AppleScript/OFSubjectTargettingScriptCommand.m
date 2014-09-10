// Copyright 2007-2014 Omni Development, Inc. All rights reserved.
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
     -- receiver specifier set to row, goes to row, no subject specifier set
     
     select {row 1, row 2}
     -- no receiver specifier set, but subject specifier is
     
     select every row
     -- receiver specifier will resolve to array of rows, command invoked on *each* row
     
     select {project 1} -- in OmniFocus
     -- receiver set to the project and subject is the correct receiver. In this case, we can't peel off a layer and talk to the container since that is the document, but we need to target the subject (the sidebar or container tree) since the same object can be selected in two spots (so 'document' shouldn't chose).
     
     select {}
     -- no receiver specifier set, but subject specifier is
     
     In the 0 and many {...} cases, Cocoa scripting will not fill out the receivers specifier at all and will get confused, but it *will* have a subject specifier (the target of the parent tell block). On the 1 case of {...} it will fill out the receiver.
     
     In the 'every row' case, we don't really want the command sent to each object in the general case. For example, if we have a 'extending' option like the 'select' command in OmniOutliner, we want "select every row without extending" to clear the previous selection and then select "every row" w/in the parent document or row. Instead, it would call "select" on each row one at a time and clear the selection from the previous row (leaving you with just one row selected).
     
     With this, subclasses/handlers of this command should look at the directParameter to figure out what to operate on, likely via -collectFlattenedParametersRequiringClass: or one of its lower-level helpers.
     
     */
    
    /*
     Possible alternative formulations to deal with objects that depend on a subject being the target:
     
     tell sidebar
        set MyTrees to locate {Project1} -- explicitly transform to tree nodes in the target view
        select MyTrees -- still would have the 'extending' problem
     end
     
     select {...} in sidebar -- explicitly name the container. still would have the 'extending' problem
     
     switch to 'selection' as a property on each container -- would be harder to extend the selection or partially deselect stuff
     
     */
    
#if 0
    NSScriptObjectSpecifier *receiversSpecifier = self.receiversSpecifier;
    if (receiversSpecifier) {
        // Peel back one layer on the receivers to get a potential target. This means that in the case of OmniOutliner, for example, 'select row 1 of row 1' will target the parent row and ask it to select its first child. That seems OK. We could look at the receivers and only do this if it resolves to an array, but it seems easier to have one less path.
        // But note that in some cases (like 'tell sidebar / select project 1 / end' in OmniFocus), the container will be the document, which can't make the choice (since the select could happen in the sidebar or content area). So, we check if the container handles the command before using it.
        NSScriptObjectSpecifier *containerSpecifier = receiversSpecifier.containerSpecifier;
        if (containerSpecifier && [receiversSpecifier.containerClassDescription supportsCommand:self.commandDescription]) {
            self.receiversSpecifier = containerSpecifier;
            return;
        }
    }
    
    NSScriptObjectSpecifier *subjectSpecifier = self.subjectSpecifier;
    if (subjectSpecifier && [subjectSpecifier.keyClassDescription supportsCommand:self.commandDescription]) {
        self.receiversSpecifier = subjectSpecifier;
        return;
    }
    
    OBASSERT_NOT_REACHED("Using default receiver specifier");
#else
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
#endif
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
                return OBSendObjectReturnMessageWithObject(subject, sel, self);
            }
        }
    }
    
    return [super executeCommand];
}

@end
