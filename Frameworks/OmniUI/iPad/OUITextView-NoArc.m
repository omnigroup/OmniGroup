// Copyright 2010-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUITextView-NoArc.h"

RCS_ID("$Id$")

// Hack needed for our -replaceTextStorage:, which can't be compiled in ARC mode.
void OUITextViewFixTextStorageIvar(OUITextView *self, NSTextStorage *oldTextStorage, NSTextStorage *textStorage)
{
    // iOS 7b2 -- 14219787: TextKit: Allow replacing the text storage on a xib-created UITextView

    // Really, the issue is that they cache the initial text storage rather that doing what the documentation claims -- derive it from the text container.
    // Hacking this for now, assuming this will get fixed for final...
    OBASSERT(self.textStorage == oldTextStorage, "Bug is fixed!");
    
    Ivar textStorageIvar = object_setInstanceVariable(self, "_textStorage", textStorage);
    OBASSERT(textStorageIvar);
    OB_UNUSED_VALUE(textStorageIvar);
    
    // Fix ref counting
    OBStrongRetain(textStorage);
    OBStrongRelease(oldTextStorage);
}
