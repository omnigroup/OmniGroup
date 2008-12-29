// Copyright 1997-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniFoundation/OFBundledClass.h 68913 2005-10-03 19:36:19Z kc $

#import <OmniFoundation/OFObject.h>

@class NSArray, NSBundle, NSMutableArray;

@interface OFBundledClass : OFObject
{
    Class bundleClass;
    NSString *className;
    NSBundle *bundle;
    NSDictionary *descriptionDictionary;
    NSMutableArray *dependencyClassNames;
    NSMutableArray *modifyingBundledClasses;
    BOOL loaded;
}

+ (Class)classNamed:(NSString *)aClassName;
+ (NSBundle *)bundleForClassNamed:(NSString *)aClassName;
+ (OFBundledClass *)bundledClassNamed:(NSString *)aClassName;

+ (OFBundledClass *)createBundledClassWithName:(NSString *)aClassName bundle:(NSBundle *)aBundle description:(NSDictionary *)aDescription;

+ (NSString *)didLoadNotification;

+ (void)processImmediateLoadClasses;
+ (void)loadAllClasses;

// Access methods

- (NSString *)className;
- (Class)bundledClass;
- (NSBundle *)bundle;
- (BOOL)isLoaded;
- (NSDictionary *) descriptionDictionary;
- (NSArray *)dependencyClassNames;
- (NSArray *)modifyingBundledClasses;

// Actions

- (void)loadBundledClass;

@end
