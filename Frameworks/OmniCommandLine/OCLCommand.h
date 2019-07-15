// Copyright 2008-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>

@class OCLCommandArguments;

typedef void (^OCLCommandBlock)(OCLCommandArguments *args);

@interface OCLCommand : NSObject

+ (instancetype)command;

- (void)group:(NSString *)name with:(void (^)(void))addCommands;
- (void)add:(NSString *)specification with:(void (^)(void))handleCommand;

- (void)usage;
- (void)error:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2);

- (void)runWithArguments:(NSArray *)argumentStrings;

// For argument lookup
- (id)objectForKeyedSubscript:(id)key;

@end

extern void OCLCommandLog(NSString *format, ...) NS_FORMAT_FUNCTION(1,2);
