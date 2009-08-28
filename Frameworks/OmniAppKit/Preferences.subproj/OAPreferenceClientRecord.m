// Copyright 1997-2005, 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OAPreferenceClientRecord.h"

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

#import "NSImage-OAExtensions.h"
#import "OAPreferenceClient.h"
#import "OAPreferenceController.h"

RCS_ID("$Id$")

@implementation OAPreferenceClientRecord

- (id)initWithCategoryName:(NSString *)newName;
{
    if ([super init] == nil)
        return nil;
    categoryName = [newName retain];
    [self setOrdering:nil];
    return self;
}

- (void)dealloc;
{
    [categoryName release];
    [identifier release];
    [className release];
    [title release];
    [shortTitle release];
    [iconName release];
    [nibName release];
    [helpURL release];
    [defaultsDictionary release];
    [defaultsArray release];
    [iconImage release];
    
    [super dealloc];
}


//

static NSString * const OAPreferenceClientRecordIconNameAppPrefix = @"app:"; // For example, you could use "app:com.apple.Mail" to use Mail's icon.

- (NSImage *)iconImage;
{
    if (iconImage != nil)
        return iconImage;

    if ([iconName hasPrefix:OAPreferenceClientRecordIconNameAppPrefix]) {
        NSString *appIdentifier = [iconName stringByRemovingPrefix:OAPreferenceClientRecordIconNameAppPrefix];
        NSString *appPath = [[NSWorkspace sharedWorkspace] absolutePathForAppBundleWithIdentifier:appIdentifier];
        if ([NSString isEmptyString:appPath]) {
            NSLog(@"%s: Cannot find '%@'", __PRETTY_FUNCTION__, appIdentifier);
        } else {
            iconImage = [[[NSWorkspace sharedWorkspace] iconForFile:appPath] retain];
        }
    } else {
        NSBundle *bundle = [OFBundledClass bundleForClassNamed:className];
        iconImage = [[NSImage imageNamed:iconName inBundle:bundle] retain];
    }

#ifdef DEBUG
    if (iconImage == nil)
        NSLog(@"OAPreferenceClientRecord '%@' is missing its icon (%@)", identifier, iconName);
#endif

    return iconImage;
}

- (NSString *)categoryName;
{
    return categoryName;
}

- (NSString *)identifier;
{
    return identifier;
}

- (NSString *)className;
{
    return className;
}

- (NSString *)title;
{
    return title;
}

- (NSString *)shortTitle;
{
    return shortTitle ? shortTitle : title;
}

- (NSString *)iconName;
{
    return iconName;
}

- (NSString *)nibName;
{
    return nibName;
}

- (NSString *)helpURL;
{
    return helpURL;
}

- (NSNumber *)ordering;
{
    OBASSERT(ordering != nil);
    return ordering;
}

- (NSDictionary *)defaultsDictionary;
{
    return defaultsDictionary;
}

- (NSArray *)defaultsArray;
{
    return defaultsArray;
}

- (void)setIdentifier:(NSString *)newIdentifier;
{
    if (identifier == newIdentifier)
        return;
    [identifier release];
    identifier = [newIdentifier retain];
}

- (void)setClassName:(NSString *)newClassName;
{
    if (className == newClassName)
        return;
    [className release];
    className = [newClassName retain];
}

- (void)setTitle:(NSString *)newTitle;
{
    if (title == newTitle)
        return;
    [title release];
    title = [newTitle retain];
}

- (void)setShortTitle:(NSString *)newShortTitle;
{
    if (shortTitle == newShortTitle)
        return;
    [shortTitle release];
    shortTitle = [newShortTitle retain];
}

- (void)setIconName:(NSString *)newIconName;
{
    if (iconName == newIconName)
        return;
    [iconName release];
    iconName = [newIconName retain];
}

- (void)setNibName:(NSString *)newNibName;
{
    if (nibName == newNibName)
        return;
    [nibName release];
    nibName = [newNibName retain];
}

- (void)setHelpURL:(NSString *)newHelpURL;
{
    if (helpURL == newHelpURL)
        return;
    [helpURL release];
    helpURL = [newHelpURL retain];
}

- (void)setOrdering:(NSNumber *)newOrdering;
{
    if (newOrdering == nil)
        newOrdering = [NSNumber numberWithInt:0];
    if (ordering == newOrdering)
        return;
    [ordering release];
    ordering = [newOrdering retain];
}

- (void)setDefaultsDictionary:(NSDictionary *)newDefaultsDictionary;
{
    if (defaultsDictionary == newDefaultsDictionary)
        return;
    [defaultsDictionary release];
    defaultsDictionary = [newDefaultsDictionary retain];
}

- (void)setDefaultsArray:(NSArray *)newDefaultsArray;
{
    if (defaultsArray == newDefaultsArray)
        return;
    [defaultsArray release];
    defaultsArray = [newDefaultsArray retain];
}

- (NSComparisonResult)compare:(OAPreferenceClientRecord *)other;
{
    if (![other isKindOfClass:[self class]])
	return NSOrderedAscending;

    return [[self shortTitle] compare:[other shortTitle]];
}

- (NSComparisonResult)compareOrdering:(OAPreferenceClientRecord *)other;
{
    int result;
    
    if (![other isKindOfClass:[self class]])
	return NSOrderedAscending;

    result = [[self ordering] compare:[other ordering]];
    
    if (result == NSOrderedSame) {
        result = [[self shortTitle] compare:[other shortTitle]];
    }
    
    return result;
}

- (OAPreferenceClient *)newClientInstanceInController:(OAPreferenceController *)controller;
{
    [controller setTitle:[NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Loading %@...", @"OmniAppKit", [OAPreferenceClientRecord bundle], "preference bundle loading message format"), title]];

    Class clientClass = [OFBundledClass classNamed:className];

    // Check for old initializers that are not valid anymore
    OBASSERT(![clientClass instancesRespondToSelector:@selector(initWithTitle:defaultsArray:)]);
    OBASSERT(![clientClass instancesRespondToSelector:@selector(initWithTitle:defaultsArray:defaultKeySuffix:)]);
    
    // This method was replaced by -willBecomeCurrentPreferenceClient (and the -did variant was added)
    OBASSERT(![clientClass instancesRespondToSelector:@selector(becomeCurrentPreferenceClient)]);
	
    OAPreferenceClient *clientInstance =  [[clientClass alloc] initWithPreferenceClientRecord:self controller:controller];

    return clientInstance;
}


//
// Debugging
//

- (NSMutableDictionary *) debugDictionary;
{
    NSMutableDictionary *dict;
    
    dict = [super debugDictionary];
    if (className)
        [dict setObject:className forKey:@"className"];
    if (identifier)
        [dict setObject:identifier forKey:@"identifier"];
    if (title)
        [dict setObject:title forKey:@"title"];
    if (shortTitle)
        [dict setObject:shortTitle forKey:@"shortTitle"];
    if (iconName)
        [dict setObject:iconName forKey:@"iconName"];
    if (nibName)
        [dict setObject:nibName forKey:@"nibName"];
    if (defaultsDictionary)
        [dict setObject:defaultsDictionary forKey:@"defaultsDictionary"];
    if (defaultsArray)
        [dict setObject:defaultsArray forKey:@"defaultsArray"];
    if (iconImage)
        [dict setObject:iconImage forKey:@"iconImage"];
    return dict;
}

@end
