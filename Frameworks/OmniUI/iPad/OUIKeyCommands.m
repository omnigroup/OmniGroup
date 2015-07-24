// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIKeyCommands.h>

#import <OmniBase/OmniBase.h>
#import <Foundation/Foundation.h>

RCS_ID("$Id$");

@implementation OUIKeyCommands

static NSMutableDictionary *CategoriesToKeyCommands = nil;

static NSArray *_parseKeyCommands(NSDictionary *commands)
{
    /*
     We use a similar syntax as /System/Library/Frameworks/AppKit.framework/Resources/StandardKeyBinding.dict on the Mac
     
     ^ = control
     $ = shift
     @ = command
     ~ = alternate
     
     TODO: Add UIKeyModifierAlphaShift and UIKeyModifierNumericPad mappings
     
     After the flag specification there is a single character. The value of each dictionary pair is the name of an action (the Mac allows a list, but UIKeyCommand does not).
     
     */
    NSCharacterSet *nonModifierCharacterSet = [[NSCharacterSet characterSetWithCharactersInString:@"^$@~"] invertedSet];

    NSMutableArray *result = [NSMutableArray new];
    [commands enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *selectorName, BOOL *stop) {
        __block UIKeyModifierFlags flags = 0;
        
        // Have to leave at least one character (so ^@ would be valid -- at least on a keyboard where '@' is not shifted).
        NSUInteger inputStart;
        {
            NSRange allowedModifierRange = NSMakeRange(0, [key length] - 1);
            
            NSRange nonModifierRange = [key rangeOfCharacterFromSet:nonModifierCharacterSet options:0 range:allowedModifierRange];
            if (nonModifierRange.location == NSNotFound)
                inputStart = NSMaxRange(allowedModifierRange); // All the characters up front are modifiers
            else
                inputStart = nonModifierRange.location;
        }
        
        [[key substringToIndex:inputStart] enumerateSubstringsInRange:NSMakeRange(0, inputStart) options:NSStringEnumerationByComposedCharacterSequences usingBlock:^(NSString *substring, NSRange substringRange, NSRange enclosingRange, BOOL *stop) {
            if ([substring isEqualToString:@"$"])
                flags |= UIKeyModifierShift;
            else if ([substring isEqualToString:@"^"])
                flags |= UIKeyModifierControl;
            else if ([substring isEqualToString:@"~"])
                flags |= UIKeyModifierAlternate;
            else if ([substring isEqualToString:@"@"])
                flags |= UIKeyModifierCommand;
            else
                NSLog(@"Unknown key command modifier flag \"%@\".", substring);
        }];
        
        NSString *input = [key substringFromIndex:inputStart];
        
        if ([input isEqualToString:@"up"])
            input = UIKeyInputUpArrow;
        else if ([input isEqualToString:@"down"])
            input = UIKeyInputDownArrow;
        else if ([input isEqualToString:@"left"])
            input = UIKeyInputLeftArrow;
        else if ([input isEqualToString:@"right"])
            input = UIKeyInputRightArrow;
        else if ([input isEqualToString:@"escape"])
            input = UIKeyInputEscape;
        else {
            OBASSERT([input length] == 1, "Input portion of key command string \"%@\" should be a single character", key);
        }
        OBASSERT([selectorName rangeOfString:@":"].location == [selectorName length] - 1, "Selector \"%@\" should have one \":\" at the end.", selectorName);
        
        UIKeyCommand *command = [UIKeyCommand keyCommandWithInput:input modifierFlags:flags action:NSSelectorFromString(selectorName)];
        [result addObject:command];
    }];

    return result;
}

+ (void)initialize;
{
    OBINITIALIZE;
    
    CategoriesToKeyCommands = [NSMutableDictionary new];
    
    // Each file should have the structure { category = ( list of commands ); }
    NSMutableArray *bundles = [[NSBundle allFrameworks] mutableCopy]; // On iOS 8 and iOS 9, +allFrameworks includes +mainBundle.
    if ([bundles containsObject:[NSBundle mainBundle]] == NO)
        [bundles addObject:[NSBundle mainBundle]]; // but let's be safe in case they fix the bug.
    
    NSMutableArray *keyCommandsFileURLs = [NSMutableArray array];
    for (NSBundle *bundle in bundles) {
        [keyCommandsFileURLs addObjectsFromArray:[bundle URLsForResourcesWithExtension:@"keycommands" subdirectory:nil]];
    }
    
    for (NSURL *keyCommandFileURL in keyCommandsFileURLs) {
        __autoreleasing NSError *error = nil;
        
        NSData *keyCommandData = [[NSData alloc] initWithContentsOfURL:keyCommandFileURL options:NSDataReadingMappedIfSafe error:&error];
        if (!keyCommandData) {
            [error log:@"Error reading data from %@", keyCommandFileURL];
            continue;
        }
        
        error = nil;
        NSDictionary *keyCommands = [NSPropertyListSerialization propertyListWithData:keyCommandData options:0 format:NULL error:&error];
        if (!keyCommands) {
            [error log:@"Error deserializing data from %@", keyCommandFileURL];
            continue;
        }
        
        [keyCommands enumerateKeysAndObjectsUsingBlock:^(NSString *categoryName, NSDictionary *keyCommandDescriptions, BOOL *stop) {
            NSArray *keyCommands = _parseKeyCommands(keyCommandDescriptions);
            
            // TODO: Check for duplicates
            NSArray *previousCommands = CategoriesToKeyCommands[categoryName];
            if (previousCommands)
                keyCommands = [previousCommands arrayByAddingObjectsFromArray:keyCommands];
            CategoriesToKeyCommands[categoryName] = keyCommands;
        }];
    }
}

+ (NSArray *)keyCommandsWithCategories:(NSString *)categories;
{
    NSArray *commands = CategoriesToKeyCommands[categories];
    if (commands)
        return commands;
    
    NSMutableArray *mergedCommands = [NSMutableArray new];
    NSArray *categoryNames = [categories componentsSeparatedByString:@","];
    for (NSString *categoryName in categoryNames) {
        commands = CategoriesToKeyCommands[categoryName];
        if (!commands) {
            NSLog(@"No key command category named \"%@\".", categoryName);
            continue;
        }
        
        [mergedCommands addObjectsFromArray:commands];
    }
    
    commands = [mergedCommands copy];
    
    CategoriesToKeyCommands[categories] = commands;
    return commands;
}

@end
