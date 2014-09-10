// Copyright 2014 Omni Development. Inc. All rights reserved.
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
 
 The command executed is derived from the query string in the URL (or, if no query exists, the resource specifier). This string is converted to a camel-case equivalent, then prefixed with the string "command_" and executed as a selector on this class. For example, the OmniGraffle URL omnigraffle:///debug?clear-preview-cache would eventually invoke a selector -command_ClearPreviewCache. If no matching selector for a URL is found, this command does nothing.
 
 To provide custom commands in an application, simply define a method with the appropriate name and signature. Debug commands should return BOOL (whether their debug operation succeeded or failed) and take no arguments. They must be of the form -command_CamelCaseDebugString. Generally, you should consider providing a category on OUIDebugURLCommand to define these methods instead of subclassing further; overriding this class's implementation of -invoke is especially discouraged.
 */
@interface OUIDebugURLCommand : OUISpecialURLCommand

/// Debug command parameters extracted from the original URL for this command. Your custom command_ methods may make use of these parameters to further fine-tune their behavior.
- (NSArray *)parameters;

@end

@interface OUIDebugURLCommand (OUIOptionalMethods)

/// If implemented, called immediately before the invocation of this command forces the app to exit. Provide an implementation of this method alongside your custom command selectors in a category on OUIDebugURLCommand if you need to perform some action after the debug command was invoked, but before the app exits.
- (void)prepareForTermination;

@end
