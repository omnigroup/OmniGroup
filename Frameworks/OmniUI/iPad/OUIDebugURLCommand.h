// Copyright 2014-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniUI/OUIAppController+SpecialURLHandling.h>

/*!
 Concrete special URL command handler for debug URLs (of the form <app name>:///debug?<command>). When invoked, this command prompts for confirmation as usual, but then executes a command and forces the app to quit immediately.
 
 The command executed is derived from the query string in the URL (or, if no query exists, the resource specifier). The string is converted to a camel-case equivalent and then the command can take on one of the following forms:
 
    * Deferred completion:

        Camel-cased command is transformed into "command_%@_completionHandler:". The completion handler takes on the following signature: ^void (BOOL success).
 
        To provide this type of command in an application, simply define a method with the appropriate name and signature and a return type of void.
 
        Note: This takes precedence if both formats are implemented.

    * Immediate completion:

        Camel-cased command is prefixed with the string "command_" and executed as a selector on this class.

        To provide this type of command in an application, simply define a method with the appropriate name and signature and a return type of BOOL.

 For example, the OmniGraffle URL omnigraffle:///debug?clear-preview-cache would invoke a selector -command_ClearPreviewCache_completionHandler: and failing that -command_ClearPreviewCache. If no matching selector for a URL is found, this command does nothing.

 Generally, you should consider providing a category on OUIDebugURLCommand to define these methods instead of subclassing further; overriding this class's implementation of -invoke is especially discouraged.

 */
@interface OUIDebugURLCommand : OUISpecialURLCommand

/// Debug command parameters extracted from the original URL for this command. Your custom command_ methods may make use of these parameters to further fine-tune their behavior.
- (NSArray *)parameters;

@end

@interface OUIDebugURLCommand (OUIOptionalMethods)

/// If implemented, called immediately before the invocation of this command forces the app to exit. Provide an implementation of this method alongside your custom command selectors in a category on OUIDebugURLCommand if you need to perform some action after the debug command was invoked, but before the app exits.
- (void)prepareForTermination;

@end
