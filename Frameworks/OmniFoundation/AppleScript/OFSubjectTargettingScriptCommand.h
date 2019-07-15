// Copyright 2007-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSScriptStandardSuiteCommands.h>

@interface NSScriptCommand (OFSubjectTargetting)
- (void)targetSubject;
@end

@interface OFSubjectTargettingScriptCommand : NSScriptCommand
@end

// Specify this as the class in your sdef for delete and lists will be supported with the subject as the command handler. But, the subject also needs to respond to the selector (it's going to handle the command rather than letting the normal delete command handle it).
@interface OFSubjectTargettingDeleteCommand : NSDeleteCommand
@end
