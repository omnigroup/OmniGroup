// Copyright 2014-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIAppController.h>

@interface OUIAppController (OUISpecialURLHandling)

/*!
 Provide another type of special URL command for handling and invocation. Calling this method maps the path in a special URL (e.g. the "/debug" in "omnifocus:///debug?...") to a strategy for invoking that URL on an application, encapsulated inside a command class (e.g. the OmniFocus class DebugURLAlertCommand).
 
 @param cls The class to use when invoking a special URL containing the given path. Must be a subclass of OUISpecialURLCommand.
 @param specialURLPath The path component of special URLs that can be invoked using the given class. Must include the leading forward slash – provide @"/debug", not @"debug".
 */
+ (void)registerCommandClass:(Class)cls forSpecialURLPath:(NSString *)specialURLPath NS_EXTENSION_UNAVAILABLE_IOS("Special URL handling is not available in extensions");

/// Determine whether the given URL is a "special" URL that can be handled by -handleSpecialURL:senderBundleIdentifier:. In order to be considered special, the URL must have a scheme handled by this app and a path earlier registered using +registerCommandClass:forSpecialURLPath:.
- (BOOL)isSpecialURL:(NSURL *)url NS_EXTENSION_UNAVAILABLE_IOS("Special URL handling is not available in extensions");

/*!
 Confirm and invoke the given special URL using a command class earlier registered with OUIAppController. This method prompts the user to confirm that they meant to enter the given URL and perform its associated action, then runs that action against the current application.
 
 @param url The special URL to handle. This URL must have a path component matching a string earlier registered with OUIAppController using +registerCommandClass:forSpecialURLPath:.
 @return Whether the URL was handled by the special URL system. A return value of YES simply means that a corresponding command was found and invoked for the given URL; it does not necessarily mean that the command succeeded.
 */
- (BOOL)handleSpecialURL:(NSURL *)url senderBundleIdentifier:(NSString *)senderBundleIdentifier NS_EXTENSION_UNAVAILABLE_IOS("Special URL handling is not available in extensions") NS_DEPRECATED_IOS(13_0, 13_0, "Use -handleSpecialURL:senderBundleIdentifier:presentingFromViewController: instead.");

/// The view controller to use as the presenter if the invocation or confirmation of a special URL command requires presenting another view controller. The default implementation searches for the current topmost presented view controller from the main window's root; subclasses can override to provide a different view controller from which to present.
@property (nonatomic, readonly) UIViewController *viewControllerForSpecialURLHandlingPresentation NS_EXTENSION_UNAVAILABLE_IOS("Special URL handling is not available in extensions") NS_DEPRECATED_IOS(13_0, 13_0, "The singleton app controller cannot know the correct presentation source in a multi-scene context.");

- (BOOL)handleSpecialURL:(NSURL *)url senderBundleIdentifier:(NSString *)senderBundleIdentifier presentingFromViewController:(UIViewController *)controller;

@end

/*!
 Abstract class providing an interface for invoking commands on behalf of a special URL. Applications can subclass OUISpecialURLCommand to handle specific command types, such as running a debug command or changing an app-specific setting.
 
 Each subclass must be capable of handling any URL with a certain path; a hypothetical debug command class, for example, would need to handle any URL with the path "/debug". After subclassing, applications should register their classes and associated paths with OUIAppController using +registerCommandClass:forSpecialURLPath:.
 */
@interface OUISpecialURLCommand : NSObject

/// The URL causing this command to be invoked. This is generally a copy of the URL passed to -initWithURL:.
@property (nonatomic, readonly) NSURL *url;

@property (nonatomic, readonly) NSString *senderBundleIdentifier;

@property (nonatomic, strong) UIViewController *viewControllerForPresentation;

/// Create a new command for invocation on behalf of the given URL. Override this method to do any command-specific setup or URL parsing.
- (id)initWithURL:(NSURL *)url senderBundleIdentifier:(NSString *)senderBundleIdentifier NS_DESIGNATED_INITIALIZER;

/// A human-readable description of this command. By default, this method returns the original URL's query string; override to provide a more accessible description. The string returned from this method is used in the command's confirmation sheet shown from +confirmAndInvokeSpecialURL:withStyle:fromController:.
- (NSString *)commandDescription;

/// Whether this command can be run without explicit user confirmation. The default value is NO, requiring that the handling machinery present an action sheet to the user requesting permission to invoke the command; subclasses can override to return YES if the URL should be run immediately without confirmation. (Note that your subclass should only do this in rare circumstances.)
@property (nonatomic, readonly) BOOL skipsConfirmation;

/// A human-readable, localized message asking for permission to invoke this command. By default, this method returns a string incorporating the -commandDescription. Subclasses can override this method to replace the entire confirmation message with something more application- or command-specific.
- (NSString *)confirmationMessage;

/// The localized title for the button that will confirm this command's invocation. By default, this method returns the localized version of the string "Invoke".
- (NSString *)confirmButtonTitle;

/*!
 Run this command. You should generally not call this method yourself; instead, the UIAlertController presented to the user will invoke a command instance when the user confirms their intent to run that command.
 
 Instead, you must subclass this method to perform whatever command the original URL specified. Do not call super in your implementation.
 */
- (void)invoke;

@end
