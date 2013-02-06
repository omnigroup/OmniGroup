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

@implementation OFSubjectTargettingScriptCommand

// Syntax looks like "select Object1" or "select {Object1,Object2}".  In the first case the object will be both the receiver and the direct parameter and in the second case there will be no receiver and the direct parameter will be the list of object specifiers.  Note that the objects can be of different types (or in different documents!).  We'll try to handle as much of this as possible.  Also note that for the single object form to work, the object must claim to support the command.

- (id)executeCommand;
{
    // If this gets called on a list of objects, Cocoa scripting would send it to the application.  If it gets called on a single object, it'd be called on the class that handles it.  We want to call it on the subject all the time.
    // If the subject specifier is nil, then maybe we are getting called like:
    /*
        tell app "MyApp"
           cmd SomeThing
        end
     */
    // and we can leave the receiver specifier alone.
    NSScriptObjectSpecifier *specifier = [self subjectSpecifier];
    if (specifier == nil) {
        // 10.4 gets this in some cases.  In particular, when Mail invokes the OmniFocus mail action script the 'parse tasks' gets a '----' instead of 'subj'.  Inexplicably.  10.5 gets the 'subj'.
        specifier = [self directParameterSpecifier];
    }
    
    if (specifier != nil) {
        [self setReceiversSpecifier:specifier];
    }

    return [super executeCommand];
}

- (id)performDefaultImplementation;
{
    OBASSERT_NOT_REACHED("Expected command to be dispatched to subject.");
    [self setScriptErrorNumber:errAEEventNotHandled];
    return nil;
}

@end
