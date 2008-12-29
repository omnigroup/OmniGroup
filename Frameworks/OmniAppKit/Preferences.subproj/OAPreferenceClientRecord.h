// Copyright 1997-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniAppKit/Preferences.subproj/OAPreferenceClientRecord.h 68913 2005-10-03 19:36:19Z kc $

#import <OmniFoundation/OFObject.h>

@class NSArray, NSDictionary, NSNumber;
@class NSImage;
@class OAPreferenceClient, OAPreferenceController;

@interface OAPreferenceClientRecord : OFObject
{
    NSString *categoryName;
    NSString *identifier;
    NSString *className;
    NSString *title;
    NSString *shortTitle;
    NSString *iconName;
    NSString *nibName;
    NSString *helpURL;
    NSNumber *ordering;
    NSDictionary *defaultsDictionary;
    NSArray *defaultsArray;
    NSImage *iconImage;
}

- (id)initWithCategoryName:(NSString *)newName;
    // Designated initializer.

- (NSImage *)iconImage;

- (NSString *)categoryName;
- (NSString *)identifier;
- (NSString *)className;
- (NSString *)title;
- (NSString *)shortTitle;
- (NSString *)iconName;
- (NSString *)nibName;
- (NSString *)helpURL;
- (NSNumber *)ordering;
- (NSDictionary *)defaultsDictionary;
- (NSArray *)defaultsArray;

- (void)setIdentifier:(NSString *)newIdentifier;
- (void)setClassName:(NSString *)newClassName;
- (void)setTitle:(NSString *)newTitle;
- (void)setShortTitle:(NSString *)newShortTitle;
- (void)setIconName:(NSString *)newIconName;
- (void)setNibName:(NSString *)newNibName;
- (void)setHelpURL:(NSString *)newHelpURL;
- (void)setOrdering:(NSNumber *)newOrdering;
- (void)setDefaultsDictionary:(NSDictionary *)newDefaultsDictionary;
- (void)setDefaultsArray:(NSArray *)newDefaultsArray;

- (NSComparisonResult)compare:(OAPreferenceClientRecord *)other;

- (OAPreferenceClient *)createClientInstanceInController:(OAPreferenceController *)controller;


@end
