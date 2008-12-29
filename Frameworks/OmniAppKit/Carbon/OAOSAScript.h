// Copyright 2002-2005, 2007 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniAppKit/Carbon/OAOSAScript.h 93428 2007-10-25 16:36:11Z kc $

#if !defined(MAC_OS_X_VERSION_10_5) || MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_5

#import <Foundation/NSObject.h>
#import <AppKit/NSNibDeclarations.h> // For IBOutlet

@class NSString, NSData, NSAttributedString, NSArray;
@class NSWindow, NSProgressIndicator;

@interface OAOSAScript : NSObject 
{
    IBOutlet NSWindow *scriptSheet;
    IBOutlet NSProgressIndicator *progressIndicator;
    NSWindow *runAttachedWindow;

    unsigned long int scriptID;           /* The OSAID of our compiled script */
    unsigned long int scriptContextID;    /* The OSAID of the script execution context */
}

+ (NSString *)executeScriptString:(NSString *)scriptString;
+ (OAOSAScript *)runningScript;

- init;
- initWithPath:(NSString *)scriptPath;
- initWithData:(NSData *)compiledData;
- initWithSourceCode:(NSString *)sourceText;

- (BOOL)isValid;

- (NSString *)sourceCode;
- (void)setSourceCode:(NSString *)someSource;

- (void)setProperty:(NSString *)propName toString:(NSString *)value;
- valueOfProperty:(NSString *)propName;

- (NSString *)execute;
- (NSString *)executeWithInterfaceOnWindow:(NSWindow *)aWindow;

- (IBAction)stopScript:(id)sender;

- (NSData *)compiledData;


@end

extern NSString *OSAScriptException;
extern NSString *OSAScriptExceptionSourceRangeKey;

#endif
