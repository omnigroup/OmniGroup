// Copyright 1997-2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OAPreferenceClientRecord.h>

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

#import <OmniAppKit/NSImage-OAExtensions.h>
#import <OmniAppKit/OAPreferenceClient.h>
#import <OmniAppKit/OAPreferenceController.h>

RCS_ID("$Id$")

@implementation OAPreferenceClientRecord

@synthesize iconImage = _iconImage;
@synthesize ordering = _ordering;

#pragma mark - Init

- (instancetype)initWithCategoryName:(NSString *)newName;
{
    if (!(self = [super init]))
        return nil;

    _categoryName = newName;
    [self setOrdering:nil];
    return self;
}

#pragma mark - Accessors

static NSString * const OAPreferenceClientRecordIconNameAppPrefix = @"app:"; // For example, you could use "app:com.apple.Mail" to use Mail's icon.

- (NSImage *)iconImage;
{
    if (_iconImage != nil)
        return _iconImage;

    if ([self.iconName hasPrefix:OAPreferenceClientRecordIconNameAppPrefix]) {
        NSString *appIdentifier = [self.iconName stringByRemovingPrefix:OAPreferenceClientRecordIconNameAppPrefix];
        NSURL *appURL = [[NSWorkspace sharedWorkspace] URLForApplicationWithBundleIdentifier:appIdentifier];
        NSString *appPath = [appURL path];
        if ([NSString isEmptyString:appPath]) {
            NSLog(@"%s: Cannot find '%@'", __PRETTY_FUNCTION__, appIdentifier);
        } else {
            _iconImage = [[NSWorkspace sharedWorkspace] iconForFile:appPath];
        }
    } else {
#ifdef MAC_OS_X_VERSION_10_16
        if (@available(macOS 10.16, *)) {
            _iconImage = [NSImage imageWithSystemSymbolName:self.iconName accessibilityDescription:self.identifier];
        }
#endif
        
        if (_iconImage == nil) {
            NSBundle *bundle = [OFBundledClass bundleForClassNamed:self.className];
            _iconImage = OAImageNamed(self.iconName, bundle);
        }
    }

#ifdef DEBUG
    if (_iconImage == nil)
        NSLog(@"OAPreferenceClientRecord '%@' is missing its icon (%@)", self.identifier, self.iconName);
#endif

    return _iconImage;
}

- (NSString *)shortTitle;
{
    return _shortTitle ? _shortTitle : _title;
}

- (NSNumber *)ordering;
{
    OBASSERT(_ordering != nil);
    return _ordering;
}

- (void)setOrdering:(NSNumber *)newOrdering;
{
    if (newOrdering == nil)
        newOrdering = [NSNumber numberWithInt:0];
    if (_ordering == newOrdering)
        return;
    _ordering = newOrdering;
}

#pragma mark - API

- (NSComparisonResult)compare:(OAPreferenceClientRecord *)other;
{
    if (![other isKindOfClass:[self class]])
	return NSOrderedAscending;

    return [[self shortTitle] compare:[other shortTitle]];
}

- (NSComparisonResult)compareOrdering:(OAPreferenceClientRecord *)other;
{
    if (![other isKindOfClass:[self class]])
	return NSOrderedAscending;

    NSComparisonResult result = [[self ordering] compare:[other ordering]];
    
    if (result == NSOrderedSame)
        result = [[self shortTitle] compare:[other shortTitle]];
    
    return result;
}

- (OAPreferenceClient *)newClientInstanceInController:(OAPreferenceController *)controller;
{
    [controller setTitle:[NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Loading %@...", @"OmniAppKit", [OAPreferenceClientRecord bundle], "preference bundle loading message format"), self.title]];

    Class clientClass = [OFBundledClass classNamed:self.className];

    OAPreferenceClient *clientInstance =  [[clientClass alloc] initWithPreferenceClientRecord:self controller:controller];

    // Check for old initializers that are not valid anymore
    OBASSERT_NOT_IMPLEMENTED(clientInstance, initWithTitle:defaultsArray:);
    OBASSERT_NOT_IMPLEMENTED(clientInstance, initWithTitle:defaultsArray:defaultKeySuffix:);
    
    // This method was replaced by -willBecomeCurrentPreferenceClient (and the -did variant was added)
    OBASSERT_NOT_IMPLEMENTED(clientInstance, becomeCurrentPreferenceClient);

    OBASSERT(clientInstance);
    return clientInstance;
}

#pragma mark - Debugging

- (NSMutableDictionary *) debugDictionary;
{
    NSMutableDictionary *dict = [super debugDictionary];
    [dict setObject:self.categoryName forKey:@"01_categoryName" defaultObject:nil];
    [dict setObject:self.identifier forKey:@"02_identifier" defaultObject:nil];
    [dict setObject:self.className forKey:@"03_className" defaultObject:nil];
    [dict setObject:self.title forKey:@"04_title" defaultObject:nil];
    [dict setObject:self.shortTitle forKey:@"05_shortTitle" defaultObject:nil];
    [dict setObject:self.iconName forKey:@"06_iconName" defaultObject:nil];
    [dict setObject:self.nibName forKey:@"07_nibName" defaultObject:nil];
    [dict setObject:self.helpURL forKey:@"08_helpURL" defaultObject:nil];
    [dict setObject:self.ordering forKey:@"09_ordering" defaultObject:nil];
    [dict setObject:self.defaultsDictionary forKey:@"10_defaultsDictionary" defaultObject:nil];
    [dict setObject:self.defaultsArray forKey:@"11_defaultsArray" defaultObject:nil];
    [dict setObject:self.iconImage forKey:@"12_iconImage" defaultObject:nil];
    return dict;
}

@end
