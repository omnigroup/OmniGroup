// Copyright 1997-2005, 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniAppKit/OpenStepExtensions.subproj/NSPopUpButton-OAExtensions.h 104581 2008-09-06 21:18:23Z kc $

#import <AppKit/NSPopUpButton.h>

@interface NSPopUpButton (OAExtensions)
- (void)selectItemWithRepresentedObject:(id)object;
- (NSMenuItem *)itemWithTag:(int)tag;
- (void)addRepresentedObjects:(NSArray *)objects titleSelector:(SEL)titleSelector;
- (void)addRepresentedObjects:(NSArray *)objects titleKeyPath:(NSString *)keyPath;
@end
