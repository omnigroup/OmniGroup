// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

extern void OFProcessICUDateFormatStringWithComponentHandler(NSString *formatString, void (^componentHandler)(NSString *component, BOOL isLiteral)); // Scans  an ICU-compliant date format string and calls the handler for each component, along with a flag to let the handler know whether or not the component is a string literal as opposed to an actual format string
extern NSArray *OFComponentsFromICUDateFormatString(NSString *formatString); // Returns an array of the individual components (including string literals) of an ICU-compliant date format string
extern NSString *OFDateFormatStringForOldFormatString(NSString *oldFormat); // 10.0 strftime-like format to ICU format
extern NSString *OFOldDateFormatStringForFormatString(NSString *newFormat); // ICU to 10.0 strftime-like format
