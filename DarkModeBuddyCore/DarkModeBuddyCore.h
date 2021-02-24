//
//  DarkModeBuddyCore.h
//  DarkModeBuddyCore
//
//  Created by Guilherme Rambo on 23/02/21.
//

#import <Foundation/Foundation.h>

//! Project version number for DarkModeBuddyCore.
FOUNDATION_EXPORT double DarkModeBuddyCoreVersionNumber;

//! Project version string for DarkModeBuddyCore.
FOUNDATION_EXPORT const unsigned char DarkModeBuddyCoreVersionString[];

// In this header, you should import all the public headers of your framework using statements like #import <DarkModeBuddyCore/PublicHeader.h>

extern int SLSGetAppearanceThemeLegacy(void);
extern void SLSSetAppearanceThemeLegacy(int);

#define kDarkModeBuddyCoreSubsystemName "codes.rambo.DarkModeBuddyCore"

#import <DarkModeBuddyCore/DMBAmbientLightSensor.h>
#import <DarkModeBuddyCore/SharedFileList.h>
