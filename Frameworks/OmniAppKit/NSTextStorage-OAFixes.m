// Copyright 2015-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#else
#import <AppKit/NSTextStorage.h>
#endif

#import <OmniBase/OmniBase.h>

#ifdef OMNI_ASSERTIONS_ON

RCS_ID("$Id$")

static void (*original_addLayoutManager)(NSTextStorage *self, SEL _cmd, NSLayoutManager *layoutManager) = NULL;
static void (*original_removeLayoutManager)(NSTextStorage *self, SEL _cmd, NSLayoutManager *layoutManager) = NULL;

// Adding the same layout manager twice will silently work OK for display-only purposes, but if you edit the text storage, the layout manager will be told about the change twice and get corrupted
static void replacement_addLayoutManager(NSTextStorage *self, SEL _cmd, NSLayoutManager *layoutManager)
{
    OBPRECONDITION([self.layoutManagers containsObject:layoutManager] == NO);
    original_addLayoutManager(self, _cmd, layoutManager);
}

// Removing a layout manager that isn't attached to a text storage is probably a logic error, so flag it as such.
static void replacement_removeLayoutManager(NSTextStorage *self, SEL _cmd, NSLayoutManager *layoutManager)
{
    OBPRECONDITION([self.layoutManagers containsObject:layoutManager]);
    original_removeLayoutManager(self, _cmd, layoutManager);
}

static void OAInstallTextStorageAssertions(void) __attribute__((constructor));
static void OAInstallTextStorageAssertions(void)
{
    @autoreleasepool {
        Class cls = [NSTextStorage class];
        
        original_addLayoutManager = (typeof(original_addLayoutManager))OBReplaceMethodImplementation(cls, @selector(addLayoutManager:), (IMP)replacement_addLayoutManager);
        original_removeLayoutManager = (typeof(original_removeLayoutManager))OBReplaceMethodImplementation(cls, @selector(removeLayoutManager:), (IMP)replacement_removeLayoutManager);
    }
}

#endif
