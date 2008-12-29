// Copyright 2007 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniAppKit/Bindings/OATextFieldBinder.h 84394 2007-03-06 20:14:23Z wiml $

#import <OmniBase/OBObject.h>
#import <AppKit/NSNibDeclarations.h>

@class NSTextField, NSString;

/*
 OATextFieldBinder works around the problem of an NSTextField that has a formatter and a binding: if the formatter fails, the textfield puts up two identical dialog boxes with horrible wording and two different buttons (each) that do the same thing. This is undocumented and there doesn't seem to be a way to turn it off or supply your own validation behavior. So the OATextFieldBinder lets you configure the text field to use the old-fashioned target-action mechanism, but it observes a key path so you can still get the convenience of KVO.

You can instantiate one of these in IB and hook it up, but you'll still need to call -setKeyPath: to tell it what key path to observe on its subject.

The bound field's delegate should be some other object that responds to the usual control:blahBlah: methods.
*/

@interface OATextFieldBinder : OBObject
{
    IBOutlet NSTextField *boundField;
    
    IBOutlet NSObject *subject;
    NSString *keyPath;
    
    BOOL observing;
    BOOL settingValue;
}

/* Methods for configuring the OATextFieldBinder */
- (void)setSubject:(NSObject *)s;
- (void)setKeyPath:(NSString *)newKeyPath;
- (void)setBoundField:(NSTextField *)f;

/* Action method invoked by the text field */
- (IBAction)uiChangedValue:sender;

@end

